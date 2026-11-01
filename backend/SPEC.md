# Backend specification (checkpoint 02: the Diary Keeper as a multi-user server)

One codebase that runs **locally** (SQLite, one user or a few, nothing to install) and **on a server** (PostgreSQL, many users). Everything below is binding for implementers; if something must change, change this file in the same commit and say why.

## Principles

1. **Local first.** Default config runs on a laptop with SQLite and files in `./data`. A server is opt-in via environment variables.
2. **Raw EEG never goes into database rows.** Raw recordings (EDF, raw CSV) are files on disk (`DATA_DIR/recordings/<user_id>/<night_id>/`). The database holds metadata, 30-second epochs, events and journal entries.
3. **Every user sees only their own data.** Every query is scoped to the current user. Another user's resource answers **404**, never 403 (don't reveal that it exists).
4. **Idempotent sync.** The app records offline and uploads later, possibly twice. Creating nights and events accepts a client-generated id (`client_id`); repeating a request returns the existing object instead of creating a duplicate. Epochs are upserted by `(night_id, index)`.
5. **Privacy built in.** A user can export all their data and delete their account, which deletes all their rows and files. Registration records consent (version + time). No analytics, no third-party calls.
6. **Health data.** EEG and sleep data are sensitive. No medical claims anywhere in API texts.

## Stack

- Python 3.11+ (developed on 3.13), FastAPI, Uvicorn
- SQLAlchemy 2.0 (sync ORM, `Mapped[...]` style), Alembic for migrations
- SQLite (default, `sqlite:///./data/openlucid.db`) and PostgreSQL 15+ via psycopg 3 (`postgresql+psycopg://...`)
- Pydantic v2 + pydantic-settings
- Passwords: argon2 (`argon2-cffi`). Tokens: PyJWT (HS256)
- Tests: pytest + FastAPI TestClient (httpx)

## Configuration (environment variables, prefix `OPENLUCID_`, also read from `backend/.env`)

| Variable | Default | Meaning |
|---|---|---|
| `OPENLUCID_MODE` | `local` | `local` or `server` |
| `OPENLUCID_DATABASE_URL` | `sqlite:///<DATA_DIR>/openlucid.db` | SQLAlchemy URL |
| `OPENLUCID_DATA_DIR` | `./data` | Files: SQLite db (local), recordings, generated secret |
| `OPENLUCID_SECRET_KEY` | — | JWT signing key. **Required in server mode** (startup fails without it, min 32 chars). In local mode, generated once and stored in `DATA_DIR/secret_key` (file mode 600 where supported) |
| `OPENLUCID_ACCESS_TOKEN_MINUTES` | `15` | Access token lifetime |
| `OPENLUCID_REFRESH_TOKEN_DAYS` | `30` | Refresh token lifetime |
| `OPENLUCID_ALLOW_REGISTRATION` | `true` | Server admins can close sign-ups |
| `OPENLUCID_CORS_ORIGINS` | empty | Extra allowed origins (comma-separated). Localhost on any port is always allowed (existing behaviour) |
| `OPENLUCID_MAX_UPLOAD_MB` | `200` | Max size of one recording upload |
| `OPENLUCID_AUTO_MIGRATE` | `true` | Run `alembic upgrade head` on startup |
| `OPENLUCID_CONSENT_VERSION` | `2026-11` | Current version of the privacy/consent text |

## Data model

All ids are UUID4 (stored as `Uuid` type, works on SQLite and PostgreSQL). All timestamps are timezone-aware UTC; API accepts ISO 8601 with offset (years 1900–2199, else 422) and returns ISO 8601 with `Z` or `+00:00`. Request bodies may not contain NUL characters anywhere (PostgreSQL cannot store them) and event `details` must be strict JSON (no NaN/Infinity); both give 422, so SQLite and PostgreSQL behave the same.

**users**: `id`, `email` (unique, stored lowercased, max 254), `password_hash`, `display_name` (nullable, max 100), `role` (`user` | `admin`), `is_active` (bool, default true), `consent_version`, `consent_at`, `created_at`, `updated_at`.

**refresh_tokens**: `id`, `user_id` (FK users, cascade delete), `token_hash` (sha256 hex of the opaque token, unique), `expires_at`, `revoked_at` (nullable), `created_at`, `replaced_by_id` (nullable FK refresh_tokens).

**nights**: `id`, `user_id` (FK, cascade), `client_id` (string max 64, nullable; unique together with user_id when set), `started_at`, `ended_at` (nullable), `device_name` (max 100), `device_firmware` (nullable), `channels` (JSON list of strings), `sample_rate` (float), `timezone` (IANA name, nullable), `notes` (text, nullable, max 5000), `created_at`, `updated_at`.

**epochs**: `id`, `night_id` (FK, cascade), `index` (int ≥ 0, epoch number, 30 s each; unique with night_id), `started_at`, `stage` (nullable: `wake` | `n1` | `n2` | `n3` | `rem` | `unknown`), `stage_confidence` (nullable float 0–1), `contact` (JSON object channel → score 0–1, nullable), `quality` (nullable: `good` | `okay` | `poor` | `gap`), `created_at`, `updated_at`.

**events**: `id`, `night_id` (FK, cascade), `client_id` (nullable, unique with night_id when set), `at`, `type` (string max 40, e.g. `cue`, `lrlr`, `woke_up`, `reconnect`, `contact_lost`, `note`), `details` (JSON object, nullable, max 10 kB serialized), `created_at`.

**journal_entries**: `id`, `user_id` (FK, cascade), `night_id` (nullable FK, set null on delete), `written_at`, `lucid` (`yes` | `no` | `maybe`), `vividness` (int 1–5, nullable), `text` (max 20000), `created_at`, `updated_at`. If `night_id` is given it must belong to the same user (else 404).

**recordings**: `id`, `night_id` (FK, cascade), `kind` (`edf` | `raw_csv` | `other`), `original_filename` (sanitized, max 200), `size_bytes`, `sha256`, `storage_path` (relative to DATA_DIR, never returned to clients), `uploaded_at`.

Deleting a night deletes its epochs, events, recordings rows **and recording files**. Deleting a user deletes everything of theirs, including files. A file the OS will not remove right now (on Windows: while it is being downloaded or scanned) is listed in `DATA_DIR/pending_deletions.txt` and removed later: on startup, after every delete and after every download.

## API

JSON everywhere except uploads (multipart) and downloads (file). Errors: `{"detail": "..."}` with the right status. List endpoints take `limit` (default 50, max 200) and `offset`, and return `{"items": [...], "total": n}`.

### Public
- `GET /health` → `{"status":"awake","message":"The Diary Keeper is awake.","time":...}` (unchanged; existing tests must keep passing)
- `GET /version` → `{"name":"openlucid","version":...,"mode":"local"|"server","registration_open":bool,"consent_version":...}`

### Auth
- `POST /auth/register` `{email, password, display_name?, accept_consent: true, consent_version}` → 201 `{user, access_token, refresh_token, token_type:"bearer"}`. Password ≥ 10 chars. `accept_consent` must be true and `consent_version` must equal the current one (else 422). 409 if email taken (message must not otherwise leak). 403 if registration closed. **The first user ever becomes `admin`.**
- `POST /auth/login` `{email, password}` → 200 same shape as register. 401 on wrong email or password (same message for both). 403 if user inactive. Rate limit: max 10 failed attempts per email per 15 min and 30 per client IP per 15 min (in-memory is fine) → 429.
- `POST /auth/token` — OAuth2 password form (`username`=email, `password`) for the Swagger "Authorize" button; same rules as login; returns `{access_token, token_type}`.
- `POST /auth/refresh` `{refresh_token}` → new access + **rotated** refresh token; the old one is revoked. Reusing a revoked refresh token revokes **all** of that user's refresh tokens (theft detection) and returns 401.
- `POST /auth/logout` `{refresh_token}` → 204; revokes it.
- Access token: JWT HS256 with `sub` (user id), `exp`, `iat`, `type:"access"`. Requests use `Authorization: Bearer <token>`. Invalid/expired/wrong type → 401 with `WWW-Authenticate: Bearer`.

### Account (current user)
- `GET /me` → user (never includes password hash)
- `PATCH /me` `{display_name?}` → user
- `POST /me/password` `{current_password, new_password}` → 204; revokes all refresh tokens.
- `GET /me/export` → JSON document with the user, nights (with epochs and events), journal entries and recording metadata (not file contents). Header `Content-Disposition: attachment; filename="openlucid-export.json"`.
- `DELETE /me` `{password}` → 204; deletes the user and everything of theirs, including files.

### Nights
- `GET /nights` → own nights, newest first
- `POST /nights` `{client_id?, started_at, device_name, device_firmware?, channels, sample_rate, timezone?, notes?}` → 201; if `client_id` already exists for this user → 200 with the existing night
- `GET /nights/{id}`, `PATCH /nights/{id}` `{ended_at?, notes?, device_firmware?}`, `DELETE /nights/{id}` → 204
- `GET /nights/{id}/summary` → `{night, epoch_count, stage_minutes: {stage: minutes}, event_counts: {type: n}, contact_average: {channel: mean score}, recordings: n}`

### Epochs
- `PUT /nights/{id}/epochs` `{epochs: [{index, started_at, stage?, stage_confidence?, contact?, quality?}]}` (max 1000 per call) → 200 `{upserted: n}`; existing indexes are updated
- `GET /nights/{id}/epochs?from_index=&to_index=` → items ordered by index (pagination limit max 2000 here)

### Events
- `POST /nights/{id}/events` `{events: [{client_id?, at, type, details?}]}` (max 500) → 200 `{created: n, existing: m}`
- `GET /nights/{id}/events?type=` → ordered by `at`

### Recordings
- `POST /nights/{id}/recordings` multipart: `file`, `kind` → 201 recording; streamed to disk, size limited (413 when too big), sha256 computed while streaming; filename sanitized; stored under `DATA_DIR/recordings/<user_id>/<night_id>/<recording_id>.<ext>`
- `GET /nights/{id}/recordings` → list
- `GET /recordings/{id}/download` → the file (own only)
- `DELETE /recordings/{id}` → 204, deletes the file

### Journal
- `GET /journal?night_id=`, `POST /journal`, `GET /journal/{id}`, `PATCH /journal/{id}`, `DELETE /journal/{id}`

### Admin (role admin only; others get 403)
- `GET /admin/users` → list with `id, email, display_name, role, is_active, created_at, night_count` — **no** EEG, epochs, events or journal of other users
- `PATCH /admin/users/{id}` `{role?, is_active?}` → an admin cannot demote or deactivate themselves if they are the last active admin (409)

## Code layout (file ownership for parallel work)

```
backend/
├── app/
│   ├── main.py            create_app(); registers every router; CORS; startup migration     [foundation]
│   ├── config.py          Settings                                                          [foundation]
│   ├── db.py              engine, SessionLocal, get_db, Base                                [foundation]
│   ├── models.py          ALL tables above                                                  [foundation]
│   ├── schemas.py         ALL request/response Pydantic models                              [foundation]
│   ├── security.py        argon2, JWT, refresh-token helpers, rate limiter                  [foundation]
│   ├── deps.py            current_user, admin_user, pagination                              [foundation]
│   ├── storage.py         recording file storage helpers                                    [recordings]
│   └── routers/
│       ├── auth.py        /auth/*                                                           [foundation]
│       ├── account.py     /me*                                                              [account]
│       ├── nights.py      /nights, summary, epochs, events                                  [nights]
│       ├── recordings.py  /nights/{id}/recordings, /recordings/*                            [recordings]
│       ├── journal.py     /journal                                                          [journal]
│       └── admin.py       /admin/*                                                          [account]
├── alembic/ + alembic.ini migrations                                                        [foundation]
├── scripts/pg_test.py     starts a throwaway PostgreSQL from local binaries for tests        [foundation]
├── tests/                 conftest.py [foundation]; test_<area>.py per owner
├── Dockerfile, docker-compose.yml, .env.example                                             [deploy]
└── README.md                                                                                [deploy]
```

## Tests

- Run on SQLite by default: `pytest`.
- Run on PostgreSQL: `python scripts/pg_test.py` (finds `initdb`/`pg_ctl` from `C:\Program Files\PostgreSQL\<ver>\bin` or PATH, creates a temporary cluster in a temp dir on a free port, runs pytest with `OPENLUCID_TEST_DATABASE_URL` pointing to it, then stops and removes it). Must not touch any existing PostgreSQL installation or service. The tests ignore `OPENLUCID_DATABASE_URL` and refuse a test database whose name does not end in `_test`, because every test drops all tables.
- Every endpoint has tests for: happy path, validation errors, unauthenticated (401), **another user's resource (404)**.
