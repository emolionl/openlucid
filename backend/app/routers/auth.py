"""Sign up, sign in, keep signed in (refresh) and sign out."""

from datetime import timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy import func, select, text, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.config import Settings
from app.db import utcnow
from app.deps import AppSettings, DbSession, SecretKey, get_login_guard
from app.models import RefreshToken, User
from app.schemas import AuthOut, LoginIn, LogoutIn, RefreshIn, RegisterIn, TokenOut, TokenPairOut, UserOut
from app.security import (
    LoginGuard,
    TooManyFailures,
    create_access_token,
    hash_password,
    hash_token,
    new_refresh_token,
    revoke_all_refresh_tokens,
    verify_password,
)

router = APIRouter(prefix="/auth", tags=["auth"])

WRONG_CREDENTIALS = "Wrong email or password."
BAD_REFRESH_TOKEN = "This sign-in has expired or is no longer valid. Please sign in again."
Guard = Annotated[LoginGuard, Depends(get_login_guard)]


def _issue_refresh_token(db: Session, user: User, settings: Settings) -> tuple[RefreshToken, str]:
    """Store a new refresh token for `user` (only its hash) and return the row and the plain token."""
    token = new_refresh_token()
    row = RefreshToken(
        user_id=user.id,
        token_hash=hash_token(token),
        expires_at=utcnow() + timedelta(days=settings.refresh_token_days),
    )
    db.add(row)
    db.flush()
    return row, token


def _auth_response(db: Session, user: User, settings: Settings, secret_key: str) -> AuthOut:
    _, refresh_token = _issue_refresh_token(db, user, settings)
    db.commit()
    return AuthOut(
        user=UserOut.model_validate(user),
        access_token=create_access_token(user.id, secret_key, settings.access_token_minutes),
        refresh_token=refresh_token,
    )


def _authenticate(db: Session, guard: LoginGuard, request: Request, email: str, password: str) -> User:
    """Check email and password with the rate limits from SPEC.md. Raises 429, 401 or 403."""
    email = email.strip().lower()
    client_ip = request.client.host if request.client else "unknown"
    try:
        attempt = guard.begin(email, client_ip)
    except TooManyFailures as blocked:
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many failed sign-in attempts. Please wait a while and try again.",
            headers={"Retry-After": str(blocked.retry_after)},
        ) from None
    # The OAuth2 form is not checked by a schema; an email with a NUL character cannot exist (nor be queried).
    user = None if "\x00" in email else db.scalar(select(User).where(User.email == email))
    if not verify_password(user.password_hash if user else None, password):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail=WRONG_CREDENTIALS)
    guard.succeeded(attempt)
    if not user.is_active:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="This account is deactivated.")
    return user


# Any fixed number works; it only has to be the same for every registration.
FIRST_USER_LOCK_ID = 7_406_226_901


def _serialize_first_user_check(db: Session) -> None:
    """Make "am I the first user?" safe when two people register at the same moment.

    PostgreSQL: a transaction-wide advisory lock, so registrations take turns until they commit.
    SQLite needs nothing extra: the INSERT that follows takes SQLite's single write lock, which the
    other registrations wait for, so the count after it always sees every committed account.
    """
    if db.get_bind().dialect.name == "postgresql":
        db.execute(text("SELECT pg_advisory_xact_lock(:lock_id)"), {"lock_id": FIRST_USER_LOCK_ID})


@router.post("/register", status_code=status.HTTP_201_CREATED, response_model=AuthOut)
def register(body: RegisterIn, db: DbSession, settings: AppSettings, secret_key: SecretKey) -> AuthOut:
    """Create an account. The very first account becomes the admin."""
    if not settings.allow_registration:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Registration is closed on this server.")
    if body.consent_version != settings.consent_version:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=f"Please read and accept the current privacy text (version {settings.consent_version}).",
        )
    taken = HTTPException(status.HTTP_409_CONFLICT, detail="An account with this email address already exists.")
    if db.scalar(select(User.id).where(User.email == body.email)) is not None:
        raise taken
    user = User(
        email=body.email,
        password_hash=hash_password(body.password),
        display_name=body.display_name,
        role="user",
        consent_version=body.consent_version,
        consent_at=utcnow(),
    )
    _serialize_first_user_check(db)
    db.add(user)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise taken from None
    if db.scalar(select(func.count()).select_from(User).where(User.id != user.id)) == 0:
        user.role = "admin"
    return _auth_response(db, user, settings, secret_key)


@router.post("/login", response_model=AuthOut)
def login(
    body: LoginIn, request: Request, db: DbSession, settings: AppSettings, secret_key: SecretKey, guard: Guard
) -> AuthOut:
    user = _authenticate(db, guard, request, body.email, body.password)
    return _auth_response(db, user, settings, secret_key)


@router.post("/token", response_model=TokenOut)
def token_form(
    form: Annotated[OAuth2PasswordRequestForm, Depends()],
    request: Request,
    db: DbSession,
    settings: AppSettings,
    secret_key: SecretKey,
    guard: Guard,
) -> TokenOut:
    """OAuth2 password form for the "Authorize" button in /docs. `username` is your email."""
    user = _authenticate(db, guard, request, form.username, form.password)
    return TokenOut(access_token=create_access_token(user.id, secret_key, settings.access_token_minutes))


@router.post("/refresh", response_model=TokenPairOut)
def refresh(body: RefreshIn, db: DbSession, settings: AppSettings, secret_key: SecretKey) -> TokenPairOut:
    """Swap a refresh token for a new access token and a new refresh token (the old one stops working).

    Using a revoked refresh token again (replaced, logged out or ended by a password change) looks like
    theft, so every session of that user is ended (SPEC.md). A client must forget a token once it is used.
    """
    old = db.scalar(select(RefreshToken).where(RefreshToken.token_hash == hash_token(body.refresh_token)))
    if old is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail=BAD_REFRESH_TOKEN)
    if old.revoked_at is not None:
        revoke_all_refresh_tokens(db, old.user_id)
        db.commit()
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail=BAD_REFRESH_TOKEN)
    now = utcnow()
    if old.expires_at <= now:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail=BAD_REFRESH_TOKEN)
    user = old.user
    if not user.is_active:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="This account is deactivated.")

    new_row, new_token = _issue_refresh_token(db, user, settings)
    # Claim the old token in one conditional UPDATE: if two requests race with it, only one wins.
    claimed = db.execute(
        update(RefreshToken)
        .where(RefreshToken.id == old.id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=now, replaced_by_id=new_row.id)
        .execution_options(synchronize_session=False)
    ).rowcount
    if claimed == 0:
        db.rollback()
        revoke_all_refresh_tokens(db, old.user_id)
        db.commit()
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail=BAD_REFRESH_TOKEN)
    db.commit()
    return TokenPairOut(
        access_token=create_access_token(user.id, secret_key, settings.access_token_minutes),
        refresh_token=new_token,
    )


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(body: LogoutIn, db: DbSession) -> Response:
    """End this sign-in. Unknown or already-ended tokens are fine too (nothing to do)."""
    db.execute(
        update(RefreshToken)
        .where(RefreshToken.token_hash == hash_token(body.refresh_token), RefreshToken.revoked_at.is_(None))
        .values(revoked_at=utcnow())
        .execution_options(synchronize_session=False)
    )
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
