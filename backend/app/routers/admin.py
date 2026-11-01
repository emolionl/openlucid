"""Admin-only user management (/admin)."""

import uuid

from fastapi import APIRouter, HTTPException, status
from sqlalchemy import func, select

from app.deps import AdminUser, DbSession, PageParams
from app.models import Night, User
from app.schemas import AdminUserOut, AdminUserUpdate, Page
from app.security import revoke_all_refresh_tokens

router = APIRouter(prefix="/admin", tags=["admin"])


def _admin_view(user: User, night_count: int) -> AdminUserOut:
    return AdminUserOut(
        id=user.id,
        email=user.email,
        display_name=user.display_name,
        role=user.role,
        is_active=user.is_active,
        created_at=user.created_at,
        night_count=night_count,
    )


@router.get("/users", response_model=Page[AdminUserOut])
def list_users(_admin: AdminUser, db: DbSession, page: PageParams) -> Page[AdminUserOut]:
    """All accounts, oldest first, with how many nights each has. Nothing about the nights themselves."""
    night_counts = (
        select(Night.user_id, func.count(Night.id).label("night_count")).group_by(Night.user_id).subquery()
    )
    rows = db.execute(
        select(User, func.coalesce(night_counts.c.night_count, 0))
        .outerjoin(night_counts, night_counts.c.user_id == User.id)
        .order_by(User.created_at, User.id)
        .limit(page.limit)
        .offset(page.offset)
    ).all()
    total = db.scalar(select(func.count()).select_from(User))
    return Page(items=[_admin_view(user, count) for user, count in rows], total=total)


@router.patch("/users/{user_id}", response_model=AdminUserOut)
def update_user(user_id: uuid.UUID, body: AdminUserUpdate, _admin: AdminUser, db: DbSession) -> AdminUserOut:
    """Change someone's role or switch their account on or off.

    The last active admin cannot be demoted or deactivated (409), so the server always keeps an admin.
    Deactivating an account signs it out everywhere.
    """
    target = db.get(User, user_id)
    if target is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="No such user.")

    new_role = body.role if body.role is not None else target.role
    new_active = body.is_active if body.is_active is not None else target.is_active
    loses_admin = target.role == "admin" and target.is_active and (new_role != "admin" or not new_active)
    if loses_admin:
        # PostgreSQL: lock every active admin row, the target too, always in the same (id) order. Two admins
        # demoting each other at the same moment then take turns instead of deadlocking.
        db.execute(
            select(User.id).where(User.role == "admin", User.is_active.is_(True)).order_by(User.id).with_for_update()
        )

    if target.is_active and not new_active:
        revoke_all_refresh_tokens(db, target.id)
    target.role = new_role
    target.is_active = new_active
    if loses_admin:
        # Write first, then count. On SQLite this write takes the database's single write lock, so the
        # count sees everything that a request which went first has committed.
        db.flush()
        active_admins = db.scalar(
            select(func.count()).select_from(User).where(User.role == "admin", User.is_active.is_(True))
        )
        if active_admins == 0:
            db.rollback()
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                detail="This is the last active admin. Make someone else admin first.",
            )
    db.commit()

    night_count = db.scalar(select(func.count(Night.id)).where(Night.user_id == target.id))
    return _admin_view(target, night_count)
