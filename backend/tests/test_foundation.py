"""Tests for the foundation: settings, startup migrations, the secret key, /version and the database layer."""

import os
import subprocess
import sys
import uuid
from datetime import datetime, timedelta, timezone

import jwt
import pytest
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from alembic.operations import Operations
from fastapi.testclient import TestClient
from pydantic import ValidationError
from sqlalchemy import String, func, inspect, select
from sqlalchemy.orm import Session

from app.config import BACKEND_DIR, Settings
from app.db import Base, alembic_config, make_engine, migration_connection, run_migrations
from app.main import create_app
from app.models import Epoch, Event, JournalEntry, Night, Recording, RefreshToken, User
from conftest import choose_database_url, reset_database

ALL_TABLES = {"users", "refresh_tokens", "nights", "epochs", "events", "journal_entries", "recordings"}


# --- settings -----------------------------------------------------------------------------


@pytest.fixture
def clean_env(monkeypatch):
    """No OPENLUCID_* variables from the shell (pg_test.py sets OPENLUCID_TEST_DATABASE_URL, for example)."""
    for name in list(os.environ):
        if name.startswith("OPENLUCID_"):
            monkeypatch.delenv(name)


def test_defaults_are_local_with_sqlite_in_data_dir(clean_env, tmp_path):
    settings = Settings(_env_file=None, data_dir=tmp_path)
    assert settings.mode == "local"
    assert settings.database_url == f"sqlite:///{tmp_path.resolve().as_posix()}/openlucid.db"
    assert settings.auto_migrate is True


def test_server_mode_refuses_to_start_without_secret_key(clean_env, tmp_path):
    with pytest.raises(ValidationError, match="OPENLUCID_SECRET_KEY"):
        Settings(_env_file=None, mode="server", data_dir=tmp_path)


def test_short_secret_key_is_refused(clean_env, tmp_path):
    with pytest.raises(ValidationError, match="at least 32"):
        Settings(_env_file=None, mode="server", secret_key="too-short", data_dir=tmp_path)


def test_settings_are_read_from_environment(clean_env, monkeypatch, tmp_path):
    monkeypatch.setenv("OPENLUCID_MODE", "server")
    monkeypatch.setenv("OPENLUCID_SECRET_KEY", "s" * 40)
    monkeypatch.setenv("OPENLUCID_CORS_ORIGINS", "https://a.example, https://b.example")
    monkeypatch.setenv("OPENLUCID_ALLOW_REGISTRATION", "false")
    settings = Settings(_env_file=None, data_dir=tmp_path)
    assert settings.mode == "server"
    assert settings.cors_origin_list == ["https://a.example", "https://b.example"]
    assert settings.allow_registration is False


# --- secret key ---------------------------------------------------------------------------


def test_unfilled_copy_of_env_example_works_in_local_mode(clean_env, tmp_path):
    """`cp .env.example .env` leaves `OPENLUCID_SECRET_KEY=` empty: that means "not set", not "too short"."""
    settings = Settings(_env_file=BACKEND_DIR / ".env.example", data_dir=tmp_path)
    assert settings.mode == "local"
    assert settings.secret_key is None
    assert settings.database_url.startswith("sqlite:///")


def test_empty_secret_key_in_the_environment_counts_as_unset(clean_env, monkeypatch, tmp_path):
    monkeypatch.setenv("OPENLUCID_SECRET_KEY", "")
    assert Settings(_env_file=None, data_dir=tmp_path).secret_key is None


def test_importing_the_app_module_reads_no_settings(clean_env):
    """Tests (and tools) import app.main for create_app; only uvicorn's `app.main:app` builds the real app."""
    environment = {**os.environ, "OPENLUCID_MODE": "server"}  # would refuse to start: no secret key
    result = subprocess.run(
        [sys.executable, "-c", "import app.main"], cwd=BACKEND_DIR, env=environment, capture_output=True, text=True
    )
    assert result.returncode == 0, result.stderr


def test_tests_never_use_the_real_database_url(tmp_path):
    """A shell that exported OPENLUCID_DATABASE_URL for uvicorn must not make pytest wipe that database."""
    real = {"OPENLUCID_DATABASE_URL": "postgresql+psycopg://openlucid:secret@db.example/openlucid"}
    assert choose_database_url(real, tmp_path).startswith("sqlite:///")


def test_test_database_must_be_named_test(tmp_path):
    good = "postgresql+psycopg://postgres@127.0.0.1:5999/openlucid_test"
    assert choose_database_url({"OPENLUCID_TEST_DATABASE_URL": good}, tmp_path) == good
    with pytest.raises(pytest.UsageError, match="_test"):
        choose_database_url({"OPENLUCID_TEST_DATABASE_URL": good.removesuffix("_test")}, tmp_path)


def test_local_mode_generates_and_keeps_the_secret_key(make_client, data_dir, register_user):
    register_user(make_client())
    key = (data_dir / "secret_key").read_text(encoding="utf-8")
    assert len(key) >= 32
    # A restarted app (new app, same DATA_DIR) signs with the same key, so tokens survive restarts.
    _, headers = register_user(make_client())
    token = headers["Authorization"].removeprefix("Bearer ")
    assert jwt.decode(token, key, algorithms=["HS256"])["type"] == "access"


def test_configured_secret_key_is_used_and_not_written(make_client, data_dir, register_user):
    client = make_client(secret_key="k" * 40)
    register_user(client)
    assert client.app.state.secret_key == "k" * 40
    assert not (data_dir / "secret_key").exists()


# --- public endpoints ---------------------------------------------------------------------


def test_version(client):
    response = client.get("/version")
    assert response.status_code == 200
    body = response.json()
    assert body["name"] == "openlucid"
    assert body["mode"] == "local"
    assert body["registration_open"] is True
    assert body["consent_version"] == "2026-11"
    assert body["version"]


def test_version_shows_closed_registration(make_client):
    assert make_client(allow_registration=False).get("/version").json()["registration_open"] is False


def test_extra_cors_origin_is_allowed(make_client):
    client = make_client(cors_origins="https://lucid.example")
    allowed = client.get("/health", headers={"Origin": "https://lucid.example"})
    assert allowed.headers["access-control-allow-origin"] == "https://lucid.example"
    localhost = client.get("/health", headers={"Origin": "http://127.0.0.1:5173"})
    assert localhost.headers["access-control-allow-origin"] == "http://127.0.0.1:5173"
    other = client.get("/health", headers={"Origin": "https://evil.example"})
    assert "access-control-allow-origin" not in other.headers


def test_auth_and_public_routes_are_registered(app):
    paths = set(app.openapi()["paths"])
    assert {"/auth/register", "/auth/login", "/auth/token", "/auth/refresh", "/auth/logout", "/version"} <= paths


# --- migrations ---------------------------------------------------------------------------


@pytest.fixture
def empty_database(database_url):
    reset_database(database_url)
    engine = make_engine(database_url)
    yield engine
    engine.dispose()
    reset_database(database_url)


def test_migrations_create_exactly_the_models(empty_database):
    run_migrations(empty_database)
    assert ALL_TABLES <= set(inspect(empty_database).get_table_names())
    with empty_database.connect() as connection:
        context = MigrationContext.configure(connection, opts={"compare_type": True})
        assert compare_metadata(context, Base.metadata) == []
        assert context.get_current_revision() == "0001"


def test_migrations_downgrade_to_nothing(empty_database):
    run_migrations(empty_database)
    with empty_database.begin() as connection:
        command.downgrade(alembic_config(connection), "base")
    assert not ALL_TABLES & set(inspect(empty_database).get_table_names())


def test_startup_runs_migrations_when_auto_migrate(empty_database, make_settings, register_user):
    with TestClient(create_app(make_settings(auto_migrate=True))) as client:
        user, _ = register_user(client)
        assert user["role"] == "admin"
    assert ALL_TABLES <= set(inspect(empty_database).get_table_names())


def test_startup_without_auto_migrate_leaves_database_alone(empty_database, make_settings):
    with TestClient(create_app(make_settings(auto_migrate=False))):
        pass
    assert not ALL_TABLES & set(inspect(empty_database).get_table_names())


def test_startup_creates_data_dir(make_settings, data_dir, empty_database):
    assert not data_dir.exists()
    with TestClient(create_app(make_settings(auto_migrate=True))):
        assert data_dir.is_dir()


def add_user_with_a_night(engine) -> uuid.UUID:
    with Session(engine) as session:
        user = make_user()
        session.add(user)
        session.flush()
        session.add(Night(user_id=user.id, started_at=datetime.now(timezone.utc), device_name="d",
                          channels=["Fp1"], sample_rate=250))
        session.commit()
        return user.id


def count_nights(engine) -> int:
    with Session(engine) as session:
        return session.scalar(select(func.count()).select_from(Night))


def test_a_migration_that_rebuilds_users_keeps_every_night(empty_database):
    """SQLite rebuilds a table to alter it (DROP + rename). With foreign keys on, that DROP would cascade."""
    run_migrations(empty_database)
    add_user_with_a_night(empty_database)
    with migration_connection(empty_database) as connection:
        operations = Operations(MigrationContext.configure(connection, opts={"render_as_batch": True}))
        with operations.batch_alter_table("users") as batch:
            batch.alter_column("display_name", type_=String(200))
    assert count_nights(empty_database) == 1
    if empty_database.dialect.name == "sqlite":
        with empty_database.connect() as connection:
            assert connection.exec_driver_sql("PRAGMA foreign_keys").scalar() == 1  # switched on again


def test_a_migration_that_breaks_foreign_keys_is_rolled_back(empty_database):
    if empty_database.dialect.name != "sqlite":
        pytest.skip("PostgreSQL checks foreign keys on every statement; the extra check is for SQLite")
    run_migrations(empty_database)
    with pytest.raises(RuntimeError, match="missing rows"):
        with migration_connection(empty_database) as connection:
            connection.execute(
                Night.__table__.insert().values(
                    id=uuid.uuid4(), user_id=uuid.uuid4(), started_at=datetime.now(timezone.utc), device_name="d",
                    channels=["Fp1"], sample_rate=250, created_at=datetime.now(timezone.utc),
                    updated_at=datetime.now(timezone.utc),
                )
            )
    assert count_nights(empty_database) == 0


# --- database layer -----------------------------------------------------------------------


def make_user(email="row@example.com") -> User:
    return User(
        email=email,
        password_hash="x",
        consent_version="2026-11",
        consent_at=datetime.now(timezone.utc),
    )


def test_timestamps_come_back_as_utc(app, db):
    amsterdam_evening = datetime(2026, 11, 1, 23, 30, tzinfo=timezone(timedelta(hours=1)))
    user = make_user()
    db.add(user)
    db.flush()
    db.add(Night(user=user, started_at=amsterdam_evening, device_name="d", channels=["Fp1"], sample_rate=250))
    db.commit()
    db.expire_all()
    night = db.scalar(select(Night))
    assert night.started_at == amsterdam_evening
    assert night.started_at.tzinfo == timezone.utc
    assert night.started_at.hour == 22


def test_naive_timestamps_are_refused(app, db):
    user = make_user()
    user.consent_at = datetime(2026, 1, 1)
    db.add(user)
    with pytest.raises(Exception, match="Naive datetimes"):
        db.commit()
    db.rollback()


def test_deleting_a_user_in_the_database_cascades(app, db):
    """ON DELETE CASCADE works in the database itself (SQLite needs foreign keys switched on)."""
    now = datetime.now(timezone.utc)
    user = make_user()
    db.add(user)
    db.flush()
    night = Night(user_id=user.id, started_at=now, device_name="d", channels=["Fp1"], sample_rate=250)
    db.add(night)
    db.flush()
    db.add_all(
        [
            Epoch(night_id=night.id, index=0, started_at=now),
            Event(night_id=night.id, at=now, type="cue"),
            Recording(night_id=night.id, kind="edf", original_filename="a.edf", size_bytes=1, sha256="0" * 64,
                      storage_path="recordings/x"),
            JournalEntry(user_id=user.id, night_id=night.id, written_at=now, lucid="maybe", text="flying"),
            RefreshToken(user_id=user.id, token_hash="1" * 64, expires_at=now),
        ]
    )
    db.commit()
    user_id = user.id
    db.expunge_all()
    with db.get_bind().begin() as connection:
        connection.execute(User.__table__.delete().where(User.__table__.c.id == user_id))
    for model in (User, Night, Epoch, Event, Recording, JournalEntry, RefreshToken):
        assert db.scalars(select(model)).all() == [], model.__name__


def test_deleting_a_night_keeps_the_journal_entry(app, db):
    now = datetime.now(timezone.utc)
    user = make_user()
    db.add(user)
    db.flush()
    night = Night(user_id=user.id, started_at=now, device_name="d", channels=["Fp1"], sample_rate=250)
    db.add(night)
    db.flush()
    entry = JournalEntry(user_id=user.id, night_id=night.id, written_at=now, lucid="yes", text="I knew!")
    db.add(entry)
    db.commit()
    db.delete(night)
    db.commit()
    db.expire_all()
    assert db.get(JournalEntry, entry.id).night_id is None


def test_ids_are_uuid4(app, db):
    user = make_user()
    db.add(user)
    db.commit()
    assert isinstance(user.id, uuid.UUID) and user.id.version == 4
