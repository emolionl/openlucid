// The workflow script that built OpenLucid's backend (checkpoint 02), unchanged apart from the paths.
// It ran in Claude Code's Workflow tool: 13 agents in six phases, about 72 minutes.
// Read it next to docs/agentic/03-orchestrating-agents.md.

export const meta = {
  name: 'openlucid-backend',
  description: 'Build the OpenLucid multi-user FastAPI backend from backend/SPEC.md: foundation, parallel features, integration on SQLite and PostgreSQL, review, fixes, clean verification',
  phases: [
    { title: 'Foundation', detail: 'config, db, models, schemas, security, auth, migrations, test harness' },
    { title: 'Features', detail: 'nights/epochs/events, recordings, journal, account+admin, deploy files (parallel, file ownership)' },
    { title: 'Integrate', detail: 'apply shared-file requests, full suite on SQLite and PostgreSQL' },
    { title: 'Review', detail: 'security, isolation/privacy, API contract, operations' },
    { title: 'Fix', detail: 'reproduce each finding with a failing test, then fix' },
    { title: 'Verify', detail: 'fresh venv, follow README, both databases, live smoke test' },
  ],
}

const REPO = '/path/to/openlucid'  // where you cloned the repository
const BACKEND = REPO + '/backend'
const PY = BACKEND + '/.venv/Scripts/python.exe'  // Windows; on macOS/Linux: '/.venv/bin/python'
const COMMON = `
You are working on OpenLucid, an open-source lucid-dream project. Repository: ${REPO}. Backend: ${BACKEND}.
READ ${BACKEND}/SPEC.md FIRST — it is binding (data model, endpoints, security rules, file ownership).
Existing behaviour that must keep working: GET /health response and localhost-only CORS (see existing ${BACKEND}/tests/test_health.py).
Python: use the venv at ${BACKEND}/.venv (Windows). Run tools as "${PY} -m pip ...", "${PY} -m pytest ...". Add new dependencies to ${BACKEND}/requirements.txt with sensible version ranges and install them into that venv.
Shell: Git Bash on Windows. Never kill processes by image name (no "taskkill /IM python.exe"); only stop processes you started, by PID.
Do NOT git commit, push, or change git config. Do not touch anything outside ${BACKEND} unless your task says so.
Code style: clear names, short docstrings where they help a beginner, no dead code. Match the existing code's style (see app/main.py).
Never put medical claims in texts. Never log passwords, tokens or EEG content.
`

const SHARED_REQ = {
  type: 'object',
  properties: {
    summary: { type: 'string', description: 'What you built, briefly' },
    files_changed: { type: 'array', items: { type: 'string' } },
    tests_passed: { type: 'integer' },
    tests_failed: { type: 'integer' },
    shared_change_requests: {
      type: 'array',
      description: 'Changes you needed in files you do not own (models.py, schemas.py, main.py, deps.py, conftest.py, etc.). Describe precisely; the integrator applies them.',
      items: { type: 'string' },
    },
    open_issues: { type: 'array', items: { type: 'string' } },
  },
  required: ['summary', 'files_changed', 'tests_passed', 'tests_failed', 'shared_change_requests', 'open_issues'],
}

// ---------------- Foundation ----------------
phase('Foundation')
const foundation = await agent(`${COMMON}
YOUR TASK: build the FOUNDATION of the backend exactly per SPEC.md. You own: app/main.py, app/config.py, app/db.py, app/models.py (ALL tables in the spec), app/schemas.py (ALL request/response models for EVERY endpoint in the spec, so other agents don't need to edit it), app/security.py, app/deps.py, app/routers/auth.py, alembic.ini + alembic/ (initial migration creating ALL tables, generated or hand-written, must work on SQLite and PostgreSQL), scripts/pg_test.py, tests/conftest.py, tests/test_auth.py, requirements.txt.

Also create router stub files that the feature agents will fill in: app/routers/account.py, nights.py, recordings.py, journal.py, admin.py — each defining an empty APIRouter with the right prefix/tags and NO endpoints yet — and register ALL routers in main.py now. Create app/routers/__init__.py.

conftest.py must provide fixtures every feature test can use without editing conftest: an app/client bound to a fresh database per test (SQLite file in tmp_path, or the PostgreSQL URL from OPENLUCID_DATABASE_URL when set — then drop_all/create_all or a fresh schema between tests so tests are isolated), a tmp DATA_DIR, and helpers/fixtures: register_user(client, email=..., password=...) returning (user_json, headers), two ready users alice and bob (each giving auth headers), and an admin (the first user). Document them in a docstring at the top of conftest.py.

scripts/pg_test.py: find initdb/pg_ctl under "C:/Program Files/PostgreSQL/<highest version>/bin" or on PATH; create a temporary cluster in a temp dir (trust auth, listen only on 127.0.0.1, a free port), start it, create a database, run pytest with OPENLUCID_DATABASE_URL=postgresql+psycopg://...; always stop the cluster and delete the temp dir afterwards (also on failure or Ctrl-C); pass extra args through to pytest; exit with pytest's exit code. It must never touch an existing PostgreSQL service or data directory.

Startup: in create_app, run migrations when OPENLUCID_AUTO_MIGRATE is true (tests may instead create tables directly — your choice, but both paths must work). Local mode generates and persists the secret key in DATA_DIR/secret_key; server mode refuses to start without OPENLUCID_SECRET_KEY (at least 32 chars).

Implement auth fully (register, login, token form, refresh with rotation and reuse detection, logout, rate limiting, first user becomes admin, consent rules) with thorough tests in tests/test_auth.py; the existing health tests must still pass.

Done when: "${PY} -m pytest -q" passes from ${BACKEND}, AND "${PY} scripts/pg_test.py -q" passes against a real temporary PostgreSQL, AND importing app.main works. Report honestly.`, { label: 'foundation', phase: 'Foundation', schema: SHARED_REQ })

log(`Foundation: ${foundation ? foundation.tests_passed + ' tests passed, ' + foundation.tests_failed + ' failed' : 'no result'}`)

// ---------------- Features (parallel, strict file ownership) ----------------
phase('Features')
const FEATURES = [
  { key: 'nights', owns: 'app/routers/nights.py and tests/test_nights.py', task: 'Implement /nights (list, idempotent create by client_id, get, patch, delete incl. recording files via app.storage if present — if storage.py does not exist yet, delete files under DATA_DIR/recordings/<user_id>/<night_id>/ directly), /nights/{id}/summary, PUT /nights/{id}/epochs (batch upsert, max 1000), GET epochs (index range, ordered), POST and GET /nights/{id}/events (batch, idempotent by client_id, max 500, details max 10 kB). Test every endpoint incl. 401, validation, idempotency, and another user getting 404.' },
  { key: 'recordings', owns: 'app/storage.py, app/routers/recordings.py and tests/test_recordings.py', task: 'Implement recording upload (multipart, streamed to disk in chunks, size limit -> 413 without leaving partial files, sha256 while streaming, filename sanitized, path traversal impossible), list, download (own only), delete (removes file). storage.py offers helpers also used when deleting nights and users: delete_night_files(user_id, night_id), delete_user_files(user_id). Test incl. oversize upload, path-traversal filenames, other user 404, file really removed from disk.' },
  { key: 'journal', owns: 'app/routers/journal.py and tests/test_journal.py', task: 'Implement /journal CRUD with optional night_id filter; night_id must belong to the same user (else 404); validation of lucid, vividness and text length. Test incl. other user 404 and night deletion setting night_id to null.' },
  { key: 'account', owns: 'app/routers/account.py, app/routers/admin.py, tests/test_account.py and tests/test_admin.py', task: 'Implement /me (get, patch), POST /me/password (revokes all refresh tokens), GET /me/export (complete JSON export with attachment header), DELETE /me (password required; deletes all rows and the recording files of that user under DATA_DIR/recordings/<user_id>/), and /admin/users (list with night_count, no other user data) plus PATCH (last-active-admin protection 409; non-admins 403). Test thoroughly, including that after DELETE /me the user cannot log in and their files are gone, and that export contains nights, epochs, events and journal.' },
  { key: 'deploy', owns: 'backend/Dockerfile, backend/docker-compose.yml, backend/.env.example, backend/.dockerignore, backend/README.md, and the root README.md section about the backend only', task: 'Write a production-minded Dockerfile (slim Python image, non-root user, runs migrations then uvicorn), docker-compose.yml with PostgreSQL 17 plus the API (named volumes for db and DATA_DIR, healthchecks, secret key from .env, no secrets committed), .env.example, .dockerignore (exclude .venv, data, __pycache__). Rewrite backend/README.md for beginners: local mode (venv + uvicorn, SQLite, nothing to install), server mode (docker compose), all environment variables (from SPEC), running tests on SQLite and on PostgreSQL (scripts/pg_test.py), creating the first (admin) account, and a clear privacy section (health data, consent, export and delete, the responsibility of server operators under GDPR; not legal advice). The Docker daemon is NOT running on this machine, so you cannot build the image — validate the compose file as far as possible without Docker (e.g. parse the YAML with Python) and state clearly in your report that the image was not built. Do not write code in app/.' },
]

const features = await parallel(FEATURES.map(f => () => agent(`${COMMON}
The foundation is built (read app/models.py, app/schemas.py, app/deps.py, app/security.py, tests/conftest.py before starting). Other agents are working IN PARALLEL on other files right now.
YOU OWN ONLY: ${f.owns}. Do NOT edit any other file. If you need a change in a file you don't own (e.g. a schema field, a model column, a dependency), do NOT make it — work around it if possible and list it precisely in shared_change_requests.
YOUR TASK: ${f.task}
Run only your own test files while working (other agents' tests may be mid-change): "${PY} -m pytest -q tests/<your test files>". Do not run scripts/pg_test.py (the integrator does that, one at a time).
Report honestly, including anything not finished.`, { label: 'feature:' + f.key, phase: 'Features', schema: SHARED_REQ })))

const featureReports = FEATURES.map((f, i) => ({ key: f.key, report: features[i] }))
for (const r of featureReports) log(`${r.key}: ${r.report ? r.report.tests_passed + ' passed, ' + r.report.tests_failed + ' failed, ' + r.report.shared_change_requests.length + ' shared requests' : 'FAILED / no result'}`)

// ---------------- Integrate ----------------
phase('Integrate')
const integration = await agent(`${COMMON}
YOUR TASK: integrate. Several agents built parts of the backend in parallel. Their reports (including requested changes to shared files) follow as JSON:
${JSON.stringify({ foundation, features: featureReports }, null, 1)}

1. Apply every reasonable shared_change_request (models, schemas, migrations, main, deps, conftest). If a model changes, update the Alembic migration so a fresh database matches the models exactly (check with an autogenerate diff or by comparing metadata) — there are no deployed databases yet, so editing the initial migration is fine.
2. Make sure deleting a night and deleting a user both remove recording files (use app.storage helpers consistently).
3. Run the FULL suite on SQLite ("${PY} -m pytest -q") and on PostgreSQL ("${PY} scripts/pg_test.py -q"). Fix every failure at its root cause (in whichever file). Do not weaken tests to make them pass; if a test is wrong per SPEC.md, fix the test and say so.
4. Start the real server once ("${PY} -m uvicorn app.main:app --port 8766" in the background, with OPENLUCID_DATA_DIR set to a temp dir), exercise register, login, create night, upload epochs, upload a small recording, summary, export, delete account with curl or Python, then stop that server by its PID.
Report: what you changed, final pass/fail counts for SQLite and PostgreSQL, the smoke test result, and remaining issues.`, { label: 'integrator', phase: 'Integrate', schema: {
  type: 'object',
  properties: {
    changes: { type: 'array', items: { type: 'string' } },
    sqlite: { type: 'object', properties: { passed: { type: 'integer' }, failed: { type: 'integer' } }, required: ['passed', 'failed'] },
    postgres: { type: 'object', properties: { passed: { type: 'integer' }, failed: { type: 'integer' }, ran: { type: 'boolean' } }, required: ['passed', 'failed', 'ran'] },
    smoke_test: { type: 'string' },
    remaining_issues: { type: 'array', items: { type: 'string' } },
  },
  required: ['changes', 'sqlite', 'postgres', 'smoke_test', 'remaining_issues'],
} })
log(`Integration: SQLite ${integration?.sqlite?.passed} passed / ${integration?.sqlite?.failed} failed; PostgreSQL ${integration?.postgres?.passed} passed / ${integration?.postgres?.failed} failed`)

// ---------------- Review (parallel lenses, read-only) ----------------
phase('Review')
const FINDINGS = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          title: { type: 'string' },
          severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
          file: { type: 'string' },
          evidence: { type: 'string', description: 'Concrete scenario: inputs or requests that produce the wrong behaviour' },
          suggested_fix: { type: 'string' },
        },
        required: ['title', 'severity', 'file', 'evidence', 'suggested_fix'],
      },
    },
  },
  required: ['findings'],
}
const LENSES = [
  { key: 'security', prompt: 'SECURITY: authentication and tokens (JWT validation, algorithm confusion, expiry, token type checks, refresh rotation and reuse detection, logout), password hashing, rate limiting bypasses, secret-key handling in local and server mode, upload handling (size limit, path traversal, trusting content types, partial files), error messages leaking info (user enumeration), CORS, injection, mass assignment via schemas (e.g. setting role through PATCH /me).' },
  { key: 'isolation', prompt: 'USER ISOLATION AND PRIVACY: can user B read, modify, delete, list, export, summarize, download or attach to (e.g. journal night_id, recordings) anything of user A through ANY endpoint or query parameter? Does the admin API expose health data of other users? Do DELETE /me and DELETE night really remove all rows AND files (check cascades on SQLite, where foreign keys need PRAGMA foreign_keys=ON)? Does the export contain everything of the user and nothing of others? Are passwords, tokens or EEG ever logged?' },
  { key: 'contract', prompt: 'API CONTRACT AND CORRECTNESS: compare every endpoint, status code, request and response shape, validation rule, pagination, ordering, idempotency (nights client_id, events client_id, epochs upsert), and timezone handling (aware UTC in and out, on both SQLite and PostgreSQL) against SPEC.md. Check that the Alembic migration matches the models exactly on both databases. Check races in idempotent creates (unique constraint plus IntegrityError handling).' },
  { key: 'operations', prompt: 'OPERATIONS AND DEVELOPER EXPERIENCE: following backend/README.md from scratch, does local mode work (venv, install, run, first admin)? Are the Dockerfile and docker-compose correct (non-root, migrations, volumes, healthchecks, env vars matching config.py, no secrets)? Does scripts/pg_test.py clean up in every path and never touch an existing PostgreSQL? Are requirements complete and sensibly pinned? Does startup migration work on an existing database (run it twice)? Are large uploads streamed rather than read into memory?' },
]
const reviews = await parallel(LENSES.map(l => () => agent(`${COMMON}
YOUR TASK: review the backend (read-only — do NOT edit repository files). Lens: ${l.prompt}
You may run tests and small experiments (e.g. a throwaway script in a temp dir, or pytest) to confirm a problem. Report only REAL problems you are confident about, each with a concrete scenario as evidence. Skip style nits. If an area is fine, say nothing about it.`, { label: 'review:' + l.key, phase: 'Review', schema: FINDINGS })))

const allFindings = reviews.filter(Boolean).flatMap((r, i) => r.findings.map(f => ({ ...f, lens: LENSES[i].key })))
log(`Review: ${allFindings.length} findings (${allFindings.filter(f => f.severity === 'critical' || f.severity === 'high').length} critical or high)`)

// ---------------- Fix ----------------
phase('Fix')
let fixReport = { fixed: [], rejected: [], sqlite: null, postgres: null }
if (allFindings.length) {
  fixReport = await agent(`${COMMON}
YOUR TASK: fix the review findings below. For EACH finding: first try to reproduce it with a test (add it to the matching tests/test_*.py). If the test fails, fix the code until it passes and keep the test. If you cannot reproduce it or it contradicts SPEC.md, do not change code; mark it rejected with the reason. Fix root causes, not symptoms.
Findings (JSON): ${JSON.stringify(allFindings, null, 1)}
At the end run the FULL suite on SQLite ("${PY} -m pytest -q") and PostgreSQL ("${PY} scripts/pg_test.py -q"); both must pass.`, { label: 'fixer', phase: 'Fix', schema: {
    type: 'object',
    properties: {
      fixed: { type: 'array', items: { type: 'object', properties: { title: { type: 'string' }, test: { type: 'string' }, change: { type: 'string' } }, required: ['title', 'test', 'change'] } },
      rejected: { type: 'array', items: { type: 'object', properties: { title: { type: 'string' }, reason: { type: 'string' } }, required: ['title', 'reason'] } },
      sqlite: { type: 'object', properties: { passed: { type: 'integer' }, failed: { type: 'integer' } }, required: ['passed', 'failed'] },
      postgres: { type: 'object', properties: { passed: { type: 'integer' }, failed: { type: 'integer' } }, required: ['passed', 'failed'] },
    },
    required: ['fixed', 'rejected', 'sqlite', 'postgres'],
  } })
  log(`Fix: ${fixReport?.fixed?.length || 0} fixed, ${fixReport?.rejected?.length || 0} rejected`)
}

// ---------------- Verify from scratch ----------------
phase('Verify')
const verify = await agent(`${COMMON}
YOUR TASK: independent final verification, as a newcomer would do it. Do NOT edit any repository files (report problems instead).
1. Create a brand-new virtual environment in a temp directory (not backend/.venv), install backend/requirements.txt into it, and run the full test suite with it on SQLite and on PostgreSQL (scripts/pg_test.py with that venv's python).
2. Following ONLY backend/README.md, start the server in local mode with a temp OPENLUCID_DATA_DIR, and run a complete user story with HTTP requests: register two users (the first becomes admin), login, refresh, create a night with the same client_id twice (same night), upload 3 epochs and re-upload one (upsert), post events twice with the same client_ids (no duplicates), upload a small file as a recording and download it (same sha256), write a journal entry, get the summary and the export, check that user 2 gets 404 for user 1's night, recording and journal entry, check that the admin list shows night_count but no health data, delete user 1's account and confirm their recording file is gone from disk and login fails. Stop the server by its PID.
3. Start the server twice against the same data dir (startup migration must be idempotent).
Report every step's result honestly.`, { label: 'verify', phase: 'Verify', schema: {
  type: 'object',
  properties: {
    fresh_install_ok: { type: 'boolean' },
    sqlite: { type: 'object', properties: { passed: { type: 'integer' }, failed: { type: 'integer' } }, required: ['passed', 'failed'] },
    postgres: { type: 'object', properties: { passed: { type: 'integer' }, failed: { type: 'integer' } }, required: ['passed', 'failed'] },
    story_steps: { type: 'array', items: { type: 'object', properties: { step: { type: 'string' }, ok: { type: 'boolean' }, note: { type: 'string' } }, required: ['step', 'ok', 'note'] } },
    restart_idempotent: { type: 'boolean' },
    problems: { type: 'array', items: { type: 'string' } },
  },
  required: ['fresh_install_ok', 'sqlite', 'postgres', 'story_steps', 'restart_idempotent', 'problems'],
} })

return { foundation, features: featureReports, integration, findings: allFindings, fixReport, verify }
