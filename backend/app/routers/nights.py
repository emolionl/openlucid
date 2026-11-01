"""Nights with their epochs, events and summary (/nights).

Everything here is scoped to the signed-in user: another user's night answers 404, as if it did not exist.
Creating nights and events is idempotent through a client-generated `client_id`, and epochs are upserted
by their index, so the app can safely upload the same data twice after being offline.
"""

import uuid
from collections import defaultdict
from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, Response, status
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app import storage
from app.deps import AppSettings, CurrentUser, DbSession, EpochPageParams, PageParams
from app.models import Epoch, Event, Night, Recording, User
from app.schemas import (
    EpochOut,
    EpochsUpsertIn,
    EpochsUpsertOut,
    EventOut,
    EventsCreateIn,
    EventsCreateOut,
    NightCreate,
    NightOut,
    NightSummaryOut,
    NightUpdate,
    Page,
    PlainText,
)

router = APIRouter(prefix="/nights", tags=["nights"])

NIGHT_NOT_FOUND = "Night not found."
EPOCH_MINUTES = 0.5  # every epoch is 30 seconds


def _own_night(db: Session, user: User, night_id: uuid.UUID) -> Night:
    """The night with this id if it belongs to `user`, else 404 (never reveal other users' nights)."""
    night = db.scalar(select(Night).where(Night.id == night_id, Night.user_id == user.id))
    if night is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail=NIGHT_NOT_FOUND)
    return night


def _night_by_client_id(db: Session, user: User, client_id: str) -> Night | None:
    return db.scalar(select(Night).where(Night.user_id == user.id, Night.client_id == client_id))


# --- nights -------------------------------------------------------------------------------


@router.get("", response_model=Page[NightOut])
def list_nights(user: CurrentUser, db: DbSession, page: PageParams) -> Page[NightOut]:
    """Your nights, newest first."""
    total = db.scalar(select(func.count()).select_from(Night).where(Night.user_id == user.id))
    nights = db.scalars(
        select(Night)
        .where(Night.user_id == user.id)
        .order_by(Night.started_at.desc(), Night.created_at.desc())
        .limit(page.limit)
        .offset(page.offset)
    ).all()
    return Page[NightOut](items=[NightOut.model_validate(night) for night in nights], total=total or 0)


@router.post("", response_model=NightOut, status_code=status.HTTP_201_CREATED)
def create_night(body: NightCreate, user: CurrentUser, db: DbSession, response: Response) -> Night:
    """Start a night. Sending the same `client_id` again returns the existing night (200) instead of a copy."""
    if body.client_id is not None:
        existing = _night_by_client_id(db, user, body.client_id)
        if existing is not None:
            response.status_code = status.HTTP_200_OK
            return existing
    night = Night(user_id=user.id, **body.model_dump())
    db.add(night)
    try:
        db.commit()
    except IntegrityError:
        # Two uploads of the same night raced each other; the other one won.
        db.rollback()
        existing = _night_by_client_id(db, user, body.client_id) if body.client_id else None
        if existing is None:
            raise
        response.status_code = status.HTTP_200_OK
        return existing
    return night


@router.get("/{night_id}", response_model=NightOut)
def get_night(night_id: uuid.UUID, user: CurrentUser, db: DbSession) -> Night:
    return _own_night(db, user, night_id)


@router.patch("/{night_id}", response_model=NightOut)
def update_night(night_id: uuid.UUID, body: NightUpdate, user: CurrentUser, db: DbSession) -> Night:
    """Change the end time, notes or firmware. Only the fields you send are changed."""
    night = _own_night(db, user, night_id)
    changes = body.model_dump(exclude_unset=True)
    ended_at = changes.get("ended_at")
    if ended_at is not None and ended_at < night.started_at:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, detail="ended_at cannot be before started_at.")
    for field, value in changes.items():
        setattr(night, field, value)
    db.commit()
    return night


@router.delete("/{night_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_night(night_id: uuid.UUID, user: CurrentUser, db: DbSession, settings: AppSettings) -> Response:
    """Delete a night with its epochs, events, recordings and the recording files on disk."""
    night = _own_night(db, user, night_id)
    file_paths = list(db.scalars(select(Recording.storage_path).where(Recording.night_id == night.id)))
    db.delete(night)
    db.commit()
    # Files go only after the rows are gone, so a failed commit never leaves rows without files.
    storage.delete_recording_files(settings.data_dir, file_paths)
    storage.delete_night_files(settings.data_dir, user.id, night_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/{night_id}/summary", response_model=NightSummaryOut)
def night_summary(night_id: uuid.UUID, user: CurrentUser, db: DbSession) -> NightSummaryOut:
    """Totals of one night: minutes per sleep stage, events per type and mean contact per channel."""
    night = _own_night(db, user, night_id)

    stage_counts = db.execute(
        select(Epoch.stage, func.count())
        .where(Epoch.night_id == night.id, Epoch.stage.is_not(None))
        .group_by(Epoch.stage)
    ).all()
    event_counts = db.execute(
        select(Event.type, func.count()).where(Event.night_id == night.id).group_by(Event.type)
    ).all()
    epoch_count = db.scalar(select(func.count()).select_from(Epoch).where(Epoch.night_id == night.id))
    recording_count = db.scalar(
        select(func.count()).select_from(Recording).where(Recording.night_id == night.id)
    )

    contact_sums: dict[str, float] = defaultdict(float)
    contact_counts: dict[str, int] = defaultdict(int)
    for contact in db.scalars(select(Epoch.contact).where(Epoch.night_id == night.id)):
        for channel, score in (contact or {}).items():
            contact_sums[channel] += score
            contact_counts[channel] += 1

    return NightSummaryOut(
        night=NightOut.model_validate(night),
        epoch_count=epoch_count or 0,
        stage_minutes={stage: count * EPOCH_MINUTES for stage, count in stage_counts},
        event_counts={event_type: count for event_type, count in event_counts},
        contact_average={
            # Rounded so summing many floats does not show up as 0.9000000000000017.
            channel: round(contact_sums[channel] / contact_counts[channel], 4)
            for channel in contact_sums
        },
        recordings=recording_count or 0,
    )


# --- epochs -------------------------------------------------------------------------------


def _upsert_epochs(db: Session, night_id: uuid.UUID, body: EpochsUpsertIn) -> int:
    # The same index twice in one batch: the last one wins.
    incoming = {epoch.index: epoch for epoch in body.epochs}
    existing = {
        epoch.index: epoch
        for epoch in db.scalars(select(Epoch).where(Epoch.night_id == night_id, Epoch.index.in_(incoming)))
    }
    for index, epoch_in in incoming.items():
        values = epoch_in.model_dump()
        row = existing.get(index)
        if row is None:
            db.add(Epoch(night_id=night_id, **values))
        else:
            for field, value in values.items():
                setattr(row, field, value)
    db.commit()
    return len(incoming)


@router.put("/{night_id}/epochs", response_model=EpochsUpsertOut)
def upsert_epochs(night_id: uuid.UUID, body: EpochsUpsertIn, user: CurrentUser, db: DbSession) -> EpochsUpsertOut:
    """Add or replace up to 1000 epochs. An epoch with an index that already exists is updated."""
    night_id = _own_night(db, user, night_id).id
    try:
        upserted = _upsert_epochs(db, night_id, body)
    except IntegrityError:
        # Another upload inserted some of these indexes at the same moment; once more updates them.
        db.rollback()
        upserted = _upsert_epochs(db, night_id, body)
    return EpochsUpsertOut(upserted=upserted)


@router.get("/{night_id}/epochs", response_model=Page[EpochOut])
def list_epochs(
    night_id: uuid.UUID,
    user: CurrentUser,
    db: DbSession,
    page: EpochPageParams,
    from_index: Annotated[int | None, Query(ge=0)] = None,
    to_index: Annotated[int | None, Query(ge=0)] = None,
) -> Page[EpochOut]:
    """Epochs ordered by index. `from_index` and `to_index` are both included."""
    night = _own_night(db, user, night_id)
    conditions = [Epoch.night_id == night.id]
    if from_index is not None:
        conditions.append(Epoch.index >= from_index)
    if to_index is not None:
        conditions.append(Epoch.index <= to_index)
    total = db.scalar(select(func.count()).select_from(Epoch).where(*conditions))
    epochs = db.scalars(
        select(Epoch).where(*conditions).order_by(Epoch.index).limit(page.limit).offset(page.offset)
    ).all()
    return Page[EpochOut](items=[EpochOut.model_validate(epoch) for epoch in epochs], total=total or 0)


# --- events -------------------------------------------------------------------------------


def _create_events(db: Session, night_id: uuid.UUID, body: EventsCreateIn) -> EventsCreateOut:
    client_ids = {event.client_id for event in body.events if event.client_id is not None}
    known = set(
        db.scalars(select(Event.client_id).where(Event.night_id == night_id, Event.client_id.in_(client_ids)))
    )
    created = existing = 0
    for event_in in body.events:
        if event_in.client_id is not None and event_in.client_id in known:
            existing += 1
            continue
        db.add(Event(night_id=night_id, **event_in.model_dump()))
        if event_in.client_id is not None:
            known.add(event_in.client_id)  # the same client_id twice in one batch is stored once
        created += 1
    db.commit()
    return EventsCreateOut(created=created, existing=existing)


@router.post("/{night_id}/events", response_model=EventsCreateOut)
def create_events(night_id: uuid.UUID, body: EventsCreateIn, user: CurrentUser, db: DbSession) -> EventsCreateOut:
    """Add up to 500 events. Events whose `client_id` is already stored are counted as existing, not copied."""
    night_id = _own_night(db, user, night_id).id
    try:
        return _create_events(db, night_id, body)
    except IntegrityError:
        # A parallel upload stored some of the same events first; once more skips them.
        db.rollback()
        return _create_events(db, night_id, body)


@router.get("/{night_id}/events", response_model=Page[EventOut])
def list_events(
    night_id: uuid.UUID,
    user: CurrentUser,
    db: DbSession,
    page: PageParams,
    event_type: Annotated[PlainText | None, Query(alias="type", max_length=40)] = None,
) -> Page[EventOut]:
    """Events ordered by time, optionally only one `type`."""
    night = _own_night(db, user, night_id)
    conditions = [Event.night_id == night.id]
    if event_type is not None:
        conditions.append(Event.type == event_type)
    total = db.scalar(select(func.count()).select_from(Event).where(*conditions))
    events = db.scalars(
        select(Event)
        .where(*conditions)
        .order_by(Event.at, Event.created_at, Event.id)
        .limit(page.limit)
        .offset(page.offset)
    ).all()
    return Page[EventOut](items=[EventOut.model_validate(event) for event in events], total=total or 0)
