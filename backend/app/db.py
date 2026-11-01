"""Database plumbing: the declarative Base, engines, sessions and migrations.

Each app (see create_app) owns its own engine and session factory, stored on app.state,
so tests can run many apps side by side against different databases.
"""

from collections.abc import Iterator
from contextlib import contextmanager
from datetime import datetime, timezone

from alembic import command
from alembic.config import Config
from fastapi import Request
from sqlalchemy import Connection, DateTime, Engine, MetaData, create_engine, event
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker
from sqlalchemy.types import TypeDecorator

from app.config import BACKEND_DIR

# Fixed constraint names, so migrations look the same on SQLite and PostgreSQL.
NAMING_CONVENTION = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_N_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=NAMING_CONVENTION)


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class UTCDateTime(TypeDecorator):
    """A timestamp that always goes in and comes out as timezone-aware UTC.

    SQLite forgets time zones, so we convert to UTC on the way in and re-attach UTC on the way out.
    """

    impl = DateTime(timezone=True)
    cache_ok = True

    def process_bind_param(self, value: datetime | None, dialect) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            raise ValueError("Naive datetimes are not allowed; give a time zone.")
        return value.astimezone(timezone.utc)

    def process_result_value(self, value: datetime | None, dialect) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)


def make_engine(database_url: str) -> Engine:
    """Create an engine. For SQLite: allow use from worker threads and switch on foreign keys."""
    if database_url.startswith("sqlite"):
        engine = create_engine(database_url, connect_args={"check_same_thread": False})

        @event.listens_for(engine, "connect")
        def _sqlite_foreign_keys(dbapi_connection, _record):
            cursor = dbapi_connection.cursor()
            cursor.execute("PRAGMA foreign_keys=ON")
            cursor.close()

        return engine
    return create_engine(database_url, pool_pre_ping=True)


def make_session_factory(engine: Engine) -> sessionmaker[Session]:
    return sessionmaker(bind=engine, expire_on_commit=False)


def get_db(request: Request) -> Iterator[Session]:
    """FastAPI dependency: one database session per request, always closed afterwards."""
    session = request.app.state.session_factory()
    try:
        yield session
    finally:
        session.close()


def alembic_config(connection: Connection) -> Config:
    """Alembic settings that migrate through `connection` and leave the app's logging alone."""
    config = Config(str(BACKEND_DIR / "alembic.ini"))
    config.set_main_option("script_location", str(BACKEND_DIR / "alembic"))
    config.attributes["configure_logger"] = False
    config.attributes["connection"] = connection
    return config


@contextmanager
def migration_connection(engine: Engine) -> Iterator[Connection]:
    """A connection to migrate with, inside a transaction that commits at the end.

    On SQLite, foreign keys are switched off while migrating. SQLite's ALTER is so limited that Alembic
    rebuilds a table by copying it and dropping the old one; with foreign keys on, that DROP would
    cascade-delete every child row (all nights of all users when `users` is rebuilt). The switch only works
    outside a transaction, so it happens before the transaction starts. Afterwards
    `PRAGMA foreign_key_check` must come back empty, or the migration is rolled back.
    """
    with engine.connect() as connection:
        is_sqlite = connection.dialect.name == "sqlite"
        if is_sqlite:
            connection.exec_driver_sql("PRAGMA foreign_keys=OFF")
            connection.commit()
        try:
            with connection.begin():
                yield connection
                if is_sqlite and connection.exec_driver_sql("PRAGMA foreign_key_check").first() is not None:
                    raise RuntimeError("The migration left rows that point to missing rows; it was rolled back.")
        finally:
            if is_sqlite:
                connection.exec_driver_sql("PRAGMA foreign_keys=ON")  # the pooled connection is reused later
                connection.commit()


def run_migrations(engine: Engine, revision: str = "head") -> None:
    """Bring the database schema up to `revision` with Alembic (same as `alembic upgrade head`)."""
    with migration_connection(engine) as connection:
        command.upgrade(alembic_config(connection), revision)
