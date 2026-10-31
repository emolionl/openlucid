---
title: "Getting started"
description: "Make the app and the Diary Keeper wave at each other."
weight: 1
---

OpenLucid has three parts:

| Part | Folder | What it does |
|---|---|---|
| The Diary Keeper | `backend/` | A small server on your laptop that writes down everything about your night |
| The app | `frontend/desktop/` | Connects to the headband, listens all night, plays the sound cue |
| The morning view | `frontend/web/` | Your night's report and dream journal in the browser |

## 1. Start the Diary Keeper

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate        # macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Open <http://localhost:8000/health>. It should say *"The Diary Keeper is awake."*

## 2. Wave from the app

```bash
cd frontend/desktop
flutter run -d windows
```

Press **Wave at the Diary Keeper**.

## 3. Or wave from the browser

```bash
cd frontend/web
npm install
npm run dev
```

If you get an answer, you've finished checkpoint 00. 🎉
