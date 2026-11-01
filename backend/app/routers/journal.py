"""The dream journal (/journal).

An entry may point to one of the user's own nights (`night_id`). Deleting that night keeps the entry
and sets its `night_id` to null (ON DELETE SET NULL in the database).
"""

import uuid

from fastapi import APIRouter, HTTPException, Response, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db import utcnow
from app.deps import CurrentUser, DbSession, PageParams
from app.models import JournalEntry, Night, User
from app.schemas import JournalCreate, JournalOut, JournalUpdate, Page

router = APIRouter(prefix="/journal", tags=["journal"])

ENTRY_NOT_FOUND = "Journal entry not found."
NIGHT_NOT_FOUND = "Night not found."
# PATCH may clear these with an explicit null; the other fields always need a value.
CLEARABLE_FIELDS = {"night_id", "vividness"}


def _own_entry(db: Session, user: User, entry_id: uuid.UUID) -> JournalEntry:
    """The user's entry, or 404 (also when it belongs to someone else)."""
    entry = db.get(JournalEntry, entry_id)
    if entry is None or entry.user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail=ENTRY_NOT_FOUND)
    return entry


def _check_own_night(db: Session, user: User, night_id: uuid.UUID) -> None:
    """404 unless `night_id` is one of the user's own nights."""
    owner_id = db.scalar(select(Night.user_id).where(Night.id == night_id))
    if owner_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail=NIGHT_NOT_FOUND)


@router.get("", response_model=Page[JournalOut])
def list_entries(user: CurrentUser, db: DbSession, page: PageParams, night_id: uuid.UUID | None = None) -> dict:
    """Your journal entries, newest first. With `night_id`: only the entries about that night."""
    query = select(JournalEntry).where(JournalEntry.user_id == user.id)
    if night_id is not None:
        _check_own_night(db, user, night_id)
        query = query.where(JournalEntry.night_id == night_id)
    total = db.scalar(select(func.count()).select_from(query.subquery()))
    entries = db.scalars(
        query.order_by(JournalEntry.written_at.desc(), JournalEntry.created_at.desc(), JournalEntry.id)
        .limit(page.limit)
        .offset(page.offset)
    ).all()
    return {"items": entries, "total": total}


@router.post("", status_code=status.HTTP_201_CREATED, response_model=JournalOut)
def create_entry(body: JournalCreate, user: CurrentUser, db: DbSession) -> JournalEntry:
    """Write a new entry. `written_at` defaults to now."""
    if body.night_id is not None:
        _check_own_night(db, user, body.night_id)
    entry = JournalEntry(
        user_id=user.id,
        night_id=body.night_id,
        written_at=body.written_at or utcnow(),
        lucid=body.lucid,
        vividness=body.vividness,
        text=body.text,
    )
    db.add(entry)
    db.commit()
    return entry


@router.get("/{entry_id}", response_model=JournalOut)
def get_entry(entry_id: uuid.UUID, user: CurrentUser, db: DbSession) -> JournalEntry:
    return _own_entry(db, user, entry_id)


@router.patch("/{entry_id}", response_model=JournalOut)
def update_entry(entry_id: uuid.UUID, body: JournalUpdate, user: CurrentUser, db: DbSession) -> JournalEntry:
    """Change only the fields you send. Send `night_id: null` to unlink the entry from its night."""
    entry = _own_entry(db, user, entry_id)
    changes = body.model_dump(exclude_unset=True)
    cleared = sorted(name for name, value in changes.items() if value is None and name not in CLEARABLE_FIELDS)
    if cleared:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=f"These fields cannot be empty: {', '.join(cleared)}.",
        )
    if changes.get("night_id") is not None:
        _check_own_night(db, user, changes["night_id"])
    for name, value in changes.items():
        setattr(entry, name, value)
    db.commit()
    return entry


@router.delete("/{entry_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_entry(entry_id: uuid.UUID, user: CurrentUser, db: DbSession) -> Response:
    db.delete(_own_entry(db, user, entry_id))
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
