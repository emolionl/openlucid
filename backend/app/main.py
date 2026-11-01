"""The Diary Keeper: a small server that writes down everything about your night.

It runs locally (SQLite, files in ./data) or on a server (PostgreSQL). See SPEC.md.
"""

import math
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Any

from fastapi import FastAPI, Request, status
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app import storage
from app.config import APP_NAME, APP_VERSION, Settings
from app.db import make_engine, make_session_factory, run_migrations
from app.routers import account, admin, auth, journal, nights, recordings
from app.schemas import VersionOut
from app.security import LoginGuard

# Localhost on any port is always allowed: the Vue web app runs on its own port during development.
LOCALHOST_ORIGINS = r"http://(localhost|127\.0\.0\.1)(:\d+)?"


def _json_safe(value: Any) -> Any:
    """`value` with NaN and Infinity replaced by their names, which strict JSON cannot carry as numbers."""
    if isinstance(value, float) and not math.isfinite(value):
        return str(value)
    if isinstance(value, dict):
        return {key: _json_safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_safe(item) for item in value]
    return value


async def validation_error(_request: Request, error: RequestValidationError) -> JSONResponse:
    """FastAPI's usual 422 answer, but safe when the rejected body contained NaN or Infinity.

    (Python's JSON parser accepts those words; without this the 422 itself would fail and become a 500.)
    """
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
        content={"detail": _json_safe(jsonable_encoder(error.errors()))},
    )


def create_app(settings: Settings | None = None) -> FastAPI:
    """Build the app. Each app has its own settings, database engine and login rate limiter.

    On startup it creates DATA_DIR, runs the migrations when OPENLUCID_AUTO_MIGRATE is true, and removes
    recording files that an earlier delete could not remove yet (see storage.retry_pending_deletions).
    """
    settings = settings or Settings()
    engine = make_engine(settings.database_url)

    @asynccontextmanager
    async def lifespan(_app: FastAPI):
        settings.data_dir.mkdir(parents=True, exist_ok=True)
        if settings.auto_migrate:
            run_migrations(engine)
        storage.retry_pending_deletions(settings.data_dir)
        yield
        engine.dispose()

    app = FastAPI(
        title="OpenLucid — the Diary Keeper",
        description="API that logs sleep sessions, epochs, events and dream journals.",
        version=APP_VERSION,
        lifespan=lifespan,
    )
    app.state.settings = settings
    app.state.engine = engine
    app.state.session_factory = make_session_factory(engine)
    app.state.secret_key = None  # resolved on first use, see deps.get_secret_key
    app.state.login_guard = LoginGuard()
    app.add_exception_handler(RequestValidationError, validation_error)

    app.add_middleware(
        CORSMiddleware,
        allow_origin_regex=LOCALHOST_ORIGINS,
        allow_origins=settings.cors_origin_list,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.get("/health", tags=["public"])
    def health() -> dict:
        """Say hello. The Diary Keeper never sleeps, and it always tells you the time."""
        return {
            "status": "awake",
            "message": "The Diary Keeper is awake.",
            "time": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        }

    @app.get("/version", tags=["public"], response_model=VersionOut)
    def version() -> VersionOut:
        """What is running here, and whether new accounts can be made."""
        return VersionOut(
            name=APP_NAME,
            version=APP_VERSION,
            mode=settings.mode,
            registration_open=settings.allow_registration,
            consent_version=settings.consent_version,
        )

    for module in (auth, account, nights, recordings, journal, admin):
        app.include_router(module.router)

    return app


def __getattr__(name: str) -> FastAPI:
    """`app.main:app` for uvicorn, built from the environment on first use (and then kept).

    Building it lazily means `from app.main import create_app` reads no settings, so the tests and other
    tools never depend on your shell or backend/.env.
    """
    if name != "app":
        raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
    if "app" not in globals():
        globals()["app"] = create_app()
    return globals()["app"]
