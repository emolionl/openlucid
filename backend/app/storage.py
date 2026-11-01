"""Where raw recording files live on disk, and how they get there safely.

Layout: DATA_DIR/recordings/<user_id>/<night_id>/<recording_id>.<ext>

- Folder and file names on disk are built only from UUIDs and a short checked extension,
  never from what a client sends, so a filename like "../../secret" cannot escape.
- Uploads are streamed to disk chunk by chunk while the sha256 is computed. The data first goes
  to a "<recording_id>.part" file that is renamed only when everything went well; on any error
  (too big, broken request, client gone) the part file is removed.
- Deleting can fail for a while, e.g. on Windows while the file is being downloaded or scanned by an
  antivirus. Such paths go to DATA_DIR/pending_deletions.txt and are removed later: on startup, after
  every delete and after every download (see retry_pending_deletions).
"""

import hashlib
import logging
import re
import shutil
import threading
import unicodedata
import uuid
from collections.abc import AsyncIterator, Iterable, Mapping
from dataclasses import dataclass
from pathlib import Path

import anyio
from python_multipart.exceptions import FormParserError
from python_multipart.multipart import MultipartParser, parse_options_header

logger = logging.getLogger(__name__)

RECORDINGS_DIR = "recordings"
PENDING_DELETIONS_FILE = "pending_deletions.txt"
MAX_FILENAME_LENGTH = 200
DEFAULT_EXTENSIONS = {"edf": "edf", "raw_csv": "csv", "other": "bin"}
SAFE_EXTENSION = re.compile(r"^[a-z0-9]{1,10}$")
# Letters (any language), digits, space, dot, dash, underscore and brackets; everything else becomes "_".
UNSAFE_FILENAME_CHARS = re.compile(r"[^\w .()\[\]-]")
# Room for the multipart boundaries, part headers and the small `kind` field around the file.
MULTIPART_OVERHEAD_BYTES = 64 * 1024
MAX_FIELD_BYTES = 1024


class UploadTooLarge(Exception):
    """The uploaded file is bigger than OPENLUCID_MAX_UPLOAD_MB."""


class InvalidUpload(Exception):
    """The request is not a usable multipart upload (the message is safe to show to the client)."""


@dataclass(frozen=True)
class StoredUpload:
    """A finished upload, renamed to its final place."""

    kind: str
    original_filename: str
    size_bytes: int
    sha256: str
    storage_path: str  # relative to DATA_DIR, with forward slashes


# --- paths --------------------------------------------------------------------------------


def recordings_root(data_dir: Path) -> Path:
    return Path(data_dir) / RECORDINGS_DIR


def user_dir(data_dir: Path, user_id: uuid.UUID | str) -> Path:
    # uuid.UUID() refuses anything that is not a UUID, so the folder name is always safe.
    return recordings_root(data_dir) / str(uuid.UUID(str(user_id)))


def night_dir(data_dir: Path, user_id: uuid.UUID | str, night_id: uuid.UUID | str) -> Path:
    return user_dir(data_dir, user_id) / str(uuid.UUID(str(night_id)))


def resolve_storage_path(data_dir: Path, storage_path: str) -> Path:
    """The absolute path of a stored file. Raises ValueError if it would point outside the recordings folder."""
    root = recordings_root(data_dir).resolve()
    path = (Path(data_dir) / storage_path).resolve()
    if not path.is_relative_to(root) or path == root:
        raise ValueError("Storage path points outside the recordings folder.")
    return path


# --- names --------------------------------------------------------------------------------


def sanitize_filename(filename: str | None) -> str:
    """A harmless display name for an uploaded file: no folders, no control or odd characters, max 200 chars.

    It is only stored and shown (and used in the download header), never used as a path on disk.
    """
    name = unicodedata.normalize("NFKC", filename or "")
    name = re.split(r"[\\/]", name)[-1]  # drop any folder part, Unix or Windows style
    name = "".join(char for char in name if unicodedata.category(char)[0] != "C")  # control characters
    name = UNSAFE_FILENAME_CHARS.sub("_", name).strip(" .")
    if not name:
        return "recording"
    if len(name) > MAX_FILENAME_LENGTH:
        stem, dot, extension = name.rpartition(".")
        if dot and 0 < len(extension) <= 10:
            name = stem[: MAX_FILENAME_LENGTH - len(extension) - 1] + "." + extension
        else:
            name = name[:MAX_FILENAME_LENGTH]
    return name


def file_extension(kind: str, filename: str) -> str:
    """The extension used on disk: the upload's own one if it is short and plain, else one that fits `kind`."""
    _, dot, extension = filename.rpartition(".")
    extension = extension.lower()
    if dot and SAFE_EXTENSION.match(extension):
        return extension
    return DEFAULT_EXTENSIONS.get(kind, "bin")


# --- upload -------------------------------------------------------------------------------


class _UploadReceiver:
    """Feeds a multipart body to python-multipart and writes the one `file` part straight to a part file."""

    def __init__(self, part_path: Path, max_bytes: int):
        self.part_path = part_path
        self.max_bytes = max_bytes
        self.sha256 = hashlib.sha256()
        self.size = 0
        self.filename: str | None = None
        self.fields: dict[str, bytearray] = {}
        self._file = None
        self._pending: list[bytes] = []
        self._header_name = b""
        self._header_value = b""
        self._disposition = b""
        self._current: str | None = None  # "file", a field name, or None for parts we skip
        self._skip_part = False

    # python-multipart callbacks (plain functions, called while parsing a chunk)

    def on_part_begin(self) -> None:
        self._disposition = b""
        self._current = None
        self._skip_part = False

    def on_header_field(self, data: bytes, start: int, end: int) -> None:
        self._header_name += data[start:end]

    def on_header_value(self, data: bytes, start: int, end: int) -> None:
        self._header_value += data[start:end]

    def on_header_end(self) -> None:
        if self._header_name.lower() == b"content-disposition":
            self._disposition = self._header_value
        self._header_name = b""
        self._header_value = b""

    def on_headers_finished(self) -> None:
        _, options = parse_options_header(self._disposition)
        name = options.get(b"name", b"").decode("utf-8", errors="replace")
        if name == "file":
            if self.filename is not None:
                raise InvalidUpload("Send exactly one file per upload.")
            self.filename = options.get(b"filename", b"").decode("utf-8", errors="replace")
            self._current = "file"
        elif name == "kind":
            if name in self.fields:
                raise InvalidUpload("Send the field 'kind' only once.")
            self.fields[name] = bytearray()
            self._current = name
        else:
            self._skip_part = True  # unknown parts are ignored, but still count towards the body limit

    def on_part_data(self, data: bytes, start: int, end: int) -> None:
        if self._skip_part:
            return
        chunk = data[start:end]
        if self._current == "file":
            self.size += len(chunk)
            if self.size > self.max_bytes:
                raise UploadTooLarge()
            self.sha256.update(chunk)
            self._pending.append(chunk)
        elif self._current is not None:
            field = self.fields[self._current]
            field.extend(chunk)
            if len(field) > MAX_FIELD_BYTES:
                raise InvalidUpload(f"The field '{self._current}' is too long.")

    def on_part_end(self) -> None:
        self._current = None

    # writing

    def _write_pending(self) -> None:
        if self._file is None:
            self._file = open(self.part_path, "wb")
        for chunk in self._pending:
            self._file.write(chunk)
        self._pending.clear()

    async def flush(self) -> None:
        """Write what the parser collected, in a worker thread so the server keeps answering."""
        if self._pending or self._file is None:
            await anyio.to_thread.run_sync(self._write_pending)

    def close(self) -> None:
        if self._file is not None:
            self._file.close()


async def receive_upload(
    body: AsyncIterator[bytes],
    headers: Mapping[str, str],
    data_dir: Path,
    user_id: uuid.UUID,
    night_id: uuid.UUID,
    recording_id: uuid.UUID,
    max_bytes: int,
    allowed_kinds: tuple[str, ...],
) -> StoredUpload:
    """Stream a multipart body (fields `file` and `kind`) into the night's folder.

    Raises UploadTooLarge or InvalidUpload; in every failure case no file is left behind.
    """
    content_type = headers.get("content-type", "")
    mime_type, params = parse_options_header(content_type)
    boundary = params.get(b"boundary")
    if mime_type != b"multipart/form-data" or not boundary:
        raise InvalidUpload("Send the recording as multipart/form-data with the fields 'file' and 'kind'.")

    max_body_bytes = max_bytes + MULTIPART_OVERHEAD_BYTES
    declared_length = headers.get("content-length")
    if declared_length and declared_length.isdigit() and int(declared_length) > max_body_bytes:
        raise UploadTooLarge()  # refuse before reading anything

    folder = night_dir(data_dir, user_id, night_id)
    folder.mkdir(parents=True, exist_ok=True)
    part_path = folder / f"{recording_id}.part"
    receiver = _UploadReceiver(part_path, max_bytes)
    parser = MultipartParser(
        boundary,
        {
            "on_part_begin": receiver.on_part_begin,
            "on_header_field": receiver.on_header_field,
            "on_header_value": receiver.on_header_value,
            "on_header_end": receiver.on_header_end,
            "on_headers_finished": receiver.on_headers_finished,
            "on_part_data": receiver.on_part_data,
            "on_part_end": receiver.on_part_end,
        },
    )
    try:
        body_bytes = 0
        async for chunk in body:
            body_bytes += len(chunk)
            if body_bytes > max_body_bytes:
                raise UploadTooLarge()
            try:
                parser.write(chunk)
            except FormParserError:
                raise InvalidUpload("The multipart data is broken.") from None
            await receiver.flush()
        try:
            parser.finalize()
        except FormParserError:
            raise InvalidUpload("The multipart data is broken or incomplete.") from None
        await receiver.flush()
        receiver.close()

        kind = receiver.fields.get("kind", bytearray()).decode("utf-8", errors="replace").strip()
        if receiver.filename is None:
            raise InvalidUpload("The field 'file' is missing.")
        if kind not in allowed_kinds:
            raise InvalidUpload(f"The field 'kind' must be one of: {', '.join(allowed_kinds)}.")
        if receiver.size == 0:
            raise InvalidUpload("The file is empty.")

        original_filename = sanitize_filename(receiver.filename)
        final_path = folder / f"{recording_id}.{file_extension(kind, original_filename)}"
        part_path.replace(final_path)
    except BaseException:
        receiver.close()
        part_path.unlink(missing_ok=True)
        raise

    return StoredUpload(
        kind=kind,
        original_filename=original_filename,
        size_bytes=receiver.size,
        sha256=receiver.sha256.hexdigest(),
        storage_path=final_path.relative_to(data_dir).as_posix(),
    )


# --- deleting -----------------------------------------------------------------------------

_pending_lock = threading.Lock()  # one thread at a time reads or rewrites the pending list


def _remove(path: Path) -> None:
    """Remove a file or a whole folder. Gone already is fine; other OS errors are raised."""
    if path.is_dir():
        try:
            shutil.rmtree(path)
        except FileNotFoundError:
            pass
    else:
        path.unlink(missing_ok=True)


def _remove_or_remember(data_dir: Path, path: Path) -> None:
    """Remove `path`; if the OS refuses for now, write it on the pending list so it is removed later."""
    try:
        _remove(path)
    except OSError as error:
        # No path in the log: it contains the user id. The error type is enough to investigate.
        logger.warning("Could not remove recording data yet (%s); will try again later.", type(error).__name__)
        entry = path.relative_to(Path(data_dir).resolve()).as_posix()
        try:
            with _pending_lock, open(Path(data_dir) / PENDING_DELETIONS_FILE, "a", encoding="utf-8") as pending:
                pending.write(entry + "\n")
        except OSError as error:
            logger.warning("Could not note the recording data for later removal (%s).", type(error).__name__)


def retry_pending_deletions(data_dir: Path) -> None:
    """Try again to remove what an earlier delete could not. Never raises; whatever still fails stays listed."""
    pending_file = Path(data_dir) / PENDING_DELETIONS_FILE
    with _pending_lock:
        try:
            entries = pending_file.read_text(encoding="utf-8").splitlines()
        except FileNotFoundError:
            return
        except OSError as error:
            logger.warning("Could not read the pending deletions (%s).", type(error).__name__)
            return
        still_pending = []
        for entry in dict.fromkeys(entry for entry in entries if entry.strip()):
            try:
                _remove(resolve_storage_path(data_dir, entry))
            except ValueError:
                logger.warning("Skipped a pending deletion that points outside the recordings folder.")
            except OSError:
                still_pending.append(entry)
        try:
            if still_pending:
                pending_file.write_text("".join(entry + "\n" for entry in still_pending), encoding="utf-8")
            else:
                pending_file.unlink()
        except OSError as error:
            logger.warning("Could not update the pending deletions (%s).", type(error).__name__)


def delete_recording_file(data_dir: Path, storage_path: str) -> None:
    """Remove one stored file. A file that is already gone is fine.

    Never raises: a path outside the recordings folder is skipped (a bad row must never delete files
    elsewhere), and a file the OS will not remove right now is put on the pending list, so a failed
    file removal never undoes a committed delete.
    """
    try:
        path = resolve_storage_path(data_dir, storage_path)
    except ValueError:
        logger.warning("Skipped a recording path that points outside the recordings folder.")
        return
    _remove_or_remember(data_dir, path)
    retry_pending_deletions(data_dir)


def delete_recording_files(data_dir: Path, storage_paths: Iterable[str]) -> None:
    """Remove several stored files (see delete_recording_file)."""
    for storage_path in storage_paths:
        delete_recording_file(data_dir, storage_path)


def delete_night_files(data_dir: Path, user_id: uuid.UUID | str, night_id: uuid.UUID | str) -> None:
    """Remove every recording file of one night (call it after the night's rows are deleted)."""
    _remove_or_remember(data_dir, night_dir(data_dir, user_id, night_id).resolve())
    retry_pending_deletions(data_dir)


def delete_user_files(data_dir: Path, user_id: uuid.UUID | str) -> None:
    """Remove every recording file of one user (call it after the user's rows are deleted)."""
    _remove_or_remember(data_dir, user_dir(data_dir, user_id).resolve())
    retry_pending_deletions(data_dir)
