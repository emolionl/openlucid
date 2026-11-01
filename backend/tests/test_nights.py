"""Tests for /nights: nights, summary, epochs and events (incl. idempotency and other users' 404)."""

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import func, select

from app.models import Epoch, Event, Night, Recording

START = datetime(2026, 11, 1, 23, 0, tzinfo=timezone.utc)


def night_body(**extra) -> dict:
    body = {
        "started_at": START.isoformat(),
        "device_name": "OpenBCI Ganglion",
        "channels": ["Fp1", "Fp2"],
        "sample_rate": 200,
        "timezone": "Europe/Amsterdam",
    }
    body.update(extra)
    return body


def epoch(index: int, **extra) -> dict:
    body = {"index": index, "started_at": (START + timedelta(seconds=30 * index)).isoformat()}
    body.update(extra)
    return body


def event(minute: int, type: str = "cue", **extra) -> dict:
    body = {"at": (START + timedelta(minutes=minute)).isoformat(), "type": type}
    body.update(extra)
    return body


@pytest.fixture
def night(client, alice) -> dict:
    """A night of Alice's."""
    response = client.post("/nights", json=night_body(client_id="night-1"), headers=alice.headers)
    assert response.status_code == 201, response.text
    return response.json()


def url(night: dict, suffix: str = "") -> str:
    return f"/nights/{night['id']}{suffix}"


# --- authentication: every endpoint needs a signed-in user ---------------------------------


@pytest.mark.parametrize(
    ("method", "suffix"),
    [
        ("get", ""),
        ("get", "/summary"),
        ("patch", ""),
        ("delete", ""),
        ("put", "/epochs"),
        ("get", "/epochs"),
        ("post", "/events"),
        ("get", "/events"),
    ],
)
def test_night_endpoints_need_sign_in(client, night, method, suffix):
    response = client.request(method, url(night, suffix), json={})
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


@pytest.mark.parametrize("method", ["get", "post"])
def test_night_collection_needs_sign_in(client, method):
    response = client.request(method, "/nights", json=night_body())
    assert response.status_code == 401


def test_broken_token_is_401(client, night):
    response = client.get(url(night), headers={"Authorization": "Bearer not-a-token"})
    assert response.status_code == 401


# --- another user's night: always 404 ------------------------------------------------------


@pytest.mark.parametrize(
    ("method", "suffix", "body"),
    [
        ("get", "", None),
        ("get", "/summary", None),
        ("patch", "", {"notes": "mine now"}),
        ("delete", "", None),
        ("put", "/epochs", {"epochs": [epoch(0)]}),
        ("get", "/epochs", None),
        ("post", "/events", {"events": [event(1)]}),
        ("get", "/events", None),
    ],
)
def test_other_users_night_is_404(client, night, bob, db, method, suffix, body):
    response = client.request(method, url(night, suffix), json=body, headers=bob.headers)
    assert response.status_code == 404
    assert response.json() == {"detail": "Night not found."}
    # Nothing was changed or deleted.
    stored = db.get(Night, uuid.UUID(night["id"]))
    assert stored is not None and stored.notes is None
    assert db.scalar(select(func.count()).select_from(Epoch)) == 0
    assert db.scalar(select(func.count()).select_from(Event)) == 0


@pytest.mark.parametrize("suffix", ["", "/summary", "/epochs", "/events"])
def test_unknown_night_is_404(client, alice, suffix):
    response = client.get(f"/nights/{uuid.uuid4()}{suffix}", headers=alice.headers)
    assert response.status_code == 404


def test_invalid_night_id_is_422(client, alice):
    assert client.get("/nights/not-a-uuid", headers=alice.headers).status_code == 422


def test_other_users_nights_are_not_listed(client, night, bob):
    response = client.get("/nights", headers=bob.headers)
    assert response.status_code == 200
    assert response.json() == {"items": [], "total": 0}


def test_same_client_id_for_two_users_makes_two_nights(client, night, bob):
    response = client.post("/nights", json=night_body(client_id="night-1"), headers=bob.headers)
    assert response.status_code == 201
    assert response.json()["id"] != night["id"]


# --- create, list, get ---------------------------------------------------------------------


def test_create_night_returns_it(client, alice):
    response = client.post(
        "/nights",
        json=night_body(started_at="2026-11-02T00:30:00+01:00", device_firmware="1.2", notes="First try"),
        headers=alice.headers,
    )
    assert response.status_code == 201
    body = response.json()
    assert datetime.fromisoformat(body["started_at"]) == START + timedelta(minutes=30)
    assert datetime.fromisoformat(body["started_at"]).utcoffset() == timedelta(0)
    assert body["ended_at"] is None
    assert body["client_id"] is None
    assert body["device_name"] == "OpenBCI Ganglion"
    assert body["device_firmware"] == "1.2"
    assert body["channels"] == ["Fp1", "Fp2"]
    assert body["sample_rate"] == 200
    assert body["timezone"] == "Europe/Amsterdam"
    assert body["notes"] == "First try"
    assert "user_id" not in body


def test_create_night_twice_with_client_id_returns_the_first(client, alice, night):
    again = client.post(
        "/nights", json=night_body(client_id="night-1", device_name="Something else"), headers=alice.headers
    )
    assert again.status_code == 200
    assert again.json() == night
    assert client.get("/nights", headers=alice.headers).json()["total"] == 1


def test_create_night_without_client_id_is_not_deduplicated(client, alice):
    for _ in range(2):
        assert client.post("/nights", json=night_body(), headers=alice.headers).status_code == 201
    assert client.get("/nights", headers=alice.headers).json()["total"] == 2


@pytest.mark.parametrize(
    "changes",
    [
        {"started_at": "2026-11-01T23:00:00"},  # no time zone
        {"started_at": "yesterday"},
        {"device_name": ""},
        {"device_name": "x" * 101},
        {"channels": []},
        {"channels": [""]},
        {"sample_rate": 0},
        {"sample_rate": -5},
        {"timezone": "Mars/Olympus_Mons"},
        {"notes": "x" * 5001},
        {"client_id": ""},
        {"client_id": "x" * 65},
    ],
)
def test_create_night_validation(client, alice, changes):
    response = client.post("/nights", json=night_body(**changes), headers=alice.headers)
    assert response.status_code == 422


@pytest.mark.parametrize("missing", ["started_at", "device_name", "channels", "sample_rate"])
def test_create_night_requires_fields(client, alice, missing):
    body = night_body()
    del body[missing]
    assert client.post("/nights", json=body, headers=alice.headers).status_code == 422


def test_list_nights_newest_first_with_pagination(client, alice):
    ids = []
    for day in range(3):
        started = (START + timedelta(days=day)).isoformat()
        ids.append(client.post("/nights", json=night_body(started_at=started), headers=alice.headers).json()["id"])

    response = client.get("/nights", headers=alice.headers)
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 3
    assert [item["id"] for item in body["items"]] == list(reversed(ids))

    page = client.get("/nights?limit=1&offset=1", headers=alice.headers).json()
    assert page["total"] == 3
    assert [item["id"] for item in page["items"]] == [ids[1]]


@pytest.mark.parametrize("query", ["limit=0", "limit=201", "offset=-1"])
def test_list_nights_pagination_validation(client, alice, query):
    assert client.get(f"/nights?{query}", headers=alice.headers).status_code == 422


def test_get_night(client, alice, night):
    response = client.get(url(night), headers=alice.headers)
    assert response.status_code == 200
    assert response.json() == night


# --- patch ---------------------------------------------------------------------------------


def test_patch_night_changes_only_sent_fields(client, alice, night):
    ended = (START + timedelta(hours=7)).isoformat()
    response = client.patch(url(night), json={"ended_at": ended, "notes": "Woke up twice"}, headers=alice.headers)
    assert response.status_code == 200
    body = response.json()
    assert datetime.fromisoformat(body["ended_at"]) == START + timedelta(hours=7)
    assert body["notes"] == "Woke up twice"
    assert body["device_name"] == night["device_name"]

    response = client.patch(url(night), json={"device_firmware": "2.0"}, headers=alice.headers)
    body = response.json()
    assert body["device_firmware"] == "2.0"
    assert body["notes"] == "Woke up twice"


def test_patch_night_can_clear_notes(client, alice, night):
    client.patch(url(night), json={"notes": "temporary"}, headers=alice.headers)
    response = client.patch(url(night), json={"notes": None}, headers=alice.headers)
    assert response.status_code == 200
    assert response.json()["notes"] is None


def test_patch_night_ignores_fields_that_cannot_change(client, alice, night):
    response = client.patch(url(night), json={"device_name": "Other", "client_id": "x"}, headers=alice.headers)
    assert response.status_code == 200
    assert response.json()["device_name"] == night["device_name"]
    assert response.json()["client_id"] == "night-1"


@pytest.mark.parametrize(
    "body",
    [
        {"ended_at": "2026-11-02T07:00:00"},  # no time zone
        {"ended_at": (START - timedelta(minutes=1)).isoformat()},  # before the start
        {"notes": "x" * 5001},
        {"device_firmware": "x" * 101},
    ],
)
def test_patch_night_validation(client, alice, night, body):
    response = client.patch(url(night), json=body, headers=alice.headers)
    assert response.status_code == 422


# --- delete --------------------------------------------------------------------------------


def test_delete_night_removes_everything_including_files(client, alice, night, db, data_dir):
    client.put(url(night, "/epochs"), json={"epochs": [epoch(0), epoch(1)]}, headers=alice.headers)
    client.post(url(night, "/events"), json={"events": [event(1)]}, headers=alice.headers)

    # A recording as the recordings router would store it: a row plus a file in the night's folder.
    night_dir = data_dir / "recordings" / alice.id / night["id"]
    night_dir.mkdir(parents=True)
    recording_id = uuid.uuid4()
    recording_file = night_dir / f"{recording_id}.edf"
    recording_file.write_bytes(b"0       fake edf")
    db.add(
        Recording(
            id=recording_id,
            night_id=uuid.UUID(night["id"]),
            kind="edf",
            original_filename="night.edf",
            size_bytes=16,
            sha256="0" * 64,
            storage_path=recording_file.relative_to(data_dir).as_posix(),
        )
    )
    db.commit()

    # Another night of Alice's keeps its files.
    other = client.post("/nights", json=night_body(), headers=alice.headers).json()
    other_dir = data_dir / "recordings" / alice.id / other["id"]
    other_dir.mkdir(parents=True)
    (other_dir / "keep.edf").write_bytes(b"keep")

    response = client.delete(url(night), headers=alice.headers)
    assert response.status_code == 204
    assert response.content == b""

    assert client.get(url(night), headers=alice.headers).status_code == 404
    db.expire_all()
    night_id = uuid.UUID(night["id"])
    assert db.get(Night, night_id) is None
    assert db.scalar(select(func.count()).select_from(Epoch).where(Epoch.night_id == night_id)) == 0
    assert db.scalar(select(func.count()).select_from(Event).where(Event.night_id == night_id)) == 0
    assert db.scalar(select(func.count()).select_from(Recording)) == 0
    assert not recording_file.exists()
    assert not night_dir.exists()
    assert (other_dir / "keep.edf").exists()


def test_delete_night_without_files(client, alice, night):
    assert client.delete(url(night), headers=alice.headers).status_code == 204
    assert client.delete(url(night), headers=alice.headers).status_code == 404


def test_delete_night_ignores_storage_paths_outside_data_dir(client, alice, night, db, tmp_path):
    outside = tmp_path / "outside.txt"
    outside.write_text("do not delete")
    db.add(
        Recording(
            night_id=uuid.UUID(night["id"]),
            kind="other",
            original_filename="x",
            size_bytes=1,
            sha256="0" * 64,
            storage_path="../outside.txt",
        )
    )
    db.commit()
    assert client.delete(url(night), headers=alice.headers).status_code == 204
    assert outside.exists()


def test_deleted_client_id_can_be_used_again(client, alice, night):
    client.delete(url(night), headers=alice.headers)
    again = client.post("/nights", json=night_body(client_id="night-1"), headers=alice.headers)
    assert again.status_code == 201
    assert again.json()["id"] != night["id"]


# --- epochs --------------------------------------------------------------------------------


def test_put_epochs_inserts_and_lists_them_in_order(client, alice, night):
    epochs = [
        epoch(2, stage="rem", stage_confidence=0.8, contact={"Fp1": 0.9, "Fp2": 0.7}, quality="good"),
        epoch(0, stage="wake"),
        epoch(1),
    ]
    response = client.put(url(night, "/epochs"), json={"epochs": epochs}, headers=alice.headers)
    assert response.status_code == 200
    assert response.json() == {"upserted": 3}

    listed = client.get(url(night, "/epochs"), headers=alice.headers).json()
    assert listed["total"] == 3
    assert [item["index"] for item in listed["items"]] == [0, 1, 2]
    last = listed["items"][2]
    assert last["stage"] == "rem"
    assert last["stage_confidence"] == 0.8
    assert last["contact"] == {"Fp1": 0.9, "Fp2": 0.7}
    assert last["quality"] == "good"
    assert datetime.fromisoformat(last["started_at"]) == START + timedelta(seconds=60)
    assert listed["items"][1]["stage"] is None


def test_put_epochs_again_updates_existing_indexes(client, alice, night, db):
    first = {"epochs": [epoch(0, stage="wake"), epoch(1, stage="n1")]}
    client.put(url(night, "/epochs"), json=first, headers=alice.headers)
    first_items = client.get(url(night, "/epochs"), headers=alice.headers).json()["items"]
    first_ids = {item["index"]: item["id"] for item in first_items}

    response = client.put(
        url(night, "/epochs"), json={"epochs": [epoch(1, stage="n2", quality="okay"), epoch(2)]}, headers=alice.headers
    )
    assert response.json() == {"upserted": 2}

    items = client.get(url(night, "/epochs"), headers=alice.headers).json()["items"]
    assert [(item["index"], item["stage"]) for item in items] == [(0, "wake"), (1, "n2"), (2, None)]
    assert items[1]["id"] == first_ids[1]  # updated in place, not replaced
    assert items[1]["quality"] == "okay"
    assert db.scalar(select(func.count()).select_from(Epoch)) == 3


def test_put_same_epochs_twice_is_harmless(client, alice, night):
    body = {"epochs": [epoch(i, stage="n2") for i in range(5)]}
    for _ in range(2):
        assert client.put(url(night, "/epochs"), json=body, headers=alice.headers).json() == {"upserted": 5}
    assert client.get(url(night, "/epochs"), headers=alice.headers).json()["total"] == 5


def test_put_epochs_with_repeated_index_keeps_the_last(client, alice, night):
    body = {"epochs": [epoch(0, stage="wake"), epoch(0, stage="rem")]}
    assert client.put(url(night, "/epochs"), json=body, headers=alice.headers).json() == {"upserted": 1}
    items = client.get(url(night, "/epochs"), headers=alice.headers).json()["items"]
    assert [(item["index"], item["stage"]) for item in items] == [(0, "rem")]


def test_put_1000_epochs_is_allowed_1001_is_not(client, alice, night):
    body = {"epochs": [epoch(i) for i in range(1000)]}
    assert client.put(url(night, "/epochs"), json=body, headers=alice.headers).json() == {"upserted": 1000}
    body["epochs"].append(epoch(1000))
    assert client.put(url(night, "/epochs"), json=body, headers=alice.headers).status_code == 422


@pytest.mark.parametrize(
    "bad_epoch",
    [
        epoch(-1),
        {"index": 0},  # no started_at
        epoch(0, started_at="2026-11-01T23:00:00"),  # no time zone
        epoch(0, stage="deep"),
        epoch(0, stage_confidence=1.5),
        epoch(0, stage_confidence=-0.1),
        epoch(0, contact={"Fp1": 2}),
        epoch(0, contact={"": 0.5}),
        epoch(0, quality="great"),
    ],
)
def test_put_epochs_validation(client, alice, night, bad_epoch):
    response = client.put(url(night, "/epochs"), json={"epochs": [bad_epoch]}, headers=alice.headers)
    assert response.status_code == 422


def test_put_epochs_needs_at_least_one(client, alice, night):
    assert client.put(url(night, "/epochs"), json={"epochs": []}, headers=alice.headers).status_code == 422


def test_get_epochs_index_range_and_pagination(client, alice, night):
    client.put(url(night, "/epochs"), json={"epochs": [epoch(i) for i in range(10)]}, headers=alice.headers)

    ranged = client.get(url(night, "/epochs?from_index=3&to_index=6"), headers=alice.headers).json()
    assert ranged["total"] == 4
    assert [item["index"] for item in ranged["items"]] == [3, 4, 5, 6]

    only_from = client.get(url(night, "/epochs?from_index=8"), headers=alice.headers).json()
    assert [item["index"] for item in only_from["items"]] == [8, 9]

    page = client.get(url(night, "/epochs?from_index=2&limit=3&offset=1"), headers=alice.headers).json()
    assert page["total"] == 8
    assert [item["index"] for item in page["items"]] == [3, 4, 5]

    empty = client.get(url(night, "/epochs?from_index=7&to_index=2"), headers=alice.headers).json()
    assert empty == {"items": [], "total": 0}


def test_get_epochs_allows_a_limit_of_2000(client, alice, night):
    assert client.get(url(night, "/epochs?limit=2000"), headers=alice.headers).status_code == 200


@pytest.mark.parametrize("query", ["limit=2001", "limit=0", "from_index=-1", "to_index=-1", "from_index=abc"])
def test_get_epochs_validation(client, alice, night, query):
    assert client.get(url(night, f"/epochs?{query}"), headers=alice.headers).status_code == 422


def test_epochs_belong_to_their_night(client, alice, night):
    other = client.post("/nights", json=night_body(), headers=alice.headers).json()
    client.put(url(night, "/epochs"), json={"epochs": [epoch(0, stage="wake")]}, headers=alice.headers)
    client.put(url(other, "/epochs"), json={"epochs": [epoch(0, stage="rem")]}, headers=alice.headers)
    assert client.get(url(night, "/epochs"), headers=alice.headers).json()["items"][0]["stage"] == "wake"
    assert client.get(url(other, "/epochs"), headers=alice.headers).json()["items"][0]["stage"] == "rem"


# --- events --------------------------------------------------------------------------------


def test_post_events_and_list_them_by_time(client, alice, night):
    events = [
        event(30, "lrlr", client_id="e-2", details={"strength": 0.7}),
        event(10, "cue", client_id="e-1"),
        event(20, "note", details={"text": "heard the cue"}),
    ]
    response = client.post(url(night, "/events"), json={"events": events}, headers=alice.headers)
    assert response.status_code == 200
    assert response.json() == {"created": 3, "existing": 0}

    listed = client.get(url(night, "/events"), headers=alice.headers).json()
    assert listed["total"] == 3
    assert [item["type"] for item in listed["items"]] == ["cue", "note", "lrlr"]
    lrlr = listed["items"][2]
    assert lrlr["client_id"] == "e-2"
    assert lrlr["details"] == {"strength": 0.7}
    assert datetime.fromisoformat(lrlr["at"]) == START + timedelta(minutes=30)


def test_post_events_twice_is_idempotent_by_client_id(client, alice, night, db):
    body = {"events": [event(1, client_id="a"), event(2, client_id="b")]}
    assert client.post(url(night, "/events"), json=body, headers=alice.headers).json() == {"created": 2, "existing": 0}

    body["events"].append(event(3, client_id="c"))
    again = client.post(url(night, "/events"), json=body, headers=alice.headers)
    assert again.json() == {"created": 1, "existing": 2}
    assert db.scalar(select(func.count()).select_from(Event)) == 3


def test_events_without_client_id_are_always_created(client, alice, night):
    body = {"events": [event(1)]}
    for _ in range(2):
        assert client.post(url(night, "/events"), json=body, headers=alice.headers).json() == {
            "created": 1,
            "existing": 0,
        }
    assert client.get(url(night, "/events"), headers=alice.headers).json()["total"] == 2


def test_repeated_client_id_in_one_batch_is_stored_once(client, alice, night):
    body = {"events": [event(1, client_id="same"), event(2, client_id="same")]}
    assert client.post(url(night, "/events"), json=body, headers=alice.headers).json() == {"created": 1, "existing": 1}


def test_same_event_client_id_in_two_nights(client, alice, night):
    other = client.post("/nights", json=night_body(), headers=alice.headers).json()
    body = {"events": [event(1, client_id="x")]}
    assert client.post(url(night, "/events"), json=body, headers=alice.headers).json()["created"] == 1
    assert client.post(url(other, "/events"), json=body, headers=alice.headers).json()["created"] == 1


def test_get_events_filter_by_type_and_paginate(client, alice, night):
    events = [event(minute, "cue" if minute % 2 else "lrlr") for minute in range(6)]
    client.post(url(night, "/events"), json={"events": events}, headers=alice.headers)

    cues = client.get(url(night, "/events?type=cue"), headers=alice.headers).json()
    assert cues["total"] == 3
    assert {item["type"] for item in cues["items"]} == {"cue"}

    page = client.get(url(night, "/events?limit=2&offset=2"), headers=alice.headers).json()
    assert page["total"] == 6
    assert [datetime.fromisoformat(item["at"]) for item in page["items"]] == [
        START + timedelta(minutes=2),
        START + timedelta(minutes=3),
    ]

    assert client.get(url(night, "/events?type=nothing"), headers=alice.headers).json() == {"items": [], "total": 0}


def test_post_500_events_is_allowed_501_is_not(client, alice, night):
    body = {"events": [event(0, client_id=str(i)) for i in range(500)]}
    assert client.post(url(night, "/events"), json=body, headers=alice.headers).json() == {
        "created": 500,
        "existing": 0,
    }
    body["events"].append(event(0))
    assert client.post(url(night, "/events"), json=body, headers=alice.headers).status_code == 422


def test_event_details_up_to_10_kb(client, alice, night):
    fits = {"text": "x" * (10 * 1024 - 20)}
    too_big = {"text": "x" * (10 * 1024)}
    ok = client.post(url(night, "/events"), json={"events": [event(1, details=fits)]}, headers=alice.headers)
    assert ok.status_code == 200
    too = client.post(url(night, "/events"), json={"events": [event(1, details=too_big)]}, headers=alice.headers)
    assert too.status_code == 422


@pytest.mark.parametrize(
    "bad_event",
    [
        {"type": "cue"},  # no time
        event(1, at="2026-11-01T23:00:00"),  # no time zone
        event(1, type=""),
        event(1, type="x" * 41),
        event(1, client_id=""),
        event(1, client_id="x" * 65),
        event(1, details=["not", "an", "object"]),
    ],
)
def test_post_events_validation(client, alice, night, bad_event):
    response = client.post(url(night, "/events"), json={"events": [bad_event]}, headers=alice.headers)
    assert response.status_code == 422


def test_post_events_needs_at_least_one(client, alice, night):
    assert client.post(url(night, "/events"), json={"events": []}, headers=alice.headers).status_code == 422


def test_a_bad_event_stores_nothing_of_the_batch(client, alice, night):
    body = {"events": [event(1, client_id="ok"), event(2, type="")]}
    assert client.post(url(night, "/events"), json=body, headers=alice.headers).status_code == 422
    assert client.get(url(night, "/events"), headers=alice.headers).json()["total"] == 0


@pytest.mark.parametrize("query", ["limit=201", "type=" + "x" * 41])
def test_get_events_validation(client, alice, night, query):
    assert client.get(url(night, f"/events?{query}"), headers=alice.headers).status_code == 422


# --- summary -------------------------------------------------------------------------------


def test_summary_of_an_empty_night(client, alice, night):
    response = client.get(url(night, "/summary"), headers=alice.headers)
    assert response.status_code == 200
    assert response.json() == {
        "night": night,
        "epoch_count": 0,
        "stage_minutes": {},
        "event_counts": {},
        "contact_average": {},
        "recordings": 0,
    }


def test_summary_adds_up_the_night(client, alice, night, db):
    epochs = [
        epoch(0, stage="wake", contact={"Fp1": 1.0, "Fp2": 0.5}),
        epoch(1, stage="n2", contact={"Fp1": 0.5}),
        epoch(2, stage="n2"),
        epoch(3, stage="rem", contact={"Fp1": 0.0, "Fp2": 0.25}),
        epoch(4),  # not staged yet
    ]
    client.put(url(night, "/epochs"), json={"epochs": epochs}, headers=alice.headers)
    events = [event(1, "cue"), event(2, "cue"), event(3, "lrlr")]
    client.post(url(night, "/events"), json={"events": events}, headers=alice.headers)
    db.add(
        Recording(
            night_id=uuid.UUID(night["id"]),
            kind="edf",
            original_filename="night.edf",
            size_bytes=1,
            sha256="0" * 64,
            storage_path=f"recordings/{alice.id}/{night['id']}/x.edf",
        )
    )
    db.commit()

    summary = client.get(url(night, "/summary"), headers=alice.headers).json()
    assert summary["night"]["id"] == night["id"]
    assert summary["epoch_count"] == 5
    assert summary["stage_minutes"] == {"wake": 0.5, "n2": 1.0, "rem": 0.5}
    assert summary["event_counts"] == {"cue": 2, "lrlr": 1}
    assert summary["contact_average"] == pytest.approx({"Fp1": 0.5, "Fp2": 0.375})
    assert summary["recordings"] == 1


# --- text and number edge cases (must be 422 on SQLite and PostgreSQL alike) -------------------

NUL = chr(0)  # PostgreSQL cannot store this character in text


@pytest.mark.parametrize(
    "changes",
    [
        {"notes": f"x{NUL}"},
        {"device_name": f"Head{NUL}band"},
        {"device_firmware": NUL},
        {"client_id": f"night{NUL}"},
        {"channels": ["Fp1", f"Fp{NUL}2"]},
        {"timezone": f"Europe/Amsterdam{NUL}"},
    ],
)
def test_create_night_refuses_nul_characters(client, alice, changes, db):
    response = client.post("/nights", json=night_body(**changes), headers=alice.headers)
    assert response.status_code == 422
    assert "NUL" in response.text
    assert db.scalar(select(func.count()).select_from(Night)) == 0


def test_patch_night_refuses_nul_characters(client, alice, night):
    assert client.patch(url(night), json={"notes": f"a{NUL}b"}, headers=alice.headers).status_code == 422


@pytest.mark.parametrize(
    "bad_event",
    [
        event(1, type=f"cue{NUL}"),
        event(1, client_id=f"ev{NUL}"),
        event(1, details={"text": f"a{NUL}b"}),
        event(1, details={f"key{NUL}": 1}),
        event(1, details={"deep": [{"deeper": [f"{NUL}"]}]}),
    ],
)
def test_post_events_refuses_nul_characters(client, alice, night, bad_event):
    response = client.post(url(night, "/events"), json={"events": [bad_event]}, headers=alice.headers)
    assert response.status_code == 422


def test_put_epochs_refuses_nul_in_contact_channel(client, alice, night):
    body = {"epochs": [epoch(0, contact={f"Fp{NUL}1": 0.5})]}
    assert client.put(url(night, "/epochs"), json=body, headers=alice.headers).status_code == 422


def test_get_events_refuses_nul_in_type_filter(client, alice, night):
    assert client.get(url(night, "/events?type=cue%00"), headers=alice.headers).status_code == 422


@pytest.mark.parametrize("token", ["NaN", "Infinity", "-Infinity"])
def test_event_details_refuse_nan_and_infinity(client, alice, night, db, token):
    raw = '{"events": [{"at": "2026-11-01T23:00:00Z", "type": "note", "details": {"x": %s}}]}' % token
    response = client.post(
        url(night, "/events"), content=raw, headers={**alice.headers, "Content-Type": "application/json"}
    )
    assert response.status_code == 422
    assert "NaN" in response.text
    assert db.scalar(select(func.count()).select_from(Event)) == 0


@pytest.mark.parametrize(
    "timestamp",
    [
        "0001-01-01T00:00:00+05:00",  # converting this to UTC overflows
        "9999-12-31T23:00:00-05:00",  # and this one too
        "1899-12-31T23:59:59Z",
        "2200-01-01T00:00:00Z",
    ],
)
def test_timestamps_out_of_range_are_422(client, alice, night, timestamp):
    assert client.post("/nights", json=night_body(started_at=timestamp), headers=alice.headers).status_code == 422
    assert client.patch(url(night), json={"ended_at": timestamp}, headers=alice.headers).status_code == 422
    body = {"epochs": [epoch(0, started_at=timestamp)]}
    assert client.put(url(night, "/epochs"), json=body, headers=alice.headers).status_code == 422
    body = {"events": [event(0) | {"at": timestamp}]}
    assert client.post(url(night, "/events"), json=body, headers=alice.headers).status_code == 422


@pytest.mark.parametrize("timestamp", ["1900-01-01T00:00:00Z", "2199-12-31T23:59:59+00:00"])
def test_timestamps_at_the_edges_of_the_range_are_fine(client, alice, timestamp):
    response = client.post("/nights", json=night_body(started_at=timestamp), headers=alice.headers)
    assert response.status_code == 201, response.text


def test_nan_in_a_number_field_is_a_clean_422(client, alice):
    raw = '{"started_at": "2026-11-01T23:00:00Z", "device_name": "x", "channels": ["Fp1"], "sample_rate": NaN}'
    response = client.post("/nights", content=raw, headers={**alice.headers, "Content-Type": "application/json"})
    assert response.status_code == 422
    assert response.json()["detail"][0]["loc"] == ["body", "sample_rate"]
