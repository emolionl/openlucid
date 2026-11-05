---
title: "Getting started"
description: "Download the app, or run OpenLucid from the code: the app, the Diary Keeper server and the tools."
weight: 1
---

## The quick way: download

On Windows, download the app from the [download page](../../download/), unzip it and double-click `openlucid.exe`. Nothing else is needed to try it with Fake Moose or record a night with a Muse.

## How it's built

**The app is one Flutter codebase**, not rewritten per platform — Windows today, Android/iPhone and iPad/Mac/Linux from the exact same code as each is tested and shipped.

**The Diary Keeper is Python**, on purpose: sleep-staging and EEG-analysis models — [YASA](https://github.com/raphaelvallat/yasa), the lab's own `ezscore-f` and `eegFloss` — are published in Python first, so the server can call them directly, no porting required.

```
Flutter app   →  Diary Keeper (Python)  →  SQLite file            (solo, default)
Flutter apps  →  Diary Keeper (Python)  →  PostgreSQL in Docker   (a few people, opt-in)
```

Same code either way — see "The Diary Keeper" below for how to switch.

## From the code

OpenLucid has these parts:

| Part | Folder | What it does |
|---|---|---|
| The app | `frontend/desktop/` | Connects to the headband, shows the signal, records the night (later: plays the sound cue) |
| The Diary Keeper | `backend/` | An optional server on your own computer: accounts, nights, journal |
| The morning view | `frontend/web/` | Your night and dream journal in the browser |
| Tools | `tools/` | Python scripts that check recordings with MNE, the way researchers do |

### The app

Install [Flutter](https://docs.flutter.dev/get-started/install), then:

```bash
cd frontend/desktop
flutter run -d windows        # or: -d android, -d macos, -d linux
```

To make a stand-alone Windows build like the download: `flutter build windows --release`. The result is in `build/windows/x64/runner/Release`.

### The Diary Keeper

You need Python 3.11 or newer.

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate        # macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Open <http://localhost:8000/health>. It should say *"The Diary Keeper is awake."* With Docker and PostgreSQL instead: see `backend/README.md`.

### Check a recorded night

```bash
python -m venv tools/.venv
tools\.venv\Scripts\activate
pip install -r tools/requirements.txt
python tools/check_night.py "<your night's folder>"
```

The night's folder is shown on the Nights screen in the app (the folder icon opens it).
