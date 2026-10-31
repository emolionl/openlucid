from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health_says_awake():
    response = client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "awake"
    assert "time" in body


def test_web_app_on_localhost_is_allowed():
    response = client.get("/health", headers={"Origin": "http://localhost:5173"})
    assert response.headers["access-control-allow-origin"] == "http://localhost:5173"


def test_other_websites_are_not_allowed():
    response = client.get("/health", headers={"Origin": "https://example.com"})
    assert "access-control-allow-origin" not in response.headers
