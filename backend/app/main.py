"""The Diary Keeper: a small local server that writes down everything about your night.

Checkpoint 00 only proves it is alive: the apps call /health and get a wave back.
"""

from datetime import datetime, timezone

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(
    title="Lucid — the Diary Keeper",
    description="Local API that logs sleep sessions, epochs, events and dream journals.",
    version="0.0.1",
)

# The Vue web app runs on its own port during development, so the browser needs permission to talk to us.
# Everything stays on this computer: only localhost origins are allowed.
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health() -> dict:
    """Say hello. The Diary Keeper never sleeps, and it always tells you the time."""
    return {
        "status": "awake",
        "message": "The Diary Keeper is awake.",
        "time": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
