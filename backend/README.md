# Backend: the Diary Keeper

A small Python server (FastAPI) that runs on your own computer and writes down everything about your night.

## Start it

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

Bonus: <http://localhost:8000/docs> is a free, automatically written manual of every endpoint, where you can try them out.

## Run the tests

```bash
pytest
```

## Phone instead of laptop?

`localhost` means "this same computer". If the app runs on a phone, start the server so other devices on your home Wi-Fi can reach it, and use the laptop's IP address in the app's settings:

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000
```
