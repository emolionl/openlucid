"""Raw recording files of a night: upload, list, download, delete.

The files live on disk (see app/storage.py); the database only keeps their metadata.
Another user's night or recording always answers 404, as if it did not exist.
"""

import uuid

from fastapi import APIRouter, HTTPException, Request, status
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import FileResponse, Response
from sqlalchemy import func, select
from sqlalchemy.orm import Session
from starlette.background import BackgroundTask

from app import storage
from app.deps import AppSettings, CurrentUser, DbSession, PageParams
from app.models import RECORDING_KINDS, Night, Recording, User
from app.schemas import Page, RecordingOut

router = APIRouter(tags=["recordings"])

MEDIA_TYPES = {"edf": "application/octet-stream", "raw_csv": "text/csv", "other": "application/octet-stream"}

# The upload reads the request body itself (to stream it), so its form is described here for /docs.
UPLOAD_OPENAPI = {
    "requestBody": {
        "required": True,
        "content": {
            "multipart/form-data": {
                "schema": {
                    "type": "object",
                    "required": ["file", "kind"],
                    "properties": {
                        "file": {"type": "string", "format": "binary"},
                        "kind": {"type": "string", "enum": list(RECORDING_KINDS)},
                    },
                }
            }
        },
    }
}


def own_night(db: Session, user: User, night_id: uuid.UUID) -> Night:
    night = db.scalar(select(Night).where(Night.id == night_id, Night.user_id == user.id))
    if night is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Night not found.")
    return night


def own_recording(db: Session, user: User, recording_id: uuid.UUID) -> Recording:
    recording = db.scalar(
        select(Recording).join(Night).where(Recording.id == recording_id, Night.user_id == user.id)
    )
    if recording is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Recording not found.")
    return recording


def save_recording(db: Session, recording: Recording) -> Recording:
    db.add(recording)
    db.commit()
    return recording


@router.post(
    "/nights/{night_id}/recordings",
    status_code=status.HTTP_201_CREATED,
    response_model=RecordingOut,
    openapi_extra=UPLOAD_OPENAPI,
    responses={413: {"description": "The file is bigger than the upload limit."}},
)
async def upload_recording(
    night_id: uuid.UUID, request: Request, user: CurrentUser, db: DbSession, settings: AppSettings
) -> Recording:
    """Upload a raw recording (EDF, raw CSV or other) of one of your nights.

    Send multipart/form-data with `file` and `kind`. The file is streamed to disk and its sha256
    computed on the way, so large files are fine up to OPENLUCID_MAX_UPLOAD_MB.
    """
    await run_in_threadpool(own_night, db, user, night_id)
    recording_id = uuid.uuid4()
    try:
        stored = await storage.receive_upload(
            request.stream(),
            request.headers,
            data_dir=settings.data_dir,
            user_id=user.id,
            night_id=night_id,
            recording_id=recording_id,
            max_bytes=settings.max_upload_bytes,
            allowed_kinds=RECORDING_KINDS,
        )
    except storage.UploadTooLarge:
        raise HTTPException(
            status.HTTP_413_CONTENT_TOO_LARGE,
            detail=f"The file is too big; the limit is {settings.max_upload_mb} MB.",
        ) from None
    except storage.InvalidUpload as error:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, detail=str(error)) from None

    recording = Recording(
        id=recording_id,
        night_id=night_id,
        kind=stored.kind,
        original_filename=stored.original_filename,
        size_bytes=stored.size_bytes,
        sha256=stored.sha256,
        storage_path=stored.storage_path,
    )
    try:
        return await run_in_threadpool(save_recording, db, recording)
    except BaseException:
        # Without its row nobody could ever reach the file, so don't keep it.
        storage.delete_recording_file(settings.data_dir, stored.storage_path)
        raise


@router.get("/nights/{night_id}/recordings", response_model=Page[RecordingOut])
def list_recordings(night_id: uuid.UUID, user: CurrentUser, db: DbSession, page: PageParams) -> dict:
    """The recordings of one of your nights, newest first."""
    own_night(db, user, night_id)
    total = db.scalar(select(func.count()).select_from(Recording).where(Recording.night_id == night_id))
    items = db.scalars(
        select(Recording)
        .where(Recording.night_id == night_id)
        .order_by(Recording.uploaded_at.desc(), Recording.id)
        .limit(page.limit)
        .offset(page.offset)
    ).all()
    return {"items": items, "total": total}


@router.get(
    "/recordings/{recording_id}/download",
    response_class=FileResponse,
    responses={200: {"content": {"application/octet-stream": {}, "text/csv": {}}}},
)
def download_recording(
    recording_id: uuid.UUID, user: CurrentUser, db: DbSession, settings: AppSettings
) -> FileResponse:
    """Download one of your recording files, byte for byte as it was uploaded."""
    recording = own_recording(db, user, recording_id)
    try:
        path = storage.resolve_storage_path(settings.data_dir, recording.storage_path)
    except ValueError:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Recording not found.") from None
    if not path.is_file():
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="The file of this recording is missing on the server.")
    return FileResponse(
        path,
        media_type=MEDIA_TYPES.get(recording.kind, "application/octet-stream"),
        filename=recording.original_filename,
        # A download holds its file open; on Windows a delete during that time has to wait for it.
        background=BackgroundTask(storage.retry_pending_deletions, settings.data_dir),
    )


@router.delete("/recordings/{recording_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_recording(recording_id: uuid.UUID, user: CurrentUser, db: DbSession, settings: AppSettings) -> Response:
    """Delete one of your recordings: its metadata and the file on disk."""
    recording = own_recording(db, user, recording_id)
    storage_path = recording.storage_path
    db.delete(recording)
    db.commit()
    storage.delete_recording_file(settings.data_dir, storage_path)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
