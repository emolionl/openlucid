"""Tests for /me: profile, password change, export and account deletion.

Nights, epochs, events, journal entries and recordings are written straight into the database
(and recording files onto disk), so these tests do not depend on the other routers.
"""

import threading
import time
import uuid
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import Epoch, Event, JournalEntry, Night, RefreshToken, Recording, User
from app.routers import account
from tests.conftest import RegisteredUser

NEW_PASSWORD = "a brand new password 42"
START = datetime(2026, 10, 31, 23, 0, tzinfo=timezone.utc)


def seed_night(db: Session, data_dir: Path, user_id: str, client_id: str = "night-1") -> Night:
    """One night with two epochs, two events, a journal entry and a recording file on disk."""
    owner = uuid.UUID(user_id)
    night = Night(
        user_id=owner,
        client_id=client_id,
        started_at=START,
        ended_at=START + timedelta(hours=7),
        device_name="OpenBCI Ganglion",
        channels=["Fp1", "Fp2"],
        sample_rate=200.0,
        timezone="Europe/Amsterdam",
        notes="Slept with the window open.",
    )
    db.add(night)
    db.flush()
    db.add_all(
        [
            Epoch(night_id=night.id, index=0, started_at=START, stage="wake", contact={"Fp1": 0.9}, quality="good"),
            Epoch(night_id=night.id, index=1, started_at=START + timedelta(seconds=30), stage="n1"),
            Event(night_id=night.id, client_id="ev-1", at=START + timedelta(hours=5), type="cue"),
            Event(night_id=night.id, at=START + timedelta(hours=5, minutes=1), type="lrlr", details={"count": 2}),
            JournalEntry(
                user_id=owner, night_id=night.id, written_at=START + timedelta(hours=7), lucid="maybe", text="A tower."
            ),
        ]
    )
    recording_id = uuid.uuid4()
    relative = Path("recordings") / user_id / str(night.id) / f"{recording_id}.edf"
    file_path = data_dir / relative
    file_path.parent.mkdir(parents=True, exist_ok=True)
    file_path.write_bytes(b"0       fake edf")
    db.add(
        Recording(
            id=recording_id,
            night_id=night.id,
            kind="edf",
            original_filename="night.edf",
            size_bytes=16,
            sha256="0" * 64,
            storage_path=relative.as_posix(),
        )
    )
    db.commit()
    return night


def login(client: TestClient, email: str, password: str):
    return client.post("/auth/login", json={"email": email, "password": password})


def count(db: Session, model, *where) -> int:
    db.rollback()  # start a fresh read, so changes made through the API are visible
    return db.scalar(select(func.count()).select_from(model).where(*where))


# --- GET /me ------------------------------------------------------------------------------


def test_get_me_returns_own_account_without_password_hash(client: TestClient, alice: RegisteredUser):
    response = client.get("/me", headers=alice.headers)
    assert response.status_code == 200
    body = response.json()
    assert body["id"] == alice.id
    assert body["email"] == "alice@example.com"
    assert body["display_name"] == "Alice"
    assert body["role"] == "user"
    assert body["is_active"] is True
    assert "password_hash" not in body
    assert "password" not in str(body)


def test_get_me_requires_sign_in(client: TestClient):
    assert client.get("/me").status_code == 401
    response = client.get("/me", headers={"Authorization": "Bearer not-a-token"})
    assert response.status_code == 401
    assert response.headers["WWW-Authenticate"] == "Bearer"


# --- PATCH /me ----------------------------------------------------------------------------


def test_patch_me_changes_display_name(client: TestClient, alice: RegisteredUser, bob: RegisteredUser):
    response = client.patch("/me", json={"display_name": "Alice in Dreamland"}, headers=alice.headers)
    assert response.status_code == 200
    assert response.json()["display_name"] == "Alice in Dreamland"
    assert client.get("/me", headers=alice.headers).json()["display_name"] == "Alice in Dreamland"
    assert client.get("/me", headers=bob.headers).json()["display_name"] == "Bob"


def test_patch_me_without_field_keeps_and_null_clears(client: TestClient, alice: RegisteredUser):
    assert client.patch("/me", json={}, headers=alice.headers).json()["display_name"] == "Alice"
    assert client.patch("/me", json={"display_name": None}, headers=alice.headers).json()["display_name"] is None


def test_patch_me_validation(client: TestClient, alice: RegisteredUser):
    assert client.patch("/me", json={"display_name": "x" * 101}, headers=alice.headers).status_code == 422
    assert client.patch("/me", json={"display_name": 12}, headers=alice.headers).status_code == 422


def test_patch_me_refuses_nul_characters(client: TestClient, alice: RegisteredUser):
    assert client.patch("/me", json={"display_name": "Al" + chr(0)}, headers=alice.headers).status_code == 422


def test_patch_me_requires_sign_in(client: TestClient):
    assert client.patch("/me", json={"display_name": "Nobody"}).status_code == 401


def test_patch_me_cannot_change_role_or_email(client: TestClient, alice: RegisteredUser):
    response = client.patch(
        "/me", json={"role": "admin", "email": "evil@example.com", "is_active": False}, headers=alice.headers
    )
    assert response.status_code == 200
    body = response.json()
    assert body["role"] == "user"
    assert body["email"] == "alice@example.com"
    assert body["is_active"] is True


# --- POST /me/password --------------------------------------------------------------------


def test_change_password(client: TestClient, alice: RegisteredUser):
    response = client.post(
        "/me/password",
        json={"current_password": alice.password, "new_password": NEW_PASSWORD},
        headers=alice.headers,
    )
    assert response.status_code == 204
    assert response.content == b""
    assert login(client, alice.email, alice.password).status_code == 401
    assert login(client, alice.email, NEW_PASSWORD).status_code == 200


def test_change_password_revokes_all_refresh_tokens(client: TestClient, db: Session, alice: RegisteredUser):
    second_device = login(client, alice.email, alice.password).json()["refresh_token"]
    response = client.post(
        "/me/password",
        json={"current_password": alice.password, "new_password": NEW_PASSWORD},
        headers=alice.headers,
    )
    assert response.status_code == 204
    for refresh_token in (alice.refresh_token, second_device):
        assert client.post("/auth/refresh", json={"refresh_token": refresh_token}).status_code == 401
    assert count(db, RefreshToken, RefreshToken.user_id == uuid.UUID(alice.id), RefreshToken.revoked_at.is_(None)) == 0


def test_change_password_leaves_other_users_alone(client: TestClient, alice: RegisteredUser, bob: RegisteredUser):
    client.post(
        "/me/password",
        json={"current_password": alice.password, "new_password": NEW_PASSWORD},
        headers=alice.headers,
    )
    assert client.post("/auth/refresh", json={"refresh_token": bob.refresh_token}).status_code == 200
    assert login(client, bob.email, bob.password).status_code == 200


def test_change_password_wrong_current_password(client: TestClient, alice: RegisteredUser):
    response = client.post(
        "/me/password",
        json={"current_password": "not my password", "new_password": NEW_PASSWORD},
        headers=alice.headers,
    )
    assert response.status_code == 403
    assert login(client, alice.email, alice.password).status_code == 200
    assert client.post("/auth/refresh", json={"refresh_token": alice.refresh_token}).status_code == 200


def test_change_password_validation(client: TestClient, alice: RegisteredUser):
    too_short = {"current_password": alice.password, "new_password": "short"}
    assert client.post("/me/password", json=too_short, headers=alice.headers).status_code == 422
    missing = {"new_password": NEW_PASSWORD}
    assert client.post("/me/password", json=missing, headers=alice.headers).status_code == 422
    assert login(client, alice.email, alice.password).status_code == 200


def test_change_password_requires_sign_in(client: TestClient):
    body = {"current_password": "whatever it is", "new_password": NEW_PASSWORD}
    assert client.post("/me/password", json=body).status_code == 401


def test_change_password_is_rate_limited(client: TestClient, alice: RegisteredUser):
    wrong = {"current_password": "guess number x", "new_password": NEW_PASSWORD}
    for _ in range(10):
        assert client.post("/me/password", json=wrong, headers=alice.headers).status_code == 403
    response = client.post(
        "/me/password", json={"current_password": alice.password, "new_password": NEW_PASSWORD}, headers=alice.headers
    )
    assert response.status_code == 429
    assert int(response.headers["Retry-After"]) > 0


def test_parallel_wrong_passwords_cannot_get_past_the_limit(
    client: TestClient, alice: RegisteredUser, monkeypatch: pytest.MonkeyPatch
):
    checks = []
    lock = threading.Lock()

    def slow_wrong_verify(_password_hash, _password) -> bool:
        with lock:
            checks.append(1)
        time.sleep(0.3)  # every parallel request arrives while the first checks still run
        return False

    monkeypatch.setattr(account, "verify_password", slow_wrong_verify)
    with ThreadPoolExecutor(max_workers=20) as pool:
        statuses = Counter(pool.map(lambda _: delete_me(client, alice, "a wrong guess").status_code, range(20)))
    assert len(checks) == 10
    assert statuses == {403: 10, 429: 10}


# --- GET /me/export -----------------------------------------------------------------------


def test_export_contains_everything(
    client: TestClient, db: Session, data_dir: Path, alice: RegisteredUser, bob: RegisteredUser
):
    night = seed_night(db, data_dir, alice.id)
    seed_night(db, data_dir, bob.id)

    response = client.get("/me/export", headers=alice.headers)
    assert response.status_code == 200
    assert response.headers["Content-Disposition"] == 'attachment; filename="openlucid-export.json"'
    assert response.headers["Content-Type"].startswith("application/json")
    export = response.json()

    assert export["exported_at"]
    assert export["user"]["id"] == alice.id
    assert "password_hash" not in export["user"]

    assert [n["id"] for n in export["nights"]] == [str(night.id)]
    exported_night = export["nights"][0]
    assert exported_night["notes"] == "Slept with the window open."
    assert exported_night["channels"] == ["Fp1", "Fp2"]
    assert [e["index"] for e in exported_night["epochs"]] == [0, 1]
    assert exported_night["epochs"][0]["contact"] == {"Fp1": 0.9}
    assert [e["type"] for e in exported_night["events"]] == ["cue", "lrlr"]
    assert exported_night["events"][1]["details"] == {"count": 2}

    assert len(export["journal_entries"]) == 1
    assert export["journal_entries"][0]["text"] == "A tower."
    assert export["journal_entries"][0]["night_id"] == str(night.id)

    assert len(export["recordings"]) == 1
    recording = export["recordings"][0]
    assert recording["original_filename"] == "night.edf"
    assert recording["night_id"] == str(night.id)
    assert "storage_path" not in recording
    assert "recordings/" not in response.text  # no paths on disk leak out
    assert bob.id not in response.text  # nothing of another user


def test_export_of_new_account_is_empty(client: TestClient, alice: RegisteredUser):
    export = client.get("/me/export", headers=alice.headers).json()
    assert export["user"]["email"] == alice.email
    assert export["nights"] == []
    assert export["journal_entries"] == []
    assert export["recordings"] == []


def test_export_includes_journal_entries_without_night(client: TestClient, db: Session, alice: RegisteredUser):
    db.add(JournalEntry(user_id=uuid.UUID(alice.id), written_at=START, lucid="yes", vividness=5, text="Flying."))
    db.commit()
    entries = client.get("/me/export", headers=alice.headers).json()["journal_entries"]
    assert [(e["text"], e["night_id"], e["vividness"]) for e in entries] == [("Flying.", None, 5)]


def test_export_requires_sign_in(client: TestClient):
    assert client.get("/me/export").status_code == 401


# --- DELETE /me ---------------------------------------------------------------------------


def delete_me(client: TestClient, user: RegisteredUser, password: str):
    return client.request("DELETE", "/me", json={"password": password}, headers=user.headers)


def test_delete_me_removes_account_rows_and_files(
    client: TestClient, db: Session, data_dir: Path, alice: RegisteredUser, bob: RegisteredUser
):
    alice_night_id = seed_night(db, data_dir, alice.id).id
    seed_night(db, data_dir, alice.id, client_id="night-2")
    bob_night_id = seed_night(db, data_dir, bob.id).id
    alice_dir = data_dir / "recordings" / alice.id
    bob_dir = data_dir / "recordings" / bob.id
    assert len(list(alice_dir.rglob("*.edf"))) == 2

    response = delete_me(client, alice, alice.password)
    assert response.status_code == 204
    assert response.content == b""

    # Signing in no longer works, and the old tokens are dead.
    assert login(client, alice.email, alice.password).status_code == 401
    assert client.get("/me", headers=alice.headers).status_code == 401
    assert client.post("/auth/refresh", json={"refresh_token": alice.refresh_token}).status_code == 401

    # Every row of Alice is gone.
    alice_id = uuid.UUID(alice.id)
    assert count(db, User, User.id == alice_id) == 0
    assert count(db, Night, Night.user_id == alice_id) == 0
    assert count(db, Epoch, Epoch.night_id == alice_night_id) == 0
    assert count(db, Event, Event.night_id == alice_night_id) == 0
    assert count(db, JournalEntry, JournalEntry.user_id == alice_id) == 0
    assert count(db, Recording, Recording.night_id == alice_night_id) == 0
    assert count(db, RefreshToken, RefreshToken.user_id == alice_id) == 0

    # Her files are gone; Bob's data and files are untouched.
    assert not alice_dir.exists()
    assert len(list(bob_dir.rglob("*.edf"))) == 1
    assert count(db, Night, Night.user_id == uuid.UUID(bob.id)) == 1
    assert count(db, Epoch, Epoch.night_id == bob_night_id) == 2
    assert login(client, bob.email, bob.password).status_code == 200
    assert len(client.get("/me/export", headers=bob.headers).json()["nights"]) == 1


def test_delete_me_while_a_recording_is_open_removes_the_file_later(
    client: TestClient, make_client, db: Session, data_dir: Path, alice: RegisteredUser
):
    """On Windows an open file (e.g. a download in progress) cannot be removed; it must go once it is closed."""
    seed_night(db, data_dir, alice.id)
    alice_dir = data_dir / "recordings" / alice.id
    (edf,) = alice_dir.rglob("*.edf")
    with open(edf, "rb"):
        assert delete_me(client, alice, alice.password).status_code == 204
    make_client()  # a restart of the server retries what could not be removed
    assert not alice_dir.exists()


def test_delete_me_without_any_data(client: TestClient, db: Session, alice: RegisteredUser):
    assert delete_me(client, alice, alice.password).status_code == 204
    assert count(db, User, User.id == uuid.UUID(alice.id)) == 0


def test_delete_me_never_touches_files_outside_data_dir(
    client: TestClient, db: Session, data_dir: Path, alice: RegisteredUser
):
    night = seed_night(db, data_dir, alice.id)
    outside = data_dir.parent / "outside.txt"
    outside.write_text("keep me", encoding="utf-8")
    db.add(
        Recording(
            night_id=night.id,
            kind="other",
            original_filename="evil.txt",
            size_bytes=7,
            sha256="0" * 64,
            storage_path="../outside.txt",
        )
    )
    db.commit()
    assert delete_me(client, alice, alice.password).status_code == 204
    assert outside.read_text(encoding="utf-8") == "keep me"


def test_delete_me_wrong_password_keeps_everything(
    client: TestClient, db: Session, data_dir: Path, alice: RegisteredUser
):
    seed_night(db, data_dir, alice.id)
    assert delete_me(client, alice, "not my password").status_code == 403
    assert client.get("/me", headers=alice.headers).status_code == 200
    assert count(db, Night, Night.user_id == uuid.UUID(alice.id)) == 1
    assert len(list((data_dir / "recordings" / alice.id).rglob("*.edf"))) == 1


@pytest.mark.parametrize("body", [None, {}, {"password": ""}, {"pass": "x"}])
def test_delete_me_validation(client: TestClient, alice: RegisteredUser, body):
    response = client.request("DELETE", "/me", json=body, headers=alice.headers)
    assert response.status_code == 422
    assert client.get("/me", headers=alice.headers).status_code == 200


def test_delete_me_requires_sign_in(client: TestClient):
    assert client.request("DELETE", "/me", json={"password": "anything"}).status_code == 401


def test_deleted_email_can_register_again(client: TestClient, register_user, alice: RegisteredUser):
    assert delete_me(client, alice, alice.password).status_code == 204
    user, headers = register_user(client, email=alice.email)
    assert user["id"] != alice.id
    assert user["role"] == "user"
    assert client.get("/me/export", headers=headers).json()["nights"] == []


def test_last_admin_can_delete_own_account(client: TestClient, db: Session, admin: RegisteredUser):
    """Deleting your own account is a privacy right; it is not blocked by the last-admin rule."""
    assert delete_me(client, admin, admin.password).status_code == 204
    assert count(db, User) == 0
