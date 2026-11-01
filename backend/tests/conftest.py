"""Shared test fixtures. Every test gets its own fresh database and DATA_DIR.

Database: an SQLite file in tmp_path, or, when OPENLUCID_TEST_DATABASE_URL is set (scripts/pg_test.py does
that), that PostgreSQL database with all tables dropped and created again before each test. Its name must
end in "_test". OPENLUCID_DATABASE_URL (your real database) is ignored, so pytest can never wipe it.
Settings never come from your shell or backend/.env here: every test starts from the defaults.

Fixtures
--------
data_dir         Path of this test's DATA_DIR (recordings and the generated secret key go here).
make_settings    make_settings(**overrides) -> Settings for this test's database and DATA_DIR.
make_client      make_client(**overrides) -> a started TestClient on a new app with those settings,
                 e.g. make_client(allow_registration=False) or make_client(max_upload_mb=1).
                 All clients of one test share the database, DATA_DIR and secret key.
client           make_client() with default settings.
app              client.app (the FastAPI app behind `client`).
db               a SQLAlchemy session on the test database, to look at or prepare rows directly.
register_user    register_user(client, email=None, password=DEFAULT_PASSWORD, display_name=None)
                 -> (user_json, headers). The email is random when not given.
admin            the first registered user, so role "admin" (a RegisteredUser).
alice, bob       two ordinary users (RegisteredUser), registered after `admin`.

A RegisteredUser has: id (str), email, password, user (the JSON), headers ({"Authorization": ...})
and refresh_token. Use it like: client.get("/me", headers=alice.headers).
"""

import os
import uuid
from collections.abc import Callable, Iterator, Mapping
from dataclasses import dataclass
from pathlib import Path

import pytest
from argon2 import PasswordHasher
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import make_url, text
from sqlalchemy.orm import Session

from app import models  # noqa: F401  (registers every table on Base.metadata)
from app import security
from app.config import Settings
from app.db import Base, make_engine
from app.main import create_app

TEST_DATABASE_URL_ENV = "OPENLUCID_TEST_DATABASE_URL"
DEFAULT_PASSWORD = "correct horse battery staple"


@dataclass(frozen=True)
class RegisteredUser:
    id: str
    email: str
    password: str
    user: dict
    headers: dict[str, str]
    refresh_token: str


@pytest.fixture(autouse=True)
def fast_password_hashing(monkeypatch: pytest.MonkeyPatch) -> None:
    """Real argon2, but with tiny cost settings so hundreds of sign-ups stay quick in tests."""
    monkeypatch.setattr(security, "password_hasher", PasswordHasher(time_cost=1, memory_cost=1024, parallelism=1))


@pytest.fixture
def data_dir(tmp_path: Path) -> Path:
    return tmp_path / "data"


def choose_database_url(environ: Mapping[str, str], tmp_path: Path) -> str:
    """The database the tests may wipe: OPENLUCID_TEST_DATABASE_URL (named *_test), else SQLite in tmp_path."""
    url = environ.get(TEST_DATABASE_URL_ENV)
    if not url:
        return f"sqlite:///{(tmp_path / 'test.db').as_posix()}"
    if not (make_url(url).database or "").endswith("_test"):
        raise pytest.UsageError(
            f"{TEST_DATABASE_URL_ENV} must name a database ending in '_test'; every test drops all its tables."
        )
    return url


@pytest.fixture
def database_url(tmp_path: Path) -> str:
    return choose_database_url(os.environ, tmp_path)


def reset_database(database_url: str) -> None:
    """Drop everything (including Alembic's bookkeeping) so the database is empty."""
    engine = make_engine(database_url)
    try:
        Base.metadata.drop_all(engine)
        with engine.begin() as connection:
            connection.execute(text("DROP TABLE IF EXISTS alembic_version"))
    finally:
        engine.dispose()


@pytest.fixture
def fresh_database(database_url: str) -> str:
    """An empty database with all tables created straight from the models (no migrations)."""
    reset_database(database_url)
    engine = make_engine(database_url)
    try:
        Base.metadata.create_all(engine)
    finally:
        engine.dispose()
    return database_url


@pytest.fixture
def make_settings(data_dir: Path, database_url: str) -> Callable[..., Settings]:
    def _make_settings(**overrides) -> Settings:
        values = {name: field.default for name, field in Settings.model_fields.items()}
        values.update(data_dir=data_dir, database_url=database_url, auto_migrate=False)
        values.update(overrides)
        return Settings(_env_file=None, **values)

    return _make_settings


@pytest.fixture
def make_client(fresh_database: str, make_settings: Callable[..., Settings]) -> Iterator[Callable[..., TestClient]]:
    clients: list[TestClient] = []

    def _make_client(**overrides) -> TestClient:
        test_client = TestClient(create_app(make_settings(**overrides)))
        test_client.__enter__()  # runs the app's startup
        clients.append(test_client)
        return test_client

    yield _make_client
    for test_client in clients:
        test_client.__exit__(None, None, None)


@pytest.fixture
def client(make_client: Callable[..., TestClient]) -> TestClient:
    return make_client()


@pytest.fixture
def app(client: TestClient) -> FastAPI:
    return client.app


@pytest.fixture
def db(app: FastAPI) -> Iterator[Session]:
    session = app.state.session_factory()
    try:
        yield session
    finally:
        session.close()


def _register(client: TestClient, email: str | None, password: str, display_name: str | None) -> dict:
    response = client.post(
        "/auth/register",
        json={
            "email": email or f"user-{uuid.uuid4().hex[:10]}@example.com",
            "password": password,
            "display_name": display_name,
            "accept_consent": True,
            "consent_version": client.app.state.settings.consent_version,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def bearer(access_token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {access_token}"}


@pytest.fixture
def register_user() -> Callable[..., tuple[dict, dict[str, str]]]:
    def _register_user(
        client: TestClient, email: str | None = None, password: str = DEFAULT_PASSWORD, display_name: str | None = None
    ) -> tuple[dict, dict[str, str]]:
        body = _register(client, email, password, display_name)
        return body["user"], bearer(body["access_token"])

    return _register_user


def _registered(client: TestClient, email: str, display_name: str) -> RegisteredUser:
    body = _register(client, email, DEFAULT_PASSWORD, display_name)
    return RegisteredUser(
        id=body["user"]["id"],
        email=email,
        password=DEFAULT_PASSWORD,
        user=body["user"],
        headers=bearer(body["access_token"]),
        refresh_token=body["refresh_token"],
    )


@pytest.fixture
def admin(client: TestClient) -> RegisteredUser:
    registered = _registered(client, "admin@example.com", "Admin")
    assert registered.user["role"] == "admin"
    return registered


@pytest.fixture
def alice(client: TestClient, admin: RegisteredUser) -> RegisteredUser:
    return _registered(client, "alice@example.com", "Alice")


@pytest.fixture
def bob(client: TestClient, alice: RegisteredUser) -> RegisteredUser:
    return _registered(client, "bob@example.com", "Bob")
