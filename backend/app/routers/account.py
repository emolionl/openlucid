"""The signed-in user's own account: profile, password, export and deletion (/me)."""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app import storage
from app.db import utcnow
from app.deps import AppSettings, CurrentUser, DbSession, get_login_guard
from app.models import JournalEntry, Night, Recording, User
from app.schemas import AccountDeleteIn, ExportOut, MeUpdate, PasswordChangeIn, UserOut
from app.security import LoginGuard, TooManyFailures, hash_password, revoke_all_refresh_tokens, verify_password

router = APIRouter(prefix="/me", tags=["account"])

WRONG_PASSWORD = "The password is not right."
EXPORT_FILENAME = "openlucid-export.json"
Guard = Annotated[LoginGuard, Depends(get_login_guard)]


def _check_password(user: User, password: str, request: Request, guard: LoginGuard) -> None:
    """Make sure the signed-in person knows the password. Counts towards the login rate limits.

    Raises 429 when there were too many failures, 403 on a wrong password.
    """
    client_ip = request.client.host if request.client else "unknown"
    try:
        attempt = guard.begin(user.email, client_ip)
    except TooManyFailures as blocked:
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many wrong passwords. Please wait a while and try again.",
            headers={"Retry-After": str(blocked.retry_after)},
        ) from None
    if not verify_password(user.password_hash, password):
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail=WRONG_PASSWORD)
    guard.succeeded(attempt)


@router.get("", response_model=UserOut)
def get_me(user: CurrentUser) -> User:
    """Your own account."""
    return user


@router.patch("", response_model=UserOut)
def update_me(body: MeUpdate, user: CurrentUser, db: DbSession) -> User:
    """Change your display name. Send `null` to remove it; leave the field out to keep it."""
    if "display_name" in body.model_fields_set:
        user.display_name = body.display_name
    db.commit()
    return user


@router.post("/password", status_code=status.HTTP_204_NO_CONTENT)
def change_password(
    body: PasswordChangeIn, request: Request, user: CurrentUser, db: DbSession, guard: Guard
) -> Response:
    """Set a new password. Every device is signed out (all refresh tokens stop working)."""
    _check_password(user, body.current_password, request, guard)
    user.password_hash = hash_password(body.new_password)
    revoke_all_refresh_tokens(db, user.id)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/export", response_model=ExportOut)
def export_me(user: CurrentUser, db: DbSession, response: Response) -> ExportOut:
    """Download everything stored about you as one JSON file (recording files themselves are not included)."""
    nights = db.scalars(
        select(Night)
        .where(Night.user_id == user.id)
        .options(selectinload(Night.epochs), selectinload(Night.events))
        .order_by(Night.started_at)
    ).all()
    journal_entries = db.scalars(
        select(JournalEntry).where(JournalEntry.user_id == user.id).order_by(JournalEntry.written_at)
    ).all()
    recordings = db.scalars(
        select(Recording).join(Night).where(Night.user_id == user.id).order_by(Recording.uploaded_at)
    ).all()
    response.headers["Content-Disposition"] = f'attachment; filename="{EXPORT_FILENAME}"'
    return ExportOut.model_validate(
        {
            "exported_at": utcnow(),
            "user": user,
            "nights": nights,
            "journal_entries": journal_entries,
            "recordings": recordings,
        },
        from_attributes=True,
    )


@router.delete("", status_code=status.HTTP_204_NO_CONTENT)
def delete_me(
    body: AccountDeleteIn,
    request: Request,
    user: CurrentUser,
    db: DbSession,
    settings: AppSettings,
    guard: Guard,
) -> Response:
    """Delete your account for good: every night, epoch, event, journal entry and recording file.

    This cannot be undone. Download an export first if you want to keep anything.
    """
    _check_password(user, body.password, request, guard)
    file_paths = list(db.scalars(select(Recording.storage_path).join(Night).where(Night.user_id == user.id)))
    user_id = user.id
    db.delete(user)
    db.commit()
    # Files go only after the rows are gone, so a failed commit never leaves rows without files.
    storage.delete_recording_files(settings.data_dir, file_paths)
    storage.delete_user_files(settings.data_dir, user_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
