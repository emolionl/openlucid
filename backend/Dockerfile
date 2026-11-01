# The Diary Keeper as a server: a slim Python image that runs as a normal (non-root) user.
# Build and start it with docker-compose.yml next to this file: `docker compose up -d`.
FROM python:3.13-slim

# No .pyc files in the image, log lines appear immediately, no pip cache or version check.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Dependencies first, so Docker can reuse this layer when only the code changes.
COPY requirements.txt .
RUN pip install -r requirements.txt

# A user without a password or a home login shell, and a DATA_DIR it owns.
# A new named volume mounted on /data starts out with this owner.
RUN groupadd --system --gid 10001 openlucid \
    && useradd --system --uid 10001 --gid openlucid --no-create-home --shell /usr/sbin/nologin openlucid \
    && mkdir -p /data \
    && chown openlucid:openlucid /data

COPY --chown=root:root app ./app
COPY --chown=root:root alembic ./alembic
COPY --chown=root:root alembic.ini .

# Server mode by default; the secret key and database URL come from docker-compose.yml / your environment.
# The migrations run once below, before the server starts, so the app itself does not need to run them.
ENV OPENLUCID_MODE=server \
    OPENLUCID_DATA_DIR=/data \
    OPENLUCID_AUTO_MIGRATE=false

USER openlucid
EXPOSE 8000

# python:slim has no curl, so the health check asks /health with Python itself.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD ["python", "-c", "import urllib.request, sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=4).status == 200 else 1)"]

# 1. bring the database up to date, 2. replace the shell with uvicorn (so it receives stop signals).
# One worker on purpose: the login rate limiter lives in memory, and several workers would each count separately.
# --proxy-headers: behind a reverse proxy, uvicorn trusts X-Forwarded-For only from FORWARDED_ALLOW_IPS.
CMD ["sh", "-c", "alembic upgrade head && exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers --no-server-header"]
