"""initial tables: users, refresh tokens, nights, epochs, events, journal entries, recordings

Revision ID: 0001
Revises:
Create Date: 2026-11-01
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("email", sa.String(length=254), nullable=False),
        sa.Column("password_hash", sa.String(length=255), nullable=False),
        sa.Column("display_name", sa.String(length=100), nullable=True),
        sa.Column("role", sa.String(length=10), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("consent_version", sa.String(length=40), nullable=False),
        sa.Column("consent_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id", name="pk_users"),
        sa.UniqueConstraint("email", name="uq_users_email"),
    )

    op.create_table(
        "refresh_tokens",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("replaced_by_id", sa.Uuid(), nullable=True),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name="fk_refresh_tokens_user_id_users", ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["replaced_by_id"],
            ["refresh_tokens.id"],
            name="fk_refresh_tokens_replaced_by_id_refresh_tokens",
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_refresh_tokens"),
        sa.UniqueConstraint("token_hash", name="uq_refresh_tokens_token_hash"),
    )
    op.create_index("ix_refresh_tokens_user_id", "refresh_tokens", ["user_id"])

    op.create_table(
        "nights",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("client_id", sa.String(length=64), nullable=True),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("device_name", sa.String(length=100), nullable=False),
        sa.Column("device_firmware", sa.String(length=100), nullable=True),
        sa.Column("channels", sa.JSON(), nullable=False),
        sa.Column("sample_rate", sa.Float(), nullable=False),
        sa.Column("timezone", sa.String(length=64), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], name="fk_nights_user_id_users", ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id", name="pk_nights"),
        sa.UniqueConstraint("user_id", "client_id", name="uq_nights_user_id_client_id"),
    )
    op.create_index("ix_nights_user_id", "nights", ["user_id"])

    op.create_table(
        "epochs",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("night_id", sa.Uuid(), nullable=False),
        sa.Column("index", sa.Integer(), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("stage", sa.String(length=10), nullable=True),
        sa.Column("stage_confidence", sa.Float(), nullable=True),
        sa.Column("contact", sa.JSON(), nullable=True),
        sa.Column("quality", sa.String(length=10), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["night_id"], ["nights.id"], name="fk_epochs_night_id_nights", ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id", name="pk_epochs"),
        sa.UniqueConstraint("night_id", "index", name="uq_epochs_night_id_index"),
    )
    op.create_index("ix_epochs_night_id", "epochs", ["night_id"])

    op.create_table(
        "events",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("night_id", sa.Uuid(), nullable=False),
        sa.Column("client_id", sa.String(length=64), nullable=True),
        sa.Column("at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("type", sa.String(length=40), nullable=False),
        sa.Column("details", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["night_id"], ["nights.id"], name="fk_events_night_id_nights", ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id", name="pk_events"),
        sa.UniqueConstraint("night_id", "client_id", name="uq_events_night_id_client_id"),
    )
    op.create_index("ix_events_night_id", "events", ["night_id"])

    op.create_table(
        "journal_entries",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("night_id", sa.Uuid(), nullable=True),
        sa.Column("written_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("lucid", sa.String(length=10), nullable=False),
        sa.Column("vividness", sa.Integer(), nullable=True),
        sa.Column("text", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name="fk_journal_entries_user_id_users", ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["night_id"], ["nights.id"], name="fk_journal_entries_night_id_nights", ondelete="SET NULL"
        ),
        sa.PrimaryKeyConstraint("id", name="pk_journal_entries"),
    )
    op.create_index("ix_journal_entries_user_id", "journal_entries", ["user_id"])
    op.create_index("ix_journal_entries_night_id", "journal_entries", ["night_id"])

    op.create_table(
        "recordings",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("night_id", sa.Uuid(), nullable=False),
        sa.Column("kind", sa.String(length=10), nullable=False),
        sa.Column("original_filename", sa.String(length=200), nullable=False),
        sa.Column("size_bytes", sa.BigInteger(), nullable=False),
        sa.Column("sha256", sa.String(length=64), nullable=False),
        sa.Column("storage_path", sa.String(length=500), nullable=False),
        sa.Column("uploaded_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["night_id"], ["nights.id"], name="fk_recordings_night_id_nights", ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name="pk_recordings"),
    )
    op.create_index("ix_recordings_night_id", "recordings", ["night_id"])


def downgrade() -> None:
    op.drop_table("recordings")
    op.drop_table("journal_entries")
    op.drop_table("events")
    op.drop_table("epochs")
    op.drop_table("nights")
    op.drop_table("refresh_tokens")
    op.drop_table("users")
