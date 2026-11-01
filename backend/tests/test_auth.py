"""Tests for /auth/*: register, login, token form, refresh rotation, logout, rate limits and the auth deps."""

import hashlib
import threading
import time
import uuid
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

import jwt
import pytest
from sqlalchemy import select

from app import security
from app.routers import auth
from app.deps import AdminUser, CurrentUser
from app.models import RefreshToken, User
from app.security import create_access_token
from conftest import DEFAULT_PASSWORD

WRONG_CREDENTIALS = "Wrong email or password."


def registration(email="dreamer@example.com", password=DEFAULT_PASSWORD, **extra) -> dict:
    body = {"email": email, "password": password, "accept_consent": True, "consent_version": "2026-11"}
    body.update(extra)
    return body


def login(client, email, password=DEFAULT_PASSWORD):
    return client.post("/auth/login", json={"email": email, "password": password})


def bearer(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def whoami(app):
    """Add two tiny protected routes to the app, to test the auth dependencies on their own."""

    def me(user: CurrentUser) -> dict:
        return {"id": str(user.id), "role": user.role}

    def admin_only(user: AdminUser) -> dict:
        return {"id": str(user.id)}

    app.router.add_api_route("/_test/whoami", me, methods=["GET"])
    app.router.add_api_route("/_test/admin", admin_only, methods=["GET"])
    return "/_test/whoami"


def secret_of(app) -> str:
    """The app's signing key (the same file-backed key the app itself uses in local mode)."""
    return security.resolve_secret_key(app.state.settings)


def set_active(db, user_id: str, active: bool) -> None:
    user = db.get(User, uuid.UUID(user_id))
    user.is_active = active
    db.commit()


# --- register -----------------------------------------------------------------------------


def test_register_returns_user_and_tokens(client):
    response = client.post("/auth/register", json=registration(display_name="Dreamer"))
    assert response.status_code == 201
    body = response.json()
    assert body["token_type"] == "bearer"
    assert body["access_token"] and body["refresh_token"]
    user = body["user"]
    assert user["email"] == "dreamer@example.com"
    assert user["display_name"] == "Dreamer"
    assert user["is_active"] is True
    assert user["consent_version"] == "2026-11"
    assert "password_hash" not in user and "password" not in user
    consent_at = datetime.fromisoformat(user["consent_at"].replace("Z", "+00:00"))
    assert abs(datetime.now(timezone.utc) - consent_at) < timedelta(minutes=1)


def test_first_user_is_admin_and_later_users_are_not(client):
    first = client.post("/auth/register", json=registration("first@example.com")).json()["user"]
    second = client.post("/auth/register", json=registration("second@example.com")).json()["user"]
    assert first["role"] == "admin"
    assert second["role"] == "user"


def test_parallel_first_registrations_make_exactly_one_admin(client, monkeypatch):
    real_hash_password = auth.hash_password

    def slow_hash_password(password: str) -> str:
        time.sleep(0.2)  # every registration is busy at the same time, as on a just-started server
        return real_hash_password(password)

    monkeypatch.setattr(auth, "hash_password", slow_hash_password)
    with ThreadPoolExecutor(max_workers=8) as pool:
        responses = list(
            pool.map(lambda n: client.post("/auth/register", json=registration(f"early{n}@example.com")), range(8))
        )
    assert [response.status_code for response in responses] == [201] * 8
    roles = Counter(response.json()["user"]["role"] for response in responses)
    assert roles == {"admin": 1, "user": 7}


@pytest.mark.parametrize(
    "changes",
    [{"display_name": "Al" + chr(0)}, {"email": "a" + chr(0) + "@example.com"}, {"password": "long password" + chr(0)}],
)
def test_register_refuses_nul_characters(client, changes):
    assert client.post("/auth/register", json=registration(**changes)).status_code == 422


def test_login_refuses_nul_characters(client, alice):
    assert login(client, alice.email + chr(0)).status_code == 422


def test_token_form_with_nul_in_username_is_just_wrong(client, alice):
    response = client.post("/auth/token", data={"username": alice.email + chr(0), "password": DEFAULT_PASSWORD})
    assert response.status_code == 401


def test_register_stores_email_lowercased(client):
    response = client.post("/auth/register", json=registration("  Mixed.Case@Example.COM "))
    assert response.json()["user"]["email"] == "mixed.case@example.com"


def test_register_same_email_twice_is_409_even_with_other_case(client):
    assert client.post("/auth/register", json=registration("taken@example.com")).status_code == 201
    response = client.post("/auth/register", json=registration("TAKEN@example.com"))
    assert response.status_code == 409
    assert set(response.json()) == {"detail"}


def test_register_stores_only_an_argon2_hash(client, db):
    client.post("/auth/register", json=registration("hash@example.com"))
    user = db.scalar(select(User).where(User.email == "hash@example.com"))
    assert user.password_hash.startswith("$argon2")
    assert DEFAULT_PASSWORD not in user.password_hash


@pytest.mark.parametrize(
    "changes",
    [
        {"password": "too-short"},
        {"email": "not-an-email"},
        {"email": "a" * 250 + "@example.com"},
        {"accept_consent": False},
        {"display_name": "x" * 101},
    ],
    ids=["short-password", "bad-email", "long-email", "consent-not-accepted", "long-display-name"],
)
def test_register_validation_errors(client, changes):
    assert client.post("/auth/register", json=registration(**changes)).status_code == 422


def test_register_without_consent_field_is_422(client):
    body = registration()
    del body["accept_consent"]
    assert client.post("/auth/register", json=body).status_code == 422


def test_register_with_old_consent_version_is_422(client):
    response = client.post("/auth/register", json=registration(consent_version="2020-01"))
    assert response.status_code == 422
    assert "2026-11" in response.json()["detail"]


def test_register_follows_configured_consent_version(make_client):
    client = make_client(consent_version="2027-01")
    assert client.post("/auth/register", json=registration()).status_code == 422
    response = client.post("/auth/register", json=registration(consent_version="2027-01"))
    assert response.status_code == 201
    assert response.json()["user"]["consent_version"] == "2027-01"


def test_register_when_registration_closed_is_403(make_client):
    client = make_client(allow_registration=False)
    response = client.post("/auth/register", json=registration())
    assert response.status_code == 403


# --- login --------------------------------------------------------------------------------


def test_login_returns_user_and_working_tokens(client, alice, whoami):
    response = login(client, alice.email)
    assert response.status_code == 200
    body = response.json()
    assert body["user"]["id"] == alice.id
    assert body["token_type"] == "bearer"
    assert client.get(whoami, headers=bearer(body["access_token"])).json()["id"] == alice.id
    assert client.post("/auth/refresh", json={"refresh_token": body["refresh_token"]}).status_code == 200


def test_login_ignores_email_case_and_spaces(client, alice):
    assert login(client, " ALICE@example.com ").status_code == 200


def test_wrong_password_and_unknown_email_look_the_same(client, alice):
    wrong_password = login(client, alice.email, "not the password")
    unknown_email = login(client, "nobody@example.com")
    assert wrong_password.status_code == unknown_email.status_code == 401
    assert wrong_password.json() == unknown_email.json() == {"detail": WRONG_CREDENTIALS}


def test_login_validation_error(client):
    assert client.post("/auth/login", json={"email": "alice@example.com"}).status_code == 422


def test_inactive_user_cannot_log_in(client, alice, db):
    set_active(db, alice.id, False)
    assert login(client, alice.email).status_code == 403
    # A wrong password still says "wrong", so the account state is not revealed to guessers.
    assert login(client, alice.email, "not the password").status_code == 401


# --- rate limiting ------------------------------------------------------------------------


def test_ten_failures_block_that_email_even_with_the_right_password(client, alice, bob):
    for _ in range(10):
        assert login(client, alice.email, "wrong password!").status_code == 401
    blocked = login(client, alice.email)
    assert blocked.status_code == 429
    assert int(blocked.headers["Retry-After"]) > 0
    assert login(client, bob.email).status_code == 200


def test_thirty_failures_block_the_client_ip(client, alice):
    for attempt in range(30):
        assert login(client, f"guess{attempt}@example.com", "wrong password!").status_code == 401
    assert login(client, alice.email).status_code == 429


def test_successful_login_clears_the_email_counter(client, alice):
    for _ in range(9):
        login(client, alice.email, "wrong password!")
    assert login(client, alice.email).status_code == 200
    for _ in range(9):
        login(client, alice.email, "wrong password!")
    assert login(client, alice.email).status_code == 200


def test_block_ends_after_fifteen_minutes(client, app, alice):
    clock = [1000.0]
    guard = app.state.login_guard
    guard.by_email.clock = guard.by_ip.clock = lambda: clock[0]
    for _ in range(10):
        login(client, alice.email, "wrong password!")
    assert login(client, alice.email).status_code == 429
    clock[0] += 15 * 60 + 1
    assert login(client, alice.email).status_code == 200


def test_token_form_is_rate_limited_too(client, alice):
    for _ in range(10):
        client.post("/auth/token", data={"username": alice.email, "password": "wrong password!"})
    response = client.post("/auth/token", data={"username": alice.email, "password": DEFAULT_PASSWORD})
    assert response.status_code == 429


def slow_wrong_passwords(monkeypatch, module) -> list[int]:
    """Make every password check in `module` slow and wrong; returns a list that grows by one per check."""
    checks = []
    lock = threading.Lock()

    def slow_verify(_password_hash, _password) -> bool:
        with lock:
            checks.append(1)
        time.sleep(0.3)  # long enough for every parallel request to arrive while the first checks still run
        return False

    monkeypatch.setattr(module, "verify_password", slow_verify)
    return checks


def test_parallel_wrong_logins_cannot_get_past_the_limit(client, alice, monkeypatch):
    checks = slow_wrong_passwords(monkeypatch, auth)
    with ThreadPoolExecutor(max_workers=30) as pool:
        statuses = Counter(pool.map(lambda _: login(client, alice.email, "wrong password!").status_code, range(30)))
    assert len(checks) == 10
    assert statuses == {401: 10, 429: 20}


def test_parallel_logins_for_many_emails_respect_the_ip_limit(client, monkeypatch):
    checks = slow_wrong_passwords(monkeypatch, auth)
    with ThreadPoolExecutor(max_workers=40) as pool:
        statuses = Counter(
            pool.map(lambda n: login(client, f"guess{n}@example.com", "wrong password!").status_code, range(40))
        )
    assert len(checks) == 30
    assert statuses == {401: 30, 429: 10}


def test_a_right_password_does_not_count_against_the_ip(client, alice):
    for _ in range(40):
        assert login(client, alice.email).status_code == 200


# --- OAuth2 token form --------------------------------------------------------------------


def test_token_form_returns_access_token(client, alice, whoami):
    response = client.post("/auth/token", data={"username": alice.email, "password": DEFAULT_PASSWORD})
    assert response.status_code == 200
    body = response.json()
    assert set(body) == {"access_token", "token_type"}
    assert body["token_type"] == "bearer"
    assert client.get(whoami, headers=bearer(body["access_token"])).status_code == 200


def test_token_form_wrong_password_is_401(client, alice):
    response = client.post("/auth/token", data={"username": alice.email, "password": "nope"})
    assert response.status_code == 401
    assert response.json() == {"detail": WRONG_CREDENTIALS}


def test_token_form_missing_fields_is_422(client):
    assert client.post("/auth/token", data={"username": "alice@example.com"}).status_code == 422


# --- access tokens and the auth dependencies ----------------------------------------------


def test_access_token_claims(app, alice):
    claims = jwt.decode(alice.headers["Authorization"].split()[1], secret_of(app), algorithms=["HS256"])
    assert claims["sub"] == alice.id
    assert claims["type"] == "access"
    assert claims["exp"] - claims["iat"] == 15 * 60


def test_protected_route_with_valid_token(client, alice, whoami):
    assert client.get(whoami, headers=alice.headers).json() == {"id": alice.id, "role": "user"}


@pytest.mark.parametrize("headers", [{}, {"Authorization": "Bearer not-a-jwt"}, {"Authorization": "Basic abc"}])
def test_missing_or_broken_token_is_401_with_bearer_challenge(client, whoami, headers):
    response = client.get(whoami, headers=headers)
    assert response.status_code == 401
    assert response.headers["WWW-Authenticate"] == "Bearer"


def test_expired_token_is_401(client, app, alice, whoami):
    token = create_access_token(uuid.UUID(alice.id), secret_of(app), minutes=-1)
    assert client.get(whoami, headers=bearer(token)).status_code == 401


def test_token_signed_with_another_key_is_401(client, alice, whoami):
    token = create_access_token(uuid.UUID(alice.id), "x" * 48, minutes=15)
    assert client.get(whoami, headers=bearer(token)).status_code == 401


def test_token_of_wrong_type_is_401(client, app, alice, whoami):
    now = datetime.now(timezone.utc)
    claims = {"sub": alice.id, "iat": now, "exp": now + timedelta(minutes=5), "type": "refresh"}
    token = jwt.encode(claims, secret_of(app), algorithm="HS256")
    assert client.get(whoami, headers=bearer(token)).status_code == 401


def test_token_with_bad_subject_is_401(client, app, whoami):
    now = datetime.now(timezone.utc)
    claims = {"sub": "not-a-uuid", "iat": now, "exp": now + timedelta(minutes=5), "type": "access"}
    token = jwt.encode(claims, secret_of(app), algorithm="HS256")
    assert client.get(whoami, headers=bearer(token)).status_code == 401


def test_token_of_deleted_user_is_401(client, alice, db, whoami):
    db.delete(db.get(User, uuid.UUID(alice.id)))
    db.commit()
    assert client.get(whoami, headers=alice.headers).status_code == 401


def test_token_of_deactivated_user_is_403(client, alice, db, whoami):
    set_active(db, alice.id, False)
    assert client.get(whoami, headers=alice.headers).status_code == 403


def test_admin_dependency(client, admin, alice, whoami):
    assert client.get("/_test/admin", headers=admin.headers).status_code == 200
    assert client.get("/_test/admin", headers=alice.headers).status_code == 403
    assert client.get("/_test/admin").status_code == 401


# --- refresh ------------------------------------------------------------------------------


def refresh(client, token):
    return client.post("/auth/refresh", json={"refresh_token": token})


def test_refresh_rotates_the_token(client, alice, whoami):
    response = refresh(client, alice.refresh_token)
    assert response.status_code == 200
    body = response.json()
    assert body["token_type"] == "bearer"
    assert body["refresh_token"] != alice.refresh_token
    assert client.get(whoami, headers=bearer(body["access_token"])).json()["id"] == alice.id
    assert refresh(client, body["refresh_token"]).status_code == 200


def test_refresh_links_old_token_to_its_replacement(client, alice, db):
    new_token = refresh(client, alice.refresh_token).json()["refresh_token"]
    old = db.scalar(select(RefreshToken).where(RefreshToken.token_hash == security.hash_token(alice.refresh_token)))
    new = db.scalar(select(RefreshToken).where(RefreshToken.token_hash == security.hash_token(new_token)))
    assert old.revoked_at is not None
    assert old.replaced_by_id == new.id
    assert new.revoked_at is None


def test_reusing_a_rotated_token_ends_every_session(client, alice):
    rotated = refresh(client, alice.refresh_token).json()["refresh_token"]
    other_device = login(client, alice.email).json()["refresh_token"]
    assert refresh(client, alice.refresh_token).status_code == 401  # the stolen old token
    assert refresh(client, rotated).status_code == 401
    assert refresh(client, other_device).status_code == 401


def test_reuse_detection_only_touches_that_user(client, alice, bob):
    refresh(client, alice.refresh_token)
    refresh(client, alice.refresh_token)
    assert refresh(client, bob.refresh_token).status_code == 200


def test_unknown_refresh_token_is_401(client):
    assert refresh(client, "made-up-token").status_code == 401


def test_expired_refresh_token_is_401(client, alice, db):
    row = db.scalar(select(RefreshToken).where(RefreshToken.token_hash == security.hash_token(alice.refresh_token)))
    row.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
    db.commit()
    assert refresh(client, alice.refresh_token).status_code == 401


def test_refresh_for_deactivated_user_is_403(client, alice, db):
    set_active(db, alice.id, False)
    assert refresh(client, alice.refresh_token).status_code == 403


def test_refresh_validation_error(client):
    assert client.post("/auth/refresh", json={}).status_code == 422


def test_refresh_lifetime_follows_settings(make_client, db):
    client = make_client(refresh_token_days=2)
    token = client.post("/auth/register", json=registration()).json()["refresh_token"]
    row = db.scalar(select(RefreshToken).where(RefreshToken.token_hash == security.hash_token(token)))
    assert timedelta(days=2) - timedelta(minutes=1) < row.expires_at - row.created_at <= timedelta(days=2)


def test_only_the_hash_of_refresh_tokens_is_stored(client, alice, db):
    stored = set(db.scalars(select(RefreshToken.token_hash)))
    assert hashlib.sha256(alice.refresh_token.encode()).hexdigest() in stored
    assert alice.refresh_token not in stored


# --- logout -------------------------------------------------------------------------------


def test_logout_ends_only_that_session(client, alice):
    other_device = login(client, alice.email).json()["refresh_token"]
    response = client.post("/auth/logout", json={"refresh_token": alice.refresh_token})
    assert response.status_code == 204
    assert response.content == b""
    assert refresh(client, other_device).status_code == 200


def test_reusing_a_logged_out_token_ends_every_session(client, alice):
    """SPEC.md: reusing any revoked refresh token looks like theft, also one that was logged out."""
    other_device = login(client, alice.email).json()["refresh_token"]
    client.post("/auth/logout", json={"refresh_token": alice.refresh_token})
    assert refresh(client, alice.refresh_token).status_code == 401
    assert refresh(client, other_device).status_code == 401


def test_reusing_a_token_ended_by_a_password_change_ends_new_sessions_too(client, alice):
    changed = client.post(
        "/me/password",
        json={"current_password": alice.password, "new_password": "a brand new password"},
        headers=alice.headers,
    )
    assert changed.status_code == 204
    new_session = login(client, alice.email, "a brand new password").json()["refresh_token"]
    assert refresh(client, alice.refresh_token).status_code == 401
    assert refresh(client, new_session).status_code == 401


def test_logout_is_idempotent(client, alice):
    for _ in range(2):
        assert client.post("/auth/logout", json={"refresh_token": alice.refresh_token}).status_code == 204
    assert client.post("/auth/logout", json={"refresh_token": "unknown"}).status_code == 204


def test_logout_validation_error(client):
    assert client.post("/auth/logout", json={}).status_code == 422
