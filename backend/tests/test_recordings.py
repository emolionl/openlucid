"""Recordings: upload (streamed, size-limited, sanitized), list, download and delete, plus the storage helpers."""

import hashlib
import os
import uuid
from datetime import datetime, timezone
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app import storage
from app.models import Night

EDF_BYTES = b"0       " + bytes(range(256)) * 40  # looks a bit like an EDF header, content does not matter
MB = 1024 * 1024


def make_night(db: Session, user_id: str) -> str:
    """Create a night straight in the database (the nights endpoints are tested elsewhere)."""
    night = Night(
        user_id=uuid.UUID(user_id),
        started_at=datetime(2026, 11, 1, 23, 0, tzinfo=timezone.utc),
        device_name="Test headband",
        channels=["Fp1", "Fp2"],
        sample_rate=250.0,
    )
    db.add(night)
    db.commit()
    return str(night.id)


def upload(client: TestClient, headers: dict, night_id: str, content: bytes = EDF_BYTES,
           filename: str = "night.edf", kind: str | None = "edf"):
    data = {"kind": kind} if kind is not None else {}
    return client.post(
        f"/nights/{night_id}/recordings",
        headers=headers,
        files={"file": (filename, content, "application/octet-stream")},
        data=data,
    )


def files_under(folder: Path) -> list[Path]:
    return sorted(path for path in folder.rglob("*") if path.is_file()) if folder.exists() else []


def recording_files(data_dir: Path) -> list[Path]:
    return files_under(storage.recordings_root(data_dir))


@pytest.fixture
def night_id(db: Session, alice) -> str:
    return make_night(db, alice.id)


# --- upload -------------------------------------------------------------------------------


def test_upload_stores_file_and_metadata(client, alice, night_id, data_dir):
    response = upload(client, alice.headers, night_id)
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["night_id"] == night_id
    assert body["kind"] == "edf"
    assert body["original_filename"] == "night.edf"
    assert body["size_bytes"] == len(EDF_BYTES)
    assert body["sha256"] == hashlib.sha256(EDF_BYTES).hexdigest()
    assert "storage_path" not in body

    expected = storage.night_dir(data_dir, alice.id, night_id) / f"{body['id']}.edf"
    assert recording_files(data_dir) == [expected]
    assert expected.read_bytes() == EDF_BYTES


def test_upload_kind_may_come_before_the_file(client, alice, night_id):
    """The order of the multipart parts must not matter (kind is read before or after the file)."""
    boundary = "testboundary"
    body = (
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"kind\"\r\n\r\nraw_csv\r\n"
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"raw.csv\"\r\n"
        f"Content-Type: text/csv\r\n\r\nt,fp1\n0,1\n\r\n--{boundary}--\r\n"
    ).encode()
    response = client.post(
        f"/nights/{night_id}/recordings",
        headers={**alice.headers, "Content-Type": f"multipart/form-data; boundary={boundary}"},
        content=body,
    )
    assert response.status_code == 201, response.text
    assert response.json()["kind"] == "raw_csv"
    assert response.json()["size_bytes"] == len(b"t,fp1\n0,1\n")


def test_upload_uses_kind_extension_when_filename_has_none(client, alice, night_id, data_dir):
    response = upload(client, alice.headers, night_id, filename="recording-without-extension", kind="raw_csv")
    assert response.status_code == 201
    assert recording_files(data_dir)[0].name == f"{response.json()['id']}.csv"


def test_upload_streamed_in_chunks_without_content_length(client, alice, night_id):
    """A chunked body (no Content-Length) is accepted and hashed correctly."""
    boundary = "chunkboundary"
    payload = b"x" * (3 * 65536 + 17)
    parts = [
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"big.edf\"\r\n\r\n".encode(),
        payload[:100000],
        payload[100000:],
        f"\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"kind\"\r\n\r\nedf\r\n--{boundary}--\r\n".encode(),
    ]
    response = client.post(
        f"/nights/{night_id}/recordings",
        headers={**alice.headers, "Content-Type": f"multipart/form-data; boundary={boundary}"},
        content=iter(parts),
    )
    assert response.status_code == 201, response.text
    assert response.json()["sha256"] == hashlib.sha256(payload).hexdigest()


# --- size limit ---------------------------------------------------------------------------


def test_upload_exactly_at_limit_is_accepted(make_client, alice, night_id):
    small_client = make_client(max_upload_mb=1)
    response = upload(small_client, alice.headers, night_id, content=b"a" * MB)
    assert response.status_code == 201, response.text
    assert response.json()["size_bytes"] == MB


@pytest.mark.parametrize("size", [MB + 1, 3 * MB], ids=["one-byte-too-many", "declared-length-too-big"])
def test_oversize_upload_is_413_and_leaves_no_file(make_client, alice, night_id, data_dir, db, size):
    small_client = make_client(max_upload_mb=1)
    response = upload(small_client, alice.headers, night_id, content=b"a" * size)
    assert response.status_code == 413
    assert "1 MB" in response.json()["detail"]
    assert recording_files(data_dir) == []
    listed = small_client.get(f"/nights/{night_id}/recordings", headers=alice.headers).json()
    assert listed["total"] == 0


def test_oversize_chunked_upload_is_413_and_leaves_no_file(make_client, alice, night_id, data_dir):
    """Without Content-Length the limit is enforced while streaming, and the part file is removed."""
    small_client = make_client(max_upload_mb=1)
    boundary = "b0undary"

    def body():
        yield f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"x.edf\"\r\n\r\n".encode()
        for _ in range(20):
            yield b"z" * 65536  # 1.25 MB in total
        yield f"\r\n--{boundary}--\r\n".encode()

    response = small_client.post(
        f"/nights/{night_id}/recordings",
        headers={**alice.headers, "Content-Type": f"multipart/form-data; boundary={boundary}"},
        content=body(),
    )
    assert response.status_code == 413
    assert recording_files(data_dir) == []


# --- filenames and path traversal ---------------------------------------------------------


@pytest.mark.parametrize(
    ("filename", "expected"),
    [
        ("../../evil.edf", "evil.edf"),
        ("..\\..\\..\\Windows\\evil.edf", "evil.edf"),
        ("/etc/passwd", "passwd"),
        ("C:\\Users\\me\\night.edf", "night.edf"),
        ("..", "recording"),
        ("....", "recording"),
        ("", "recording"),
        ("night\x00\x1f.edf", "night.edf"),
        ("a<b>c|d?e*f\":.edf", "a_b_c_d_e_f__.edf"),
        ("  .hidden.edf  ", "hidden.edf"),
        ("droom ñacht 夜.edf", "droom ñacht 夜.edf"),
    ],
)
def test_sanitize_filename(filename, expected):
    assert storage.sanitize_filename(filename) == expected


def test_sanitize_filename_keeps_extension_when_shortening():
    name = storage.sanitize_filename("n" * 500 + ".edf")
    assert len(name) == storage.MAX_FILENAME_LENGTH
    assert name.endswith(".edf")
    assert len(storage.sanitize_filename("n" * 500)) == storage.MAX_FILENAME_LENGTH


@pytest.mark.parametrize(
    "filename",
    ["../../../escape.edf", "..\\..\\escape.edf", "/tmp/escape.edf", "x/../../../secret_key", "evil.e/../../x"],
)
def test_path_traversal_filenames_stay_in_the_night_folder(client, alice, night_id, data_dir, filename):
    response = upload(client, alice.headers, night_id, filename=filename)
    assert response.status_code == 201, response.text
    body = response.json()
    assert "/" not in body["original_filename"] and "\\" not in body["original_filename"]
    assert not body["original_filename"].startswith(".")

    stored = recording_files(data_dir)
    assert len(stored) == 1
    assert stored[0].parent == storage.night_dir(data_dir, alice.id, night_id)
    assert stored[0].stem == body["id"]
    # nothing else appeared anywhere in DATA_DIR (only the recording and the generated secret key)
    everything = {path.relative_to(data_dir).as_posix() for path in files_under(data_dir)}
    assert everything <= {stored[0].relative_to(data_dir).as_posix(), "secret_key", "openlucid.db"}


def test_download_header_uses_sanitized_name(client, alice, night_id):
    recording = upload(client, alice.headers, night_id, filename="../../my;night.edf").json()
    response = client.get(f"/recordings/{recording['id']}/download", headers=alice.headers)
    assert response.status_code == 200
    assert recording["original_filename"] == "my_night.edf"
    assert 'filename="my_night.edf"' in response.headers["content-disposition"]


@pytest.mark.parametrize("storage_path", ["../secret_key", "recordings/../secret_key", "recordings", "/etc/passwd"])
def test_resolve_storage_path_refuses_paths_outside_recordings(data_dir, storage_path):
    with pytest.raises(ValueError):
        storage.resolve_storage_path(data_dir, storage_path)


def test_folder_helpers_only_accept_uuids(data_dir):
    with pytest.raises(ValueError):
        storage.night_dir(data_dir, "../..", uuid.uuid4())
    with pytest.raises(ValueError):
        storage.delete_user_files(data_dir, "..")


# --- validation ---------------------------------------------------------------------------


def test_upload_validation_errors_leave_no_files(client, alice, night_id, data_dir):
    url = f"/nights/{night_id}/recordings"
    assert upload(client, alice.headers, night_id, kind=None).status_code == 422
    assert upload(client, alice.headers, night_id, kind="mp3").status_code == 422
    assert upload(client, alice.headers, night_id, content=b"").status_code == 422
    no_file = client.post(url, headers=alice.headers, data={"kind": "edf"}, files={"other": ("a.txt", b"hi")})
    assert no_file.status_code == 422
    assert "file" in no_file.json()["detail"]
    assert client.post(url, headers=alice.headers, json={"kind": "edf"}).status_code == 422
    two_files = client.post(
        url,
        headers=alice.headers,
        data={"kind": "edf"},
        files=[("file", ("a.edf", b"1")), ("file", ("b.edf", b"2"))],
    )
    assert two_files.status_code == 422
    broken = client.post(
        url,
        headers={**alice.headers, "Content-Type": "multipart/form-data; boundary=xyz"},
        content=b"--xyz\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.edf\"\r\n\r\nhalf a file",
    )
    assert broken.status_code == 422
    assert recording_files(data_dir) == []


def test_upload_to_unknown_or_invalid_night(client, alice):
    assert upload(client, alice.headers, str(uuid.uuid4())).status_code == 404
    assert upload(client, alice.headers, "not-a-uuid").status_code == 422


# --- list, download, delete ---------------------------------------------------------------


def test_list_newest_first_with_pagination(client, alice, night_id):
    first = upload(client, alice.headers, night_id, filename="first.edf").json()
    second = upload(client, alice.headers, night_id, filename="second.csv", kind="raw_csv").json()
    response = client.get(f"/nights/{night_id}/recordings", headers=alice.headers)
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 2
    assert {item["id"] for item in body["items"]} == {first["id"], second["id"]}
    assert all("storage_path" not in item for item in body["items"])

    page = client.get(f"/nights/{night_id}/recordings?limit=1&offset=1", headers=alice.headers).json()
    assert page["total"] == 2 and len(page["items"]) == 1
    assert client.get(f"/nights/{night_id}/recordings?limit=201", headers=alice.headers).status_code == 422


def test_download_returns_the_exact_bytes(client, alice, night_id):
    recording = upload(client, alice.headers, night_id).json()
    response = client.get(f"/recordings/{recording['id']}/download", headers=alice.headers)
    assert response.status_code == 200
    assert response.content == EDF_BYTES
    assert hashlib.sha256(response.content).hexdigest() == recording["sha256"]
    assert 'filename="night.edf"' in response.headers["content-disposition"]


def test_download_when_file_vanished_is_404(client, alice, night_id, data_dir):
    recording = upload(client, alice.headers, night_id).json()
    for path in recording_files(data_dir):
        path.unlink()
    assert client.get(f"/recordings/{recording['id']}/download", headers=alice.headers).status_code == 404


def test_delete_removes_row_and_file(client, alice, night_id, data_dir):
    keep = upload(client, alice.headers, night_id, filename="keep.edf").json()
    gone = upload(client, alice.headers, night_id, filename="gone.edf").json()
    gone_path = storage.night_dir(data_dir, alice.id, night_id) / f"{gone['id']}.edf"
    assert gone_path.is_file()

    assert client.delete(f"/recordings/{gone['id']}", headers=alice.headers).status_code == 204
    assert not gone_path.exists()
    assert [path.stem for path in recording_files(data_dir)] == [keep["id"]]
    assert client.get(f"/recordings/{gone['id']}/download", headers=alice.headers).status_code == 404
    assert client.delete(f"/recordings/{gone['id']}", headers=alice.headers).status_code == 404
    listed = client.get(f"/nights/{night_id}/recordings", headers=alice.headers).json()
    assert [item["id"] for item in listed["items"]] == [keep["id"]]


# --- authentication and other users -------------------------------------------------------


def test_every_endpoint_needs_sign_in(client, alice, night_id):
    recording = upload(client, alice.headers, night_id).json()
    responses = [
        upload(client, {}, night_id),
        client.get(f"/nights/{night_id}/recordings"),
        client.get(f"/recordings/{recording['id']}/download"),
        client.delete(f"/recordings/{recording['id']}"),
        upload(client, {"Authorization": "Bearer not-a-token"}, night_id),
    ]
    for response in responses:
        assert response.status_code == 401
        assert response.headers["www-authenticate"] == "Bearer"


def test_other_users_recordings_are_404(client, alice, bob, night_id, data_dir):
    recording = upload(client, alice.headers, night_id).json()

    assert upload(client, bob.headers, night_id).status_code == 404
    assert client.get(f"/nights/{night_id}/recordings", headers=bob.headers).status_code == 404
    assert client.get(f"/recordings/{recording['id']}/download", headers=bob.headers).status_code == 404
    assert client.delete(f"/recordings/{recording['id']}", headers=bob.headers).status_code == 404

    # Alice's file is untouched and Bob's failed upload left nothing behind.
    assert len(recording_files(data_dir)) == 1
    assert client.get(f"/recordings/{recording['id']}/download", headers=alice.headers).content == EDF_BYTES
    assert not storage.user_dir(data_dir, bob.id).exists()


# --- helpers used when deleting nights and users -----------------------------------------


def test_delete_night_files_and_delete_user_files(client, db, alice, bob, night_id, data_dir):
    other_night = make_night(db, alice.id)
    bobs_night = make_night(db, bob.id)
    upload(client, alice.headers, night_id)
    upload(client, alice.headers, night_id, filename="second.edf")
    upload(client, alice.headers, other_night)
    bobs = upload(client, bob.headers, bobs_night).json()
    assert len(recording_files(data_dir)) == 4

    storage.delete_night_files(data_dir, alice.id, night_id)
    assert not storage.night_dir(data_dir, alice.id, night_id).exists()
    assert len(recording_files(data_dir)) == 2

    storage.delete_user_files(data_dir, alice.id)
    assert not storage.user_dir(data_dir, alice.id).exists()
    assert [path.stem for path in recording_files(data_dir)] == [bobs["id"]]

    # Deleting what is already gone is fine.
    storage.delete_night_files(data_dir, alice.id, night_id)
    storage.delete_user_files(data_dir, alice.id)


# --- files that cannot be removed right away (Windows: open while downloading or scanned) ----

ON_WINDOWS = os.name == "nt"  # elsewhere an open file can be removed at once, so nothing is left to retry


def stored_path(data_dir: Path) -> Path:
    (path,) = recording_files(data_dir)
    return path


def pending_entries(data_dir: Path) -> list[str]:
    pending = data_dir / storage.PENDING_DELETIONS_FILE
    return pending.read_text(encoding="utf-8").splitlines() if pending.exists() else []


def test_recording_deleted_while_open_is_removed_after_the_next_download(client, alice, night_id, data_dir):
    first = upload(client, alice.headers, night_id).json()
    path = stored_path(data_dir)
    with open(path, "rb"):  # like a download that is still streaming this file
        assert client.delete(f"/recordings/{first['id']}", headers=alice.headers).status_code == 204
        if ON_WINDOWS:
            assert path.exists()
            assert len(pending_entries(data_dir)) == 1
    second = upload(client, alice.headers, night_id).json()
    assert client.get(f"/recordings/{second['id']}/download", headers=alice.headers).status_code == 200
    assert not path.exists()
    assert pending_entries(data_dir) == []


def test_night_deleted_while_a_file_is_open_is_removed_on_the_next_start(
    client, make_client, alice, night_id, data_dir
):
    upload(client, alice.headers, night_id)
    path = stored_path(data_dir)
    with open(path, "rb"):
        assert client.delete(f"/nights/{night_id}", headers=alice.headers).status_code == 204
    if ON_WINDOWS:
        assert path.exists()  # the handle is closed now, but nothing has retried yet
    make_client()  # a restart of the server
    assert not storage.night_dir(data_dir, alice.id, night_id).exists()
    assert pending_entries(data_dir) == []


def test_pending_deletions_stay_listed_while_still_locked(client, alice, night_id, data_dir):
    recording = upload(client, alice.headers, night_id).json()
    path = stored_path(data_dir)
    with open(path, "rb"):
        client.delete(f"/recordings/{recording['id']}", headers=alice.headers)
        storage.retry_pending_deletions(data_dir)
        if ON_WINDOWS:
            assert len(pending_entries(data_dir)) == 1
    storage.retry_pending_deletions(data_dir)
    assert not path.exists()
    assert pending_entries(data_dir) == []


def test_pending_deletions_never_touch_files_outside_recordings(data_dir):
    data_dir.mkdir(parents=True)
    outside = data_dir / "openlucid.db"
    outside.write_text("keep me", encoding="utf-8")
    (data_dir / storage.PENDING_DELETIONS_FILE).write_text("openlucid.db\n../x\nrecordings\n", encoding="utf-8")
    storage.retry_pending_deletions(data_dir)
    assert outside.read_text(encoding="utf-8") == "keep me"
    assert pending_entries(data_dir) == []
