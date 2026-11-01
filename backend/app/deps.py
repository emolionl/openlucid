"""FastAPI dependencies shared by every router.

Typical use in a router:

    @router.get("/nights")
    def list_nights(user: CurrentUser, db: DbSession, page: PageParams): ...
"""

from dataclasses import dataclass
from typing import Annotated

from fastapi import Depends, HTTPException, Query, Request, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from app.config import Settings
from app.db import get_db
from app.models import User
from app.security import InvalidTokenError, LoginGuard, decode_access_token, resolve_secret_key

# auto_error=False: we raise our own 401 so the message and header are always the same.
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/token", auto_error=False)


def get_settings(request: Request) -> Settings:
    return request.app.state.settings


def get_secret_key(request: Request) -> str:
    """The JWT signing key of this app, resolved on first use (local mode may create DATA_DIR/secret_key)."""
    state = request.app.state
    if state.secret_key is None:
        state.secret_key = resolve_secret_key(state.settings)
    return state.secret_key


def get_login_guard(request: Request) -> LoginGuard:
    return request.app.state.login_guard


DbSession = Annotated[Session, Depends(get_db)]
AppSettings = Annotated[Settings, Depends(get_settings)]
SecretKey = Annotated[str, Depends(get_secret_key)]


def unauthorized(detail: str = "Not signed in, or the session has expired.") -> HTTPException:
    return HTTPException(status.HTTP_401_UNAUTHORIZED, detail=detail, headers={"WWW-Authenticate": "Bearer"})


def current_user(
    db: DbSession,
    secret_key: SecretKey,
    token: Annotated[str | None, Depends(oauth2_scheme)],
) -> User:
    """The signed-in user from `Authorization: Bearer <access token>`. 401 if missing or invalid."""
    if not token:
        raise unauthorized()
    try:
        user_id = decode_access_token(token, secret_key)
    except InvalidTokenError:
        raise unauthorized() from None
    user = db.get(User, user_id)
    if user is None:
        raise unauthorized()
    if not user.is_active:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="This account is deactivated.")
    return user


CurrentUser = Annotated[User, Depends(current_user)]


def admin_user(user: CurrentUser) -> User:
    """Like current_user, but only admins pass; everyone else gets 403."""
    if user.role != "admin":
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Only admins can do this.")
    return user


AdminUser = Annotated[User, Depends(admin_user)]


@dataclass(frozen=True)
class Pagination:
    limit: int
    offset: int


def pagination_with(max_limit: int):
    """Make a `limit`/`offset` query-parameter dependency with its own maximum limit."""

    def pagination(
        limit: Annotated[int, Query(ge=1, le=max_limit)] = 50,
        offset: Annotated[int, Query(ge=0)] = 0,
    ) -> Pagination:
        return Pagination(limit=limit, offset=offset)

    return pagination


PageParams = Annotated[Pagination, Depends(pagination_with(200))]
EpochPageParams = Annotated[Pagination, Depends(pagination_with(2000))]
