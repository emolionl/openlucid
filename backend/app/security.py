"""Passwords, tokens and the login rate limiter.

- Passwords are hashed with argon2.
- Access tokens are short-lived JWTs (HS256) that say who you are.
- Refresh tokens are long random strings; the database only keeps their sha256.
"""

import hashlib
import os
import secrets
import threading
import time
import uuid
from collections import defaultdict, deque
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError
from sqlalchemy import update
from sqlalchemy.orm import Session

from app.config import Settings
from app.models import RefreshToken

ACCESS_TOKEN_TYPE = "access"
JWT_ALGORITHM = "HS256"

password_hasher = PasswordHasher()

# Checked when the email is unknown, so a wrong email takes as long as a wrong password.
_DUMMY_HASH = password_hasher.hash("not-a-real-password")


class InvalidTokenError(Exception):
    """The access token is missing, broken, expired or of the wrong type."""


# --- passwords ----------------------------------------------------------------------------


def hash_password(password: str) -> str:
    return password_hasher.hash(password)


def verify_password(password_hash: str | None, password: str) -> bool:
    """True if `password` matches. Pass None as hash for an unknown user (still spends the time)."""
    try:
        return password_hasher.verify(password_hash or _DUMMY_HASH, password) and password_hash is not None
    except (VerificationError, InvalidHashError):
        return False


# --- secret key ---------------------------------------------------------------------------


def resolve_secret_key(settings: Settings) -> str:
    """The JWT signing key: from settings, or (local mode) generated once and kept in DATA_DIR/secret_key."""
    if settings.secret_key:
        return settings.secret_key
    key_file = settings.secret_key_file
    if key_file.exists():
        key = key_file.read_text(encoding="utf-8").strip()
        if key:
            return key
    key_file.parent.mkdir(parents=True, exist_ok=True)
    key = secrets.token_urlsafe(48)
    key_file.write_text(key, encoding="utf-8")
    try:
        os.chmod(key_file, 0o600)
    except OSError:
        pass  # not every file system supports Unix permissions
    return key


# --- access tokens (JWT) ------------------------------------------------------------------


def create_access_token(user_id: uuid.UUID, secret_key: str, minutes: int) -> str:
    now = datetime.now(timezone.utc)
    claims = {
        "sub": str(user_id),
        "iat": now,
        "exp": now + timedelta(minutes=minutes),
        "type": ACCESS_TOKEN_TYPE,
    }
    return jwt.encode(claims, secret_key, algorithm=JWT_ALGORITHM)


def decode_access_token(token: str, secret_key: str) -> uuid.UUID:
    """Return the user id inside a valid access token, or raise InvalidTokenError."""
    try:
        claims = jwt.decode(
            token, secret_key, algorithms=[JWT_ALGORITHM], options={"require": ["sub", "exp", "iat", "type"]}
        )
        if claims["type"] != ACCESS_TOKEN_TYPE:
            raise InvalidTokenError("wrong token type")
        return uuid.UUID(claims["sub"])
    except (jwt.PyJWTError, ValueError, TypeError) as error:
        raise InvalidTokenError(str(error)) from error


# --- refresh tokens -----------------------------------------------------------------------


def new_refresh_token() -> str:
    """A fresh opaque refresh token. Give it to the client; store only hash_token(token)."""
    return secrets.token_urlsafe(32)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def revoke_all_refresh_tokens(db: Session, user_id: uuid.UUID) -> None:
    """End every sign-in of this user (password change, deactivation, suspected theft). Caller commits."""
    db.execute(
        update(RefreshToken)
        .where(RefreshToken.user_id == user_id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=datetime.now(timezone.utc))
        .execution_options(synchronize_session=False)
    )


# --- rate limiting ------------------------------------------------------------------------


class TooManyFailures(Exception):
    """Too many failed password checks lately; try again after `retry_after` seconds."""

    def __init__(self, retry_after: int):
        super().__init__(f"blocked for {retry_after} s")
        self.retry_after = retry_after


class RateLimiter:
    """Counts failures per key (an email, an IP address) inside a sliding time window. In memory only.

    Not thread-safe on its own: LoginGuard holds one lock around every use.
    """

    def __init__(self, max_failures: int, window_seconds: float):
        self.max_failures = max_failures
        self.window_seconds = window_seconds
        self.clock = time.monotonic  # replaceable in tests
        self._failures: dict[str, deque[float]] = defaultdict(deque)

    def _prune(self, key: str, now: float) -> deque[float]:
        failures = self._failures[key]
        while failures and failures[0] <= now - self.window_seconds:
            failures.popleft()
        if not failures:
            del self._failures[key]
            return deque()
        return failures

    def retry_after(self, key: str) -> int:
        """0 if `key` may try again now, otherwise the seconds until its oldest counted failure expires."""
        now = self.clock()
        failures = self._prune(key, now)
        if len(failures) < self.max_failures:
            return 0
        return max(1, int(failures[0] + self.window_seconds - now) + 1)

    def record_failure(self, key: str) -> float:
        """Count one failure now; returns its time stamp (see remove)."""
        stamp = self.clock()
        self._failures[key].append(stamp)
        return stamp

    def remove(self, key: str, stamp: float) -> None:
        """Take back one failure that record_failure counted (if it is still there)."""
        failures = self._failures.get(key)
        if failures is not None and stamp in failures:
            failures.remove(stamp)
            if not failures:
                del self._failures[key]

    def reset(self, key: str) -> None:
        self._failures.pop(key, None)


LOGIN_WINDOW_SECONDS = 15 * 60


@dataclass(frozen=True)
class LoginAttempt:
    """A password check that LoginGuard.begin allowed. It counts as a failure until `succeeded` is called."""

    email: str
    ip: str
    ip_stamp: float


class LoginGuard:
    """The login limits from SPEC.md: 10 failures per email and 30 per client IP, per 15 minutes.

    Every password check is counted as a failure *before* it starts, in one locked step together with the
    limit check. So even many parallel requests can never run more checks than the limits allow.

        attempt = guard.begin(email, ip)    # raises TooManyFailures
        if password is right: guard.succeeded(attempt)
        (a wrong password needs nothing more: it was already counted)
    """

    def __init__(self) -> None:
        self.by_email = RateLimiter(max_failures=10, window_seconds=LOGIN_WINDOW_SECONDS)
        self.by_ip = RateLimiter(max_failures=30, window_seconds=LOGIN_WINDOW_SECONDS)
        self._lock = threading.Lock()

    def begin(self, email: str, ip: str) -> LoginAttempt:
        """Allow one password check and count it as a failure for now. Raises TooManyFailures."""
        with self._lock:
            wait = max(self.by_email.retry_after(email), self.by_ip.retry_after(ip))
            if wait:
                raise TooManyFailures(wait)
            self.by_email.record_failure(email)
            return LoginAttempt(email=email, ip=ip, ip_stamp=self.by_ip.record_failure(ip))

    def succeeded(self, attempt: LoginAttempt) -> None:
        """The password was right: clear the email's failures and take back this attempt's IP count."""
        with self._lock:
            self.by_email.reset(attempt.email)
            self.by_ip.remove(attempt.ip, attempt.ip_stamp)
