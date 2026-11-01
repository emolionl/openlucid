"""Tests for /admin/users: listing accounts and changing role or active state."""

import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import event, select
from sqlalchemy.orm import Session

from app.models import JournalEntry, Night, User
from tests.conftest import RegisteredUser

ADMIN_USER_FIELDS = {"id", "email", "display_name", "role", "is_active", "created_at", "night_count"}
START = datetime(2026, 10, 31, 23, 0, tzinfo=timezone.utc)


def add_nights(db: Session, user_id: str, how_many: int) -> None:
    for number in range(how_many):
        db.add(
            Night(
                user_id=uuid.UUID(user_id),
                client_id=f"night-{number}",
                started_at=START,
                device_name="Muse S",
                channels=["TP9"],
                sample_rate=256.0,
                notes="Secret dream notes.",
            )
        )
    db.commit()


def patch_user(client: TestClient, by: RegisteredUser, user_id: str, **changes):
    return client.patch(f"/admin/users/{user_id}", json=changes, headers=by.headers)


def login(client: TestClient, user: RegisteredUser):
    return client.post("/auth/login", json={"email": user.email, "password": user.password})


# --- GET /admin/users ---------------------------------------------------------------------


def test_list_users_with_night_counts(
    client: TestClient, db: Session, admin: RegisteredUser, alice: RegisteredUser, bob: RegisteredUser
):
    add_nights(db, alice.id, 3)
    add_nights(db, bob.id, 1)
    db.add(JournalEntry(user_id=uuid.UUID(alice.id), written_at=START, lucid="yes", text="Very private dream."))
    db.commit()

    response = client.get("/admin/users", headers=admin.headers)
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 3
    assert [item["email"] for item in body["items"]] == ["admin@example.com", "alice@example.com", "bob@example.com"]
    counts = {item["email"]: item["night_count"] for item in body["items"]}
    assert counts == {"admin@example.com": 0, "alice@example.com": 3, "bob@example.com": 1}
    for item in body["items"]:
        assert set(item) == ADMIN_USER_FIELDS
    assert body["items"][0]["role"] == "admin"
    assert body["items"][1]["display_name"] == "Alice"
    assert "Secret dream notes." not in response.text
    assert "Very private dream." not in response.text
    assert "password" not in response.text
    assert "consent" not in response.text


def test_list_users_pagination(client: TestClient, admin: RegisteredUser, alice: RegisteredUser, bob: RegisteredUser):
    body = client.get("/admin/users?limit=2", headers=admin.headers).json()
    assert body["total"] == 3
    assert [item["email"] for item in body["items"]] == ["admin@example.com", "alice@example.com"]
    body = client.get("/admin/users?limit=2&offset=2", headers=admin.headers).json()
    assert [item["email"] for item in body["items"]] == ["bob@example.com"]
    assert client.get("/admin/users?offset=10", headers=admin.headers).json() == {"items": [], "total": 3}


@pytest.mark.parametrize("query", ["limit=0", "limit=201", "offset=-1", "limit=many"])
def test_list_users_validation(client: TestClient, admin: RegisteredUser, query: str):
    assert client.get(f"/admin/users?{query}", headers=admin.headers).status_code == 422


def test_list_users_forbidden_for_non_admins(client: TestClient, alice: RegisteredUser):
    response = client.get("/admin/users", headers=alice.headers)
    assert response.status_code == 403
    assert "alice@example.com" not in response.text


def test_list_users_requires_sign_in(client: TestClient):
    assert client.get("/admin/users").status_code == 401


# --- PATCH /admin/users/{id} --------------------------------------------------------------


def test_promote_and_demote(client: TestClient, admin: RegisteredUser, alice: RegisteredUser):
    response = patch_user(client, admin, alice.id, role="admin")
    assert response.status_code == 200
    assert set(response.json()) == ADMIN_USER_FIELDS
    assert response.json()["role"] == "admin"
    assert client.get("/admin/users", headers=alice.headers).status_code == 200

    response = patch_user(client, admin, alice.id, role="user")
    assert response.status_code == 200
    assert response.json()["role"] == "user"
    assert client.get("/admin/users", headers=alice.headers).status_code == 403


def test_patch_returns_night_count(client: TestClient, db: Session, admin: RegisteredUser, alice: RegisteredUser):
    add_nights(db, alice.id, 2)
    assert patch_user(client, admin, alice.id, role="admin").json()["night_count"] == 2


def test_empty_patch_changes_nothing(client: TestClient, admin: RegisteredUser, alice: RegisteredUser):
    response = patch_user(client, admin, alice.id)
    assert response.status_code == 200
    assert response.json()["role"] == "user"
    assert response.json()["is_active"] is True


def test_deactivate_signs_out_and_blocks_login(client: TestClient, admin: RegisteredUser, alice: RegisteredUser):
    response = patch_user(client, admin, alice.id, is_active=False)
    assert response.status_code == 200
    assert response.json()["is_active"] is False

    assert login(client, alice).status_code == 403
    assert client.get("/me", headers=alice.headers).status_code == 403
    assert client.post("/auth/refresh", json={"refresh_token": alice.refresh_token}).status_code == 401

    assert patch_user(client, admin, alice.id, is_active=True).json()["is_active"] is True
    assert login(client, alice).status_code == 200
    assert client.get("/me", headers=alice.headers).status_code == 200


def test_deactivating_does_not_touch_other_users(
    client: TestClient, admin: RegisteredUser, alice: RegisteredUser, bob: RegisteredUser
):
    patch_user(client, admin, alice.id, is_active=False)
    assert client.get("/me", headers=bob.headers).status_code == 200
    assert client.post("/auth/refresh", json={"refresh_token": bob.refresh_token}).status_code == 200


def test_last_active_admin_cannot_demote_or_deactivate_self(client: TestClient, admin: RegisteredUser):
    assert patch_user(client, admin, admin.id, role="user").status_code == 409
    assert patch_user(client, admin, admin.id, is_active=False).status_code == 409
    assert patch_user(client, admin, admin.id, role="user", is_active=False).status_code == 409
    me = client.get("/me", headers=admin.headers).json()
    assert (me["role"], me["is_active"]) == ("admin", True)


def test_admin_may_step_down_when_another_admin_exists(
    client: TestClient, admin: RegisteredUser, alice: RegisteredUser
):
    patch_user(client, admin, alice.id, role="admin")
    response = patch_user(client, admin, admin.id, role="user")
    assert response.status_code == 200
    assert response.json()["role"] == "user"
    # Now Alice is the last active admin.
    assert patch_user(client, alice, alice.id, role="user").status_code == 409
    assert patch_user(client, alice, alice.id, is_active=False).status_code == 409


def test_inactive_admins_do_not_count(client: TestClient, admin: RegisteredUser, alice: RegisteredUser):
    patch_user(client, admin, alice.id, role="admin")
    assert patch_user(client, admin, alice.id, is_active=False).status_code == 200
    assert patch_user(client, admin, admin.id, role="user").status_code == 409


def test_admin_may_deactivate_another_admin(client: TestClient, admin: RegisteredUser, alice: RegisteredUser):
    patch_user(client, admin, alice.id, role="admin")
    response = patch_user(client, admin, alice.id, is_active=False)
    assert response.status_code == 200
    assert login(client, alice).status_code == 403


def test_last_admin_keeping_role_is_fine(client: TestClient, admin: RegisteredUser):
    response = patch_user(client, admin, admin.id, role="admin", is_active=True)
    assert response.status_code == 200


def test_patch_unknown_user(client: TestClient, admin: RegisteredUser):
    assert patch_user(client, admin, str(uuid.uuid4()), role="admin").status_code == 404


@pytest.mark.parametrize(
    "changes", [{"role": "superuser"}, {"role": "ADMIN"}, {"is_active": "maybe"}, {"role": 1}]
)
def test_patch_validation(client: TestClient, admin: RegisteredUser, alice: RegisteredUser, changes: dict):
    assert patch_user(client, admin, alice.id, **changes).status_code == 422


def test_patch_with_invalid_id(client: TestClient, admin: RegisteredUser):
    assert client.patch("/admin/users/not-a-uuid", json={}, headers=admin.headers).status_code == 422


def test_patch_forbidden_for_non_admins(client: TestClient, alice: RegisteredUser, bob: RegisteredUser):
    assert patch_user(client, alice, alice.id, role="admin").status_code == 403
    assert patch_user(client, alice, bob.id, is_active=False).status_code == 403
    assert patch_user(client, alice, str(uuid.uuid4()), role="admin").status_code == 403
    assert client.get("/me", headers=alice.headers).json()["role"] == "user"
    assert client.get("/me", headers=bob.headers).json()["is_active"] is True


def test_patch_requires_sign_in(client: TestClient, alice: RegisteredUser):
    assert client.patch(f"/admin/users/{alice.id}", json={"role": "admin"}).status_code == 401


def test_two_admins_demoting_each_other_at_once_leaves_one_admin(
    client: TestClient, db: Session, admin: RegisteredUser, alice: RegisteredUser
):
    """Both requests check "is another admin left?" at the same moment. One must win, the other gets 409."""
    assert patch_user(client, admin, alice.id, role="admin").status_code == 200
    both_about_to_write = threading.Barrier(2, timeout=2)

    def wait_for_the_other_request(*_args) -> None:
        # Hold each request just before its UPDATE, so both decide before either one writes.
        # The new locking makes the second request wait earlier, so then the barrier simply times out.
        try:
            both_about_to_write.wait()
        except threading.BrokenBarrierError:
            pass

    event.listen(client.app.state.session_factory, "before_flush", wait_for_the_other_request)
    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            demote_alice = pool.submit(patch_user, client, admin, alice.id, role="user")
            demote_admin = pool.submit(patch_user, client, alice, admin.id, role="user")
            statuses = sorted([demote_alice.result().status_code, demote_admin.result().status_code])
    finally:
        event.remove(client.app.state.session_factory, "before_flush", wait_for_the_other_request)

    assert statuses == [200, 409]
    db.expire_all()
    roles = db.scalars(select(User.role).where(User.is_active.is_(True))).all()
    assert roles.count("admin") == 1
