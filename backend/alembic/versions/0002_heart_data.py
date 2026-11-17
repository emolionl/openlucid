"""heart data from a chest strap: nights.heart_device, and heart rate, HRV and RR intervals per epoch

Revision ID: 0002
Revises: 0001
Create Date: 2026-11-17
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

EPOCH_COLUMNS = ("heart_rate", "hrv_rmssd", "hrv_sdnn", "rr_intervals")


def upgrade() -> None:
    # Batch mode: a plain ALTER on PostgreSQL; on SQLite adding a nullable column is a plain ALTER too.
    with op.batch_alter_table("nights") as batch:
        batch.add_column(sa.Column("heart_device", sa.String(length=100), nullable=True))

    with op.batch_alter_table("epochs") as batch:
        batch.add_column(sa.Column("heart_rate", sa.Float(), nullable=True))
        batch.add_column(sa.Column("hrv_rmssd", sa.Float(), nullable=True))
        batch.add_column(sa.Column("hrv_sdnn", sa.Float(), nullable=True))
        batch.add_column(sa.Column("rr_intervals", sa.JSON(), nullable=True))


def downgrade() -> None:
    # On SQLite batch mode rebuilds the table without these columns (app.db.migration_connection keeps
    # foreign keys off meanwhile, so nothing cascades); on PostgreSQL it is a plain DROP COLUMN.
    with op.batch_alter_table("epochs") as batch:
        for column in reversed(EPOCH_COLUMNS):
            batch.drop_column(column)

    with op.batch_alter_table("nights") as batch:
        batch.drop_column("heart_device")
