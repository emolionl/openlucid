"""Tests for /journal: create, list (with night filter), read, update, delete, validation and privacy."""

import uuid
from datetime import datetime, timezone

import pytest

from app.models import JournalEntry, Night

ENTRY = {"lucid": "yes", "vividness": 4, "text": "I noticed my hands and knew I was dreaming."}


def make_night(db, user_id: str, started_at: datetime | None = None) -> str:
    """Put a night straight into the database (the nights API is tested on its own)."""
    night = Night(
        user_id=uuid.UUID(user_id),
        started_at=started_at or datetime(2026, 11, 1, 23, 0, tzinfo=timezone.utc),
        device_name="Test headband",
        channels=["Fp1", "Fp2"],
        sample_rate=250.0,
    )
    db.add(night)
    db.commit()
    return str(night.id)


def write(client, user, **fields):
    response = client.post("/journal", json={**ENTRY, **fields}, headers=user.headers)
    assert response.status_code == 201, response.text
    return response.json()


# --- create -------------------------------------------------------------------------------


def test_create_entry_with_defaults(client, alice):
    before = datetime.now(timezone.utc)
    body = {"lucid": "maybe", "text": "A train through a forest."}
    response = client.post("/journal", json=body, headers=alice.headers)
    assert response.status_code == 201, response.text
    entry = response.json()
    assert entry["lucid"] == "maybe"
    assert entry["vividness"] is None
    assert entry["night_id"] is None
    assert entry["text"] == "A train through a forest."
    assert datetime.fromisoformat(entry["written_at"]) >= before.replace(microsecond=0)
    assert set(entry) == {"id", "night_id", "written_at", "lucid", "vividness", "text", "created_at", "updated_at"}


def test_create_entry_for_own_night_converts_time_to_utc(client, alice, db):
    night_id = make_night(db, alice.id)
    entry = write(client, alice, night_id=night_id, written_at="2026-11-02T07:30:00+01:00")
    assert entry["night_id"] == night_id
    assert datetime.fromisoformat(entry["written_at"]) == datetime(2026, 11, 2, 6, 30, tzinfo=timezone.utc)


def test_create_entry_for_another_users_night_is_404(client, alice, bob, db):
    bobs_night = make_night(db, bob.id)
    response = client.post("/journal", json={**ENTRY, "night_id": bobs_night}, headers=alice.headers)
    assert response.status_code == 404
    assert response.json() == {"detail": "Night not found."}


def test_create_entry_for_unknown_night_is_404(client, alice):
    response = client.post("/journal", json={**ENTRY, "night_id": str(uuid.uuid4())}, headers=alice.headers)
    assert response.status_code == 404


@pytest.mark.parametrize(
    "fields",
    [
        {"lucid": "definitely"},
        {"lucid": None},
        {"vividness": 0},
        {"vividness": 6},
        {"vividness": "very"},
        {"text": "x" * 20001},
        {"written_at": "2026-11-02T07:30:00"},  # no time zone
        {"night_id": "not-a-uuid"},
    ],
)
def test_create_entry_validation(client, alice, fields):
    response = client.post("/journal", json={**ENTRY, **fields}, headers=alice.headers)
    assert response.status_code == 422, response.text


@pytest.mark.parametrize("missing", ["lucid", "text"])
def test_create_entry_requires_lucid_and_text(client, alice, missing):
    body = {name: value for name, value in ENTRY.items() if name != missing}
    assert client.post("/journal", json=body, headers=alice.headers).status_code == 422


def test_create_entry_accepts_limits(client, alice):
    entry = write(client, alice, vividness=1, text="x" * 20000)
    assert len(entry["text"]) == 20000
    assert write(client, alice, vividness=5)["vividness"] == 5


# --- list ---------------------------------------------------------------------------------


def test_list_entries_newest_first_and_only_own(client, alice, bob):
    write(client, alice, written_at="2026-10-30T07:00:00Z", text="old")
    write(client, alice, written_at="2026-11-01T07:00:00Z", text="new")
    write(client, alice, written_at="2026-10-31T07:00:00Z", text="middle")
    write(client, bob, text="bob's dream")

    response = client.get("/journal", headers=alice.headers)
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 3
    assert [entry["text"] for entry in body["items"]] == ["new", "middle", "old"]


def test_list_entries_pagination(client, alice):
    for day in range(1, 6):
        write(client, alice, written_at=f"2026-10-0{day}T07:00:00Z", text=f"day {day}")
    body = client.get("/journal?limit=2&offset=1", headers=alice.headers).json()
    assert body["total"] == 5
    assert [entry["text"] for entry in body["items"]] == ["day 4", "day 3"]


@pytest.mark.parametrize("query", ["limit=0", "limit=201", "offset=-1", "night_id=nope"])
def test_list_entries_bad_query_is_422(client, alice, query):
    assert client.get(f"/journal?{query}", headers=alice.headers).status_code == 422


def test_list_entries_filtered_by_night(client, alice, db):
    night_a = make_night(db, alice.id)
    night_b = make_night(db, alice.id)
    write(client, alice, night_id=night_a, text="about night a")
    write(client, alice, night_id=night_b, text="about night b")
    write(client, alice, text="no night")

    body = client.get(f"/journal?night_id={night_a}", headers=alice.headers).json()
    assert body["total"] == 1
    assert body["items"][0]["text"] == "about night a"


def test_list_entries_filtered_by_another_users_night_is_404(client, alice, bob, db):
    bobs_night = make_night(db, bob.id)
    write(client, bob, night_id=bobs_night)
    response = client.get(f"/journal?night_id={bobs_night}", headers=alice.headers)
    assert response.status_code == 404


# --- read ---------------------------------------------------------------------------------


def test_get_entry(client, alice):
    entry = write(client, alice)
    response = client.get(f"/journal/{entry['id']}", headers=alice.headers)
    assert response.status_code == 200
    assert response.json() == entry


def test_get_unknown_entry_is_404(client, alice):
    response = client.get(f"/journal/{uuid.uuid4()}", headers=alice.headers)
    assert response.status_code == 404
    assert response.json() == {"detail": "Journal entry not found."}


def test_get_entry_bad_id_is_422(client, alice):
    assert client.get("/journal/not-a-uuid", headers=alice.headers).status_code == 422


# --- update -------------------------------------------------------------------------------


def test_update_entry_changes_only_sent_fields(client, alice):
    entry = write(client, alice)
    response = client.patch(f"/journal/{entry['id']}", json={"lucid": "no", "vividness": 2}, headers=alice.headers)
    assert response.status_code == 200, response.text
    updated = response.json()
    assert updated["lucid"] == "no"
    assert updated["vividness"] == 2
    assert updated["text"] == entry["text"]
    assert updated["written_at"] == entry["written_at"]
    assert updated["updated_at"] >= entry["updated_at"]
    assert client.get(f"/journal/{entry['id']}", headers=alice.headers).json() == updated


def test_update_entry_links_and_unlinks_night(client, alice, db):
    night_id = make_night(db, alice.id)
    entry = write(client, alice, vividness=3)

    linked = client.patch(f"/journal/{entry['id']}", json={"night_id": night_id}, headers=alice.headers)
    assert linked.status_code == 200
    assert linked.json()["night_id"] == night_id

    cleared = client.patch(f"/journal/{entry['id']}", json={"night_id": None, "vividness": None}, headers=alice.headers)
    assert cleared.status_code == 200
    assert cleared.json()["night_id"] is None
    assert cleared.json()["vividness"] is None


def test_update_entry_to_another_users_night_is_404(client, alice, bob, db):
    bobs_night = make_night(db, bob.id)
    entry = write(client, alice)
    response = client.patch(f"/journal/{entry['id']}", json={"night_id": bobs_night}, headers=alice.headers)
    assert response.status_code == 404
    assert client.get(f"/journal/{entry['id']}", headers=alice.headers).json()["night_id"] is None


@pytest.mark.parametrize(
    "fields",
    [
        {"lucid": "sort of"},
        {"lucid": None},
        {"text": None},
        {"written_at": None},
        {"vividness": 9},
        {"text": "x" * 20001},
    ],
)
def test_update_entry_validation(client, alice, fields):
    entry = write(client, alice)
    response = client.patch(f"/journal/{entry['id']}", json=fields, headers=alice.headers)
    assert response.status_code == 422, response.text
    assert client.get(f"/journal/{entry['id']}", headers=alice.headers).json() == entry


def test_update_unknown_entry_is_404(client, alice):
    response = client.patch(f"/journal/{uuid.uuid4()}", json={"lucid": "no"}, headers=alice.headers)
    assert response.status_code == 404


# --- delete -------------------------------------------------------------------------------


def test_delete_entry(client, alice, db):
    entry = write(client, alice)
    response = client.delete(f"/journal/{entry['id']}", headers=alice.headers)
    assert response.status_code == 204
    assert response.content == b""
    assert client.get(f"/journal/{entry['id']}", headers=alice.headers).status_code == 404
    assert db.get(JournalEntry, uuid.UUID(entry["id"])) is None


def test_delete_unknown_entry_is_404(client, alice):
    assert client.delete(f"/journal/{uuid.uuid4()}", headers=alice.headers).status_code == 404


# --- other users and signed-out requests -------------------------------------------------


def test_another_users_entry_is_404_everywhere(client, alice, bob):
    entry = write(client, bob)
    path = f"/journal/{entry['id']}"
    assert client.get(path, headers=alice.headers).status_code == 404
    assert client.patch(path, json={"lucid": "no"}, headers=alice.headers).status_code == 404
    assert client.delete(path, headers=alice.headers).status_code == 404
    assert client.get("/journal", headers=alice.headers).json() == {"items": [], "total": 0}
    assert client.get(path, headers=bob.headers).json() == entry


@pytest.mark.parametrize(
    ("method", "path"),
    [
        ("get", "/journal"),
        ("post", "/journal"),
        ("get", f"/journal/{uuid.uuid4()}"),
        ("patch", f"/journal/{uuid.uuid4()}"),
        ("delete", f"/journal/{uuid.uuid4()}"),
    ],
)
def test_signed_out_is_401(client, method, path):
    kwargs = {"json": ENTRY} if method in ("post", "patch") else {}
    response = client.request(method.upper(), path, **kwargs)
    assert response.status_code == 401
    assert response.headers["WWW-Authenticate"] == "Bearer"


def test_bad_token_is_401(client):
    response = client.get("/journal", headers={"Authorization": "Bearer not-a-token"})
    assert response.status_code == 401


# --- night deletion -----------------------------------------------------------------------


def test_deleting_a_night_keeps_its_entries_without_night(client, alice, db):
    night_id = make_night(db, alice.id)
    other_night = make_night(db, alice.id)
    about_night = write(client, alice, night_id=night_id, text="kept")
    about_other = write(client, alice, night_id=other_night, text="untouched")

    db.delete(db.get(Night, uuid.UUID(night_id)))
    db.commit()

    kept = client.get(f"/journal/{about_night['id']}", headers=alice.headers)
    assert kept.status_code == 200
    assert kept.json()["night_id"] is None
    assert kept.json()["text"] == "kept"
    assert client.get(f"/journal/{about_other['id']}", headers=alice.headers).json()["night_id"] == other_night
    assert client.get(f"/journal?night_id={night_id}", headers=alice.headers).status_code == 404


# --- text edge cases (must be 422 on SQLite and PostgreSQL alike) ----------------------------


def test_create_refuses_nul_characters(client, alice):
    response = client.post("/journal", json={**ENTRY, "text": "a" + chr(0) + "b"}, headers=alice.headers)
    assert response.status_code == 422
    assert "NUL" in response.text


def test_update_refuses_nul_characters(client, alice):
    entry = write(client, alice)
    response = client.patch(f"/journal/{entry['id']}", json={"text": chr(0)}, headers=alice.headers)
    assert response.status_code == 422


@pytest.mark.parametrize("written_at", ["0001-01-01T00:00:00+05:00", "9999-12-31T23:00:00-05:00"])
def test_written_at_out_of_range_is_422(client, alice, written_at):
    response = client.post("/journal", json={**ENTRY, "written_at": written_at}, headers=alice.headers)
    assert response.status_code == 422
