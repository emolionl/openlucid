"""Request and response models for every endpoint in SPEC.md.

Conventions:
- `...In` / `...Create` / `...Update` are request bodies, `...Out` are responses.
- Every timestamp a client sends must carry a time zone; it is converted to UTC here.
- `Page[X]` is the shape of every list endpoint: {"items": [...], "total": n}.
- Request bodies derive from `RequestModel`, which refuses NUL characters anywhere in them
  (PostgreSQL cannot store them, so they would otherwise fail there and pass on SQLite).
"""

import json
import re
import uuid
from datetime import datetime, timezone
from typing import Annotated, Any, Generic, Literal, TypeVar
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import AfterValidator, AwareDatetime, BaseModel, ConfigDict, Field, field_validator, model_validator

T = TypeVar("T")

Role = Literal["user", "admin"]
Stage = Literal["wake", "n1", "n2", "n3", "rem", "unknown"]
Quality = Literal["good", "okay", "poor", "gap"]
Lucid = Literal["yes", "no", "maybe"]
RecordingKind = Literal["edf", "raw_csv", "other"]

MAX_EVENT_DETAILS_BYTES = 10 * 1024
EMAIL_PATTERN = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
# Timestamps outside this range are surely a mistake (and years near 1 or 9999 break time zone maths).
EARLIEST_TIMESTAMP = datetime(1900, 1, 1, tzinfo=timezone.utc)
LATEST_TIMESTAMP = datetime(2200, 1, 1, tzinfo=timezone.utc)
NUL_MESSAGE = "Text may not contain NUL characters."


def _to_utc(value: datetime) -> datetime:
    try:
        value = value.astimezone(timezone.utc)
    except OverflowError:
        raise ValueError("Timestamp is out of range.") from None
    if not EARLIEST_TIMESTAMP <= value < LATEST_TIMESTAMP:
        raise ValueError("Timestamp must be between the years 1900 and 2199.")
    return value


def _contains_nul(value: Any) -> bool:
    """True if `value`, or any string, key or item inside it (at any depth), contains a NUL character."""
    pending = [value]
    while pending:
        item = pending.pop()
        if isinstance(item, str):
            if "\x00" in item:
                return True
        elif isinstance(item, dict):
            pending.extend(item.keys())
            pending.extend(item.values())
        elif isinstance(item, (list, tuple)):
            pending.extend(item)
    return False


def _no_nul(value: str) -> str:
    if "\x00" in value:
        raise ValueError(NUL_MESSAGE)
    return value


def _normalize_email(value: str) -> str:
    value = value.strip().lower()
    if not EMAIL_PATTERN.match(value):
        raise ValueError("This does not look like an email address.")
    return value


def _check_timezone(value: str) -> str:
    try:
        ZoneInfo(value)
    except (ZoneInfoNotFoundError, ValueError):
        raise ValueError("Unknown time zone; use an IANA name such as 'Europe/Amsterdam'.") from None
    return value


UTCDatetime = Annotated[AwareDatetime, AfterValidator(_to_utc)]
Email = Annotated[str, Field(max_length=254), AfterValidator(_normalize_email)]
NewPassword = Annotated[str, Field(min_length=10, max_length=1000)]
Password = Annotated[str, Field(min_length=1, max_length=1000)]
ClientId = Annotated[str, Field(min_length=1, max_length=64)]
TimezoneName = Annotated[str, Field(max_length=64), AfterValidator(_check_timezone)]
Score = Annotated[float, Field(ge=0, le=1)]
ChannelName = Annotated[str, Field(min_length=1, max_length=40)]
PlainText = Annotated[str, AfterValidator(_no_nul)]  # for query parameters; bodies are checked by RequestModel


class OrmModel(BaseModel):
    """Base for responses built straight from database rows."""

    model_config = ConfigDict(from_attributes=True)


class RequestModel(BaseModel):
    """Base for request bodies: no NUL characters anywhere, also not deep inside lists or `details`."""

    @model_validator(mode="before")
    @classmethod
    def refuse_nul_characters(cls, data: Any) -> Any:
        if _contains_nul(data):
            raise ValueError(NUL_MESSAGE)
        return data


class Page(BaseModel, Generic[T]):
    items: list[T]
    total: int


# --- public -------------------------------------------------------------------------------


class VersionOut(BaseModel):
    name: str
    version: str
    mode: Literal["local", "server"]
    registration_open: bool
    consent_version: str


# --- users and auth -----------------------------------------------------------------------


class UserOut(OrmModel):
    """A user as the user themselves sees it. Never contains the password hash."""

    id: uuid.UUID
    email: str
    display_name: str | None
    role: Role
    is_active: bool
    consent_version: str
    consent_at: datetime
    created_at: datetime
    updated_at: datetime


class RegisterIn(RequestModel):
    email: Email
    password: NewPassword
    display_name: Annotated[str, Field(max_length=100)] | None = None
    accept_consent: Literal[True] = Field(description="Must be true: you agree to the privacy text.")
    consent_version: str = Field(max_length=40, description="The consent version you read (see GET /version).")


class LoginIn(RequestModel):
    email: Annotated[str, Field(max_length=254)]
    password: Password


class TokenOut(BaseModel):
    """Answer of the OAuth2 form endpoint (/auth/token)."""

    access_token: str
    token_type: Literal["bearer"] = "bearer"


class TokenPairOut(TokenOut):
    refresh_token: str


class AuthOut(TokenPairOut):
    user: UserOut


class RefreshIn(RequestModel):
    refresh_token: Annotated[str, Field(min_length=1, max_length=200)]


class LogoutIn(RefreshIn):
    pass


# --- account (/me) ------------------------------------------------------------------------


class MeUpdate(RequestModel):
    display_name: Annotated[str, Field(max_length=100)] | None = None


class PasswordChangeIn(RequestModel):
    current_password: Password
    new_password: NewPassword


class AccountDeleteIn(RequestModel):
    password: Password


# --- nights -------------------------------------------------------------------------------


class NightCreate(RequestModel):
    client_id: ClientId | None = None
    started_at: UTCDatetime
    device_name: Annotated[str, Field(min_length=1, max_length=100)]
    device_firmware: Annotated[str, Field(max_length=100)] | None = None
    channels: Annotated[list[ChannelName], Field(min_length=1, max_length=64)]
    sample_rate: Annotated[float, Field(gt=0, le=100_000)]
    timezone: TimezoneName | None = None
    notes: Annotated[str, Field(max_length=5000)] | None = None


class NightUpdate(RequestModel):
    ended_at: UTCDatetime | None = None
    notes: Annotated[str, Field(max_length=5000)] | None = None
    device_firmware: Annotated[str, Field(max_length=100)] | None = None


class NightOut(OrmModel):
    id: uuid.UUID
    client_id: str | None
    started_at: datetime
    ended_at: datetime | None
    device_name: str
    device_firmware: str | None
    channels: list[str]
    sample_rate: float
    timezone: str | None
    notes: str | None
    created_at: datetime
    updated_at: datetime


class NightSummaryOut(BaseModel):
    night: NightOut
    epoch_count: int
    stage_minutes: dict[str, float]
    event_counts: dict[str, int]
    contact_average: dict[str, float]
    recordings: int


# --- epochs -------------------------------------------------------------------------------


class EpochIn(RequestModel):
    index: Annotated[int, Field(ge=0)]
    started_at: UTCDatetime
    stage: Stage | None = None
    stage_confidence: Score | None = None
    contact: dict[ChannelName, Score] | None = None
    quality: Quality | None = None


class EpochsUpsertIn(RequestModel):
    epochs: Annotated[list[EpochIn], Field(min_length=1, max_length=1000)]


class EpochsUpsertOut(BaseModel):
    upserted: int


class EpochOut(OrmModel):
    id: uuid.UUID
    index: int
    started_at: datetime
    stage: Stage | None
    stage_confidence: float | None
    contact: dict[str, float] | None
    quality: Quality | None
    created_at: datetime
    updated_at: datetime


# --- events -------------------------------------------------------------------------------


class EventIn(RequestModel):
    client_id: ClientId | None = None
    at: UTCDatetime
    type: Annotated[str, Field(min_length=1, max_length=40)]
    details: dict[str, Any] | None = None

    @field_validator("details")
    @classmethod
    def details_not_too_big(cls, value: dict[str, Any] | None) -> dict[str, Any] | None:
        if value is None:
            return None
        try:
            serialized = json.dumps(value, allow_nan=False)
        except ValueError:
            raise ValueError("details must be valid JSON (no NaN or Infinity).") from None
        if len(serialized.encode("utf-8")) > MAX_EVENT_DETAILS_BYTES:
            raise ValueError("details must be at most 10 kB as JSON.")
        return value


class EventsCreateIn(RequestModel):
    events: Annotated[list[EventIn], Field(min_length=1, max_length=500)]


class EventsCreateOut(BaseModel):
    created: int
    existing: int


class EventOut(OrmModel):
    id: uuid.UUID
    client_id: str | None
    at: datetime
    type: str
    details: dict[str, Any] | None
    created_at: datetime


# --- recordings ---------------------------------------------------------------------------


class RecordingOut(OrmModel):
    """Recording metadata. The storage path on disk is deliberately not part of it."""

    id: uuid.UUID
    night_id: uuid.UUID
    kind: RecordingKind
    original_filename: str
    size_bytes: int
    sha256: str
    uploaded_at: datetime


# --- journal ------------------------------------------------------------------------------


class JournalCreate(RequestModel):
    night_id: uuid.UUID | None = None
    written_at: UTCDatetime | None = Field(default=None, description="Defaults to now.")
    lucid: Lucid
    vividness: Annotated[int, Field(ge=1, le=5)] | None = None
    text: Annotated[str, Field(max_length=20000)]


class JournalUpdate(RequestModel):
    night_id: uuid.UUID | None = None
    written_at: UTCDatetime | None = None
    lucid: Lucid | None = None
    vividness: Annotated[int, Field(ge=1, le=5)] | None = None
    text: Annotated[str, Field(max_length=20000)] | None = None


class JournalOut(OrmModel):
    id: uuid.UUID
    night_id: uuid.UUID | None
    written_at: datetime
    lucid: Lucid
    vividness: int | None
    text: str
    created_at: datetime
    updated_at: datetime


# --- export -------------------------------------------------------------------------------


class NightExport(NightOut):
    epochs: list[EpochOut]
    events: list[EventOut]


class ExportOut(BaseModel):
    """Everything we store about one user (GET /me/export). Recording files themselves are not included."""

    exported_at: datetime
    user: UserOut
    nights: list[NightExport]
    journal_entries: list[JournalOut]
    recordings: list[RecordingOut]


# --- admin --------------------------------------------------------------------------------


class AdminUserOut(OrmModel):
    """What an admin may see about a user: account facts only, never their nights' content."""

    id: uuid.UUID
    email: str
    display_name: str | None
    role: Role
    is_active: bool
    created_at: datetime
    night_count: int


class AdminUserUpdate(RequestModel):
    role: Role | None = None
    is_active: bool | None = None
