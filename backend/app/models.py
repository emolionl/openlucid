"""All database tables (see SPEC.md, "Data model").

Raw EEG never lives here: recordings are files on disk, these rows only describe them.
Deleting a user or a night cascades in the database (ON DELETE CASCADE) and in the ORM.
"""

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import JSON, BigInteger, Float, ForeignKey, Integer, String, Text, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base, UTCDateTime, utcnow

ROLES = ("user", "admin")
STAGES = ("wake", "n1", "n2", "n3", "rem", "unknown")
QUALITIES = ("good", "okay", "poor", "gap")
LUCID_ANSWERS = ("yes", "no", "maybe")
RECORDING_KINDS = ("edf", "raw_csv", "other")


def new_id() -> uuid.UUID:
    return uuid.uuid4()


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=new_id)
    email: Mapped[str] = mapped_column(String(254), unique=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    display_name: Mapped[str | None] = mapped_column(String(100))
    role: Mapped[str] = mapped_column(String(10), default="user")
    is_active: Mapped[bool] = mapped_column(default=True)
    consent_version: Mapped[str] = mapped_column(String(40))
    consent_at: Mapped[datetime] = mapped_column(UTCDateTime)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow, onupdate=utcnow)

    refresh_tokens: Mapped[list["RefreshToken"]] = relationship(
        back_populates="user", cascade="all, delete-orphan", passive_deletes=True
    )
    nights: Mapped[list["Night"]] = relationship(
        back_populates="user", cascade="all, delete-orphan", passive_deletes=True
    )
    journal_entries: Mapped[list["JournalEntry"]] = relationship(
        back_populates="user", cascade="all, delete-orphan", passive_deletes=True
    )


class RefreshToken(Base):
    """One long-lived login. Only the sha256 of the token is stored, never the token itself."""

    __tablename__ = "refresh_tokens"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=new_id)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    expires_at: Mapped[datetime] = mapped_column(UTCDateTime)
    revoked_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)
    replaced_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("refresh_tokens.id", ondelete="SET NULL")
    )

    user: Mapped[User] = relationship(back_populates="refresh_tokens")


class Night(Base):
    __tablename__ = "nights"
    __table_args__ = (UniqueConstraint("user_id", "client_id"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=new_id)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    client_id: Mapped[str | None] = mapped_column(String(64))
    started_at: Mapped[datetime] = mapped_column(UTCDateTime)
    ended_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    device_name: Mapped[str] = mapped_column(String(100))
    device_firmware: Mapped[str | None] = mapped_column(String(100))
    channels: Mapped[list[str]] = mapped_column(JSON)
    sample_rate: Mapped[float] = mapped_column(Float)
    timezone: Mapped[str | None] = mapped_column(String(64))
    notes: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow, onupdate=utcnow)

    user: Mapped[User] = relationship(back_populates="nights")
    epochs: Mapped[list["Epoch"]] = relationship(
        back_populates="night", cascade="all, delete-orphan", passive_deletes=True, order_by="Epoch.index"
    )
    events: Mapped[list["Event"]] = relationship(
        back_populates="night", cascade="all, delete-orphan", passive_deletes=True, order_by="Event.at"
    )
    recordings: Mapped[list["Recording"]] = relationship(
        back_populates="night", cascade="all, delete-orphan", passive_deletes=True
    )


class Epoch(Base):
    """One 30-second slice of a night: stage, electrode contact and signal quality."""

    __tablename__ = "epochs"
    __table_args__ = (UniqueConstraint("night_id", "index"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=new_id)
    night_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("nights.id", ondelete="CASCADE"), index=True)
    index: Mapped[int] = mapped_column(Integer)
    started_at: Mapped[datetime] = mapped_column(UTCDateTime)
    stage: Mapped[str | None] = mapped_column(String(10))
    stage_confidence: Mapped[float | None] = mapped_column(Float)
    contact: Mapped[dict[str, float] | None] = mapped_column(JSON)
    quality: Mapped[str | None] = mapped_column(String(10))
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow, onupdate=utcnow)

    night: Mapped[Night] = relationship(back_populates="epochs")


class Event(Base):
    """Something that happened during a night: a cue, an eye signal, waking up, a note..."""

    __tablename__ = "events"
    __table_args__ = (UniqueConstraint("night_id", "client_id"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=new_id)
    night_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("nights.id", ondelete="CASCADE"), index=True)
    client_id: Mapped[str | None] = mapped_column(String(64))
    at: Mapped[datetime] = mapped_column(UTCDateTime)
    type: Mapped[str] = mapped_column(String(40))
    details: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)

    night: Mapped[Night] = relationship(back_populates="events")


class JournalEntry(Base):
    __tablename__ = "journal_entries"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=new_id)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    night_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("nights.id", ondelete="SET NULL"), index=True
    )
    written_at: Mapped[datetime] = mapped_column(UTCDateTime)
    lucid: Mapped[str] = mapped_column(String(10))
    vividness: Mapped[int | None] = mapped_column(Integer)
    text: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow, onupdate=utcnow)

    user: Mapped[User] = relationship(back_populates="journal_entries")


class Recording(Base):
    """Metadata of a raw recording file. `storage_path` is relative to DATA_DIR and never sent to clients."""

    __tablename__ = "recordings"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=new_id)
    night_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("nights.id", ondelete="CASCADE"), index=True)
    kind: Mapped[str] = mapped_column(String(10))
    original_filename: Mapped[str] = mapped_column(String(200))
    size_bytes: Mapped[int] = mapped_column(BigInteger)
    sha256: Mapped[str] = mapped_column(String(64))
    storage_path: Mapped[str] = mapped_column(String(500))
    uploaded_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)

    night: Mapped[Night] = relationship(back_populates="recordings")
