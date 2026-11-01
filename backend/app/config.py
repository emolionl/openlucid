"""Settings for the Diary Keeper, read from OPENLUCID_* environment variables and backend/.env.

The defaults run on a laptop with no setup: SQLite and files in ./data. A server is opt-in.
"""

from pathlib import Path
from typing import Literal

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

APP_NAME = "openlucid"
APP_VERSION = "0.2.0"
BACKEND_DIR = Path(__file__).resolve().parent.parent
MIN_SECRET_KEY_LENGTH = 32


class Settings(BaseSettings):
    """Every knob the server has. See SPEC.md for what each one means."""

    model_config = SettingsConfigDict(
        env_prefix="OPENLUCID_",
        env_file=BACKEND_DIR / ".env",
        env_file_encoding="utf-8",
        env_ignore_empty=True,  # `OPENLUCID_SECRET_KEY=` (as in an unfilled .env.example) means "not set"
        extra="ignore",
    )

    mode: Literal["local", "server"] = "local"
    data_dir: Path = Path("./data")
    database_url: str = ""  # empty means: SQLite file inside data_dir
    secret_key: str | None = None
    access_token_minutes: int = Field(default=15, ge=1)
    refresh_token_days: int = Field(default=30, ge=1)
    allow_registration: bool = True
    cors_origins: str = ""  # comma-separated extra origins
    max_upload_mb: int = Field(default=200, ge=1)
    auto_migrate: bool = True
    consent_version: str = "2026-11"

    @model_validator(mode="after")
    def check_and_fill(self) -> "Settings":
        """Fill the default database URL and refuse unsafe server setups."""
        if not self.database_url:
            sqlite_path = (self.data_dir / "openlucid.db").resolve().as_posix()
            self.database_url = f"sqlite:///{sqlite_path}"
        if self.secret_key is not None and len(self.secret_key) < MIN_SECRET_KEY_LENGTH:
            raise ValueError(f"OPENLUCID_SECRET_KEY must be at least {MIN_SECRET_KEY_LENGTH} characters long.")
        if self.mode == "server" and self.secret_key is None:
            raise ValueError("Server mode needs OPENLUCID_SECRET_KEY (at least 32 characters). Refusing to start.")
        return self

    @property
    def cors_origin_list(self) -> list[str]:
        """The extra allowed origins as a list (localhost is always allowed on top of these)."""
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

    @property
    def max_upload_bytes(self) -> int:
        return self.max_upload_mb * 1024 * 1024

    @property
    def secret_key_file(self) -> Path:
        """Where local mode keeps its generated signing key."""
        return self.data_dir / "secret_key"
