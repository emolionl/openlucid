---
title: "Day 2: the Diary Keeper grows up"
date: 2026-11-01T16:00:00+01:00
description: "The backend becomes a real multi-user server that also runs on a laptop: accounts, nights, epochs, events, journal and recordings, built and reviewed by a team of AI agents and tested on SQLite and PostgreSQL."
weight: 6
outcome: "Done"
tldr:
  - "One backend, two ways to run it: SQLite on a laptop (nothing to install), PostgreSQL on a server (Docker)."
  - "Accounts with consent, secure sign-in, export and delete; every user sees only their own data."
  - "Raw EEG goes into files, not into the database; the app can upload twice without creating duplicates."
  - "Built by 13 AI agents in six phases; 14 review findings, each proven with a failing test and fixed; 381 tests pass."
---

## Why a server, if everything is local?

Because the same code can then run in two places. On your own laptop it uses **SQLite**: one file, nothing to install. On a server it uses **PostgreSQL** in Docker, for a few people or a research group. The app only needs to know the address, in its settings.

Local stays the default. A server is something you choose, and it comes with responsibilities (see *Health data* below).

## What the Diary Keeper can do now

- **Accounts:** register (with consent to the privacy text), sign in, change password, export everything as one file, delete your account including every file. The first account becomes the admin; an admin manages accounts but cannot see anyone's sleep data.
- **Nights, epochs and events:** a night with its device, 30-second epochs (sleep stage, contact per sensor), and events such as a sound cue, an eye signal or waking up.
- **Dream journal**, optionally linked to a night.
- **Recordings:** raw EEG files (EDF) are stored as files, never as database rows. One night is millions of samples; a database is the wrong place for them.
- **Safe to sync twice.** The app records offline at night and uploads later. If an upload is repeated, the server recognises it (by an id the app chooses) instead of storing a duplicate.

## How it was built: a team of agents

We wrote a specification first ([backend/SPEC.md](https://github.com/emolionl/openlucid/blob/main/backend/SPEC.md)): every table, every endpoint, every security rule, and which agent owns which file. Then:

| Phase | Agents | What happened |
|---|---|---|
| Foundation | 1 | Configuration, database layer, all tables, sign-in security, migrations, test setup |
| Features | 5 at once | Nights and epochs, recordings, journal, account and admin, Docker and documentation. Each agent could only edit its own files |
| Integration | 1 | Put it together: 325 tests passing on SQLite and on a real PostgreSQL, plus a live server test |
| Review | 4 at once | Security, user isolation and privacy, the API contract, operations |
| Fixes | 1 | Every finding first reproduced with a failing test, then fixed |
| Final check | 1 | A fresh install following only the README, and a 20-step user story |

**The review found 14 real problems**, for example:

- the protection against password guessing could be bypassed with many requests at the same moment,
- two people registering at the same moment on an empty server could both become admin,
- a stray character (NUL) in a text field crashed PostgreSQL but not SQLite,
- running the tests with the wrong setting in your shell could empty a real database.

All 14 were reproduced with a test that failed, then fixed. **None were rejected.** Final count: **381 tests on SQLite, 380 on PostgreSQL** (one test only makes sense on SQLite).

**Lesson:** tests written by the builder catch what the builder thought of. A separate reviewer with a different question ("can user B see user A's night?") finds what the builder didn't.

## Health data

EEG combined with sleep is health data, a special category under the GDPR. If you run a server for **other** people, you need their explicit consent, a privacy statement, secure storage, and a way for them to export and delete their data. The software provides the last two; the rest is the responsibility of whoever runs the server. Collecting other people's nights for **research** also needs ethics approval. For now we use the server only with our own nights and test accounts.

## Not done yet

- The Docker image is written and checked, but not built: Docker wasn't running on this computer.
- The app doesn't talk to the new backend yet. That's the next checkpoint: record a whole night and sync it.

## Code at the end of the day

```bash
git checkout checkpoint-02
cd backend
python -m venv .venv
.venv\Scripts\activate          # macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Then open <http://localhost:8000/docs> and register the first account.
