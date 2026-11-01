# Backend: the Diary Keeper

A small Python server (FastAPI) that writes down everything about your night: the nights you record, the
30-second epochs, events such as sound cues, your dream journal, and the raw recording files.

It runs in two ways, from the same code:

| | **Local mode** (the default) | **Server mode** |
|---|---|---|
| For | You, on your own laptop | You and a few other people, on a server |
| Database | SQLite: one file, nothing to install | PostgreSQL |
| Start with | `uvicorn` | `docker compose` |
| Files in | `backend/data/` | a Docker volume |

The full design (data model, every endpoint, security rules) is in [SPEC.md](SPEC.md).

> **Educational, not medical advice.** The Diary Keeper stores data; it does not diagnose or treat anything.

## Local mode: on your own computer

You need [Python 3.11 or newer](https://www.python.org/downloads/). Nothing else: SQLite is built into Python.

Windows (PowerShell), from this `backend` folder:

```powershell
python -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

macOS / Linux:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Then open <http://localhost:8000/health>. You should see:

```json
{"status": "awake", "message": "The Diary Keeper is awake.", "time": "..."}
```

<http://localhost:8000/docs> is a free, automatically written manual of every endpoint, where you can try them out
(the **Authorize** button logs you in).

What happens on the first start:

- a `data/` folder appears next to this file, with the database `data/openlucid.db`;
- the database tables are created (the *migrations* run by themselves);
- a secret key for login tokens is made once and kept in `data/secret_key`. Don't share that file.

Everything stays in `data/`. To start over completely, stop the server and delete that folder (your nights go with it).

### Phone instead of laptop?

`localhost` means "this same computer". If the app runs on a phone, start the server so other devices on your home
Wi-Fi can reach it, and use the laptop's IP address in the app's settings:

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Only do this on a network you trust: the connection is plain HTTP, not encrypted.

## Server mode: with Docker

For a server that more people use. You need [Docker](https://docs.docker.com/get-docker/) with Compose.
One command starts two containers: PostgreSQL 17 and the API.

**1. Make your settings file.** From this `backend` folder:

```bash
cp .env.example .env
```

Open `.env` and fill in the two secrets. Make each one with:

```bash
python -c "import secrets; print(secrets.token_urlsafe(48))"
```

- `POSTGRES_PASSWORD`: the database password. Letters, digits, `-` and `_` only, because it goes into a URL
  (the command above makes exactly that).
- `OPENLUCID_SECRET_KEY`: signs the login tokens, at least 32 characters. If you change it, everybody is logged out.

`.env` holds secrets: never commit it, never paste it in a chat or an issue.

**2. Start it:**

```bash
docker compose up -d --build
```

The API container first brings the database up to date (`alembic upgrade head`), then starts the server.
Check that it's healthy:

```bash
docker compose ps
curl http://127.0.0.1:8000/health
```

**Where your data lives.** Two named Docker volumes: `db-data` (the PostgreSQL database) and `recordings`
(`DATA_DIR` inside the container: the uploaded EEG files). They survive restarts, rebuilds and
`docker compose down`. **`docker compose down -v` deletes them for good.** Back them up.

**Useful commands:**

| Command | What it does |
|---|---|
| `docker compose logs -f api` | Follow the server's log |
| `docker compose pull && docker compose up -d --build` | Update after `git pull` |
| `docker compose down` | Stop (data stays) |

**Before you open it to the internet:**

- The API only listens on `127.0.0.1:8000` of the server. Put a reverse proxy with HTTPS in front of it
  (for example [Caddy](https://caddyserver.com/) or nginx). Never send passwords and EEG data over plain HTTP.
- The login rate limit counts failed attempts per client IP. The compose file gives its network a fixed range
  (`172.30.250.0/24`), and `FORWARDED_ALLOW_IPS` defaults to its gateway `172.30.250.1`: that is the address a
  reverse proxy *on the host* shows up with inside the container (not `127.0.0.1`). If your proxy runs in a
  container, set `FORWARDED_ALLOW_IPS` to that container's address. If the range clashes with another network,
  change it in `docker-compose.yml` and set `FORWARDED_ALLOW_IPS` to the new gateway. With a wrong value every
  visitor looks like the proxy and shares one limit; never use `*`, which lets anyone fake their address.
- If the morning view runs on its own web address, add it to `OPENLUCID_CORS_ORIGINS`.
- The database has no open port; only the API container can reach it.
- The API runs one worker process on purpose: the login rate limiter lives in memory.

> The Docker image and the compose file were written and checked without Docker running (the YAML was parsed and
> the container's start command was run by hand). If something fails on your machine, please open an issue.

## Creating the first (admin) account

**The very first account that registers becomes the admin.** Every later account is a normal user. So:

1. Start the server, and register yourself **straight away**, before you tell anyone the address.
   The easiest way is <http://localhost:8000/docs> → `POST /auth/register` → *Try it out*:

   ```json
   {
     "email": "you@example.org",
     "password": "at least ten characters",
     "display_name": "You",
     "accept_consent": true,
     "consent_version": "2026-11"
   }
   ```

   `consent_version` must match what `GET /version` says. Or with curl (macOS / Linux shell):

   ```bash
   curl -X POST http://127.0.0.1:8000/auth/register -H "Content-Type: application/json" \
     -d '{"email":"you@example.org","password":"at least ten characters","accept_consent":true,"consent_version":"2026-11"}'
   ```

2. The answer shows `"role": "admin"`. As admin you can list accounts and make other people admin or
   deactivate them (`/admin/users`). An admin never sees other people's nights, epochs, events or journal.
3. Only you? Close sign-ups: set `OPENLUCID_ALLOW_REGISTRATION=false` in `.env` and run `docker compose up -d`.

## All settings

Every setting is an environment variable starting with `OPENLUCID_`. They are also read from a file `backend/.env`
(in local mode too, so be aware of what's in there).

| Variable | Default | Meaning |
|---|---|---|
| `OPENLUCID_MODE` | `local` | `local` or `server`. The Docker image uses `server`. |
| `OPENLUCID_DATABASE_URL` | `sqlite:///<DATA_DIR>/openlucid.db` | Where the database is. PostgreSQL looks like `postgresql+psycopg://user:password@host:5432/dbname`. Docker Compose sets this for you. |
| `OPENLUCID_DATA_DIR` | `./data` | Folder for the SQLite file (local), the recordings and the generated secret key. `/data` in Docker. |
| `OPENLUCID_SECRET_KEY` | (none) | Signs the login tokens, at least 32 characters. **Required in server mode** (it refuses to start without). In local mode it's made once and kept in `DATA_DIR/secret_key`. |
| `OPENLUCID_ACCESS_TOKEN_MINUTES` | `15` | How long an access token is valid. |
| `OPENLUCID_REFRESH_TOKEN_DAYS` | `30` | How long you stay logged in without typing your password again. |
| `OPENLUCID_ALLOW_REGISTRATION` | `true` | `false` closes sign-ups. |
| `OPENLUCID_CORS_ORIGINS` | (empty) | Extra web addresses allowed to call the API, comma-separated. Localhost on any port is always allowed. |
| `OPENLUCID_MAX_UPLOAD_MB` | `200` | Largest single recording upload. |
| `OPENLUCID_AUTO_MIGRATE` | `true` | Bring the database up to date on startup. The Docker image sets `false` because it migrates just before starting. |
| `OPENLUCID_CONSENT_VERSION` | `2026-11` | Version of the privacy text people agree to when registering. |

Only for Docker Compose (in `.env`):

| Variable | Default | Meaning |
|---|---|---|
| `POSTGRES_PASSWORD` | (none, required) | Password of the PostgreSQL user `openlucid`. |
| `OPENLUCID_BIND` | `127.0.0.1:8000` | Address and port on the server where the API listens. |
| `FORWARDED_ALLOW_IPS` | `172.30.250.1` | Reverse-proxy address trusted for `X-Forwarded-For` (read by uvicorn); the compose network's gateway. |

## Database migrations

The tables are described in `app/models.py`; the steps that build them are in `alembic/versions/`.
They run by themselves on startup, but you can run them by hand too (from this folder, venv active):

```bash
alembic upgrade head                                 # bring the database up to date
alembic revision --autogenerate -m "what changed"    # after you changed app/models.py
```

## Running the tests

On SQLite (fast, nothing to install). With the venv active, from this folder:

```bash
pytest
```

Each test gets its own fresh database and data folder, so your own `data/` is never touched. The tests ignore
`OPENLUCID_DATABASE_URL`, so a real database you exported it for is never touched either.

On PostgreSQL: you need PostgreSQL 15 or newer installed (on Windows the installer from
[postgresql.org](https://www.postgresql.org/download/) puts it in `C:\Program Files\PostgreSQL\<version>`;
elsewhere `initdb` and `pg_ctl` must be on your PATH). Then:

```bash
python scripts/pg_test.py            # extra arguments go to pytest, e.g. -q -k journal
```

It creates a brand-new temporary PostgreSQL in a temp folder on a free port, runs all tests against it, then stops
and deletes it. It never touches a PostgreSQL you already have running. (It hands the address to the tests in
`OPENLUCID_TEST_DATABASE_URL`; the tests refuse a database whose name does not end in `_test`.)

## Privacy: please read this if you run a server

*This is not legal advice. It's a plain-language summary to help you ask the right questions.*

**What this server stores is health data.** EEG recordings and sleep data say something about a person's body
and health. Under the European GDPR that is a *special category* of personal data (article 9), with stricter rules
than, say, an email address. Other countries have similar laws.

**On your own laptop, for yourself,** it's your data on your computer. Local mode is the default for that reason.

**As soon as other people's nights are on a server you run, you are responsible for them** (in GDPR terms you are
probably the *controller*). That roughly means:

- **Consent.** People must agree explicitly, knowing what is stored and why. The Diary Keeper records which version of
  the privacy text someone accepted and when (`consent_version`, `consent_at`). You must write that text yourself
  and bump `OPENLUCID_CONSENT_VERSION` when it changes.
- **Only what's needed.** Don't collect more than you use. The server has no analytics and calls no third parties;
  keep it that way.
- **Security.** HTTPS only, strong secrets, updates, encrypted backups, and few people with access to the server.
  The Diary Keeper does not encrypt the database or the recording files on disk itself; use disk encryption on
  the server.
- **People's rights.** Everyone can download all their data (`GET /me/export`) and delete their account with
  everything in it, including recording files (`DELETE /me`). Copies in your backups count too.
- **Admins.** The admin role can manage accounts, but cannot see anyone else's nights, epochs, events or journal
  through the API. Don't work around that by reading the database directly.
- **Data breaches** usually have to be reported to the data protection authority, often within 72 hours.

**Research.** If you want to use other people's nights for a study (for example a PhD), you almost always need
**ethics approval** first, usually through a university, plus a consent text written for research. Data collected
without that may not be usable later. Until then: use the server with yourself and test accounts.

When in doubt, ask your university's data protection officer or a lawyer.
