"""End-to-end checks across routers, using only the HTTP API: a whole night synced, then deleted."""

from pathlib import Path

from fastapi.testclient import TestClient

from app import storage
from conftest import RegisteredUser

NIGHT = {
    "client_id": "night-1",
    "started_at": "2026-11-01T23:00:00+01:00",
    "device_name": "Test headband",
    "channels": ["Fp1", "Fp2"],
    "sample_rate": 250.0,
}


def files_under(folder: Path) -> list[Path]:
    return sorted(path for path in folder.rglob("*") if path.is_file()) if folder.exists() else []


def sync_night(client: TestClient, user: RegisteredUser) -> str:
    """Create a night with epochs, an event, a recording and a journal entry. Returns the night id."""
    night = client.post("/nights", headers=user.headers, json=NIGHT)
    assert night.status_code == 201
    night_id = night.json()["id"]
    epochs = [
        {"index": i, "started_at": f"2026-11-01T22:{i // 2:02d}:{(i % 2) * 30:02d}Z", "stage": "n2",
         "contact": {"Fp1": 0.8, "Fp2": 0.6}}
        for i in range(4)
    ]
    assert client.put(f"/nights/{night_id}/epochs", headers=user.headers, json={"epochs": epochs}).json() == {
        "upserted": 4
    }
    event = {"client_id": "e1", "at": "2026-11-01T22:01:00Z", "type": "cue"}
    assert client.post(f"/nights/{night_id}/events", headers=user.headers, json={"events": [event]}).status_code == 200
    upload = client.post(
        f"/nights/{night_id}/recordings",
        headers=user.headers,
        data={"kind": "edf"},
        files={"file": ("night.edf", b"0       edf bytes", "application/octet-stream")},
    )
    assert upload.status_code == 201
    journal = client.post(
        "/journal", headers=user.headers, json={"night_id": night_id, "lucid": "maybe", "text": "A dream."}
    )
    assert journal.status_code == 201
    return night_id


def test_a_synced_night_shows_up_in_summary_and_export(client: TestClient, alice: RegisteredUser) -> None:
    night_id = sync_night(client, alice)

    summary = client.get(f"/nights/{night_id}/summary", headers=alice.headers).json()
    assert summary["epoch_count"] == 4
    assert summary["stage_minutes"] == {"n2": 2.0}
    assert summary["event_counts"] == {"cue": 1}
    assert summary["contact_average"] == {"Fp1": 0.8, "Fp2": 0.6}
    assert summary["recordings"] == 1

    export = client.get("/me/export", headers=alice.headers).json()
    assert [night["id"] for night in export["nights"]] == [night_id]
    assert len(export["nights"][0]["epochs"]) == 4
    assert len(export["recordings"]) == 1 and "storage_path" not in export["recordings"][0]
    assert export["journal_entries"][0]["night_id"] == night_id


def test_deleting_a_night_through_the_api_removes_files_and_unlinks_journal(
    client: TestClient, alice: RegisteredUser, bob: RegisteredUser, data_dir: Path
) -> None:
    night_id = sync_night(client, alice)
    bobs_night = sync_night(client, bob)
    assert files_under(storage.night_dir(data_dir, alice.id, night_id))

    assert client.delete(f"/nights/{night_id}", headers=alice.headers).status_code == 204

    assert not storage.night_dir(data_dir, alice.id, night_id).exists()
    assert files_under(storage.night_dir(data_dir, bob.id, bobs_night))
    assert client.get(f"/nights/{night_id}/recordings", headers=alice.headers).status_code == 404
    journal = client.get("/journal", headers=alice.headers).json()
    assert journal["total"] == 1 and journal["items"][0]["night_id"] is None


def test_deleting_an_account_through_the_api_removes_every_file(
    client: TestClient, alice: RegisteredUser, bob: RegisteredUser, data_dir: Path
) -> None:
    sync_night(client, alice)
    bobs_night = sync_night(client, bob)

    response = client.request("DELETE", "/me", headers=alice.headers, json={"password": alice.password})
    assert response.status_code == 204

    assert not storage.user_dir(data_dir, alice.id).exists()
    assert files_under(storage.night_dir(data_dir, bob.id, bobs_night))
    assert client.get("/me", headers=alice.headers).status_code == 401
    assert client.get("/nights", headers=bob.headers).json()["total"] == 1


def test_a_file_that_cannot_be_removed_does_not_fail_the_delete(
    client: TestClient, alice: RegisteredUser, data_dir: Path, monkeypatch
) -> None:
    """The rows are already committed when files are removed, so an OS error must not turn into a 500."""
    night_id = sync_night(client, alice)
    recording_id = client.get(f"/nights/{night_id}/recordings", headers=alice.headers).json()["items"][0]["id"]

    def locked(self: Path, missing_ok: bool = False) -> None:
        raise PermissionError("file is open")

    monkeypatch.setattr(Path, "unlink", locked)
    assert client.delete(f"/recordings/{recording_id}", headers=alice.headers).status_code == 204
    assert client.get(f"/nights/{night_id}/recordings", headers=alice.headers).json()["total"] == 0
