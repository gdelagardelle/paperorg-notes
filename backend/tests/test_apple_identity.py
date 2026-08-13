"""Acceptance tests for the verified Apple identity foundation.

These tests intentionally define the backend contract before implementation.
They never contact Apple: the identity-token verifier is replaced with a
verified subject, so the endpoint must consume that verified result rather
than trust a subject supplied by the client.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pytest
from fastapi.testclient import TestClient

from config import settings


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "database_url", "")
    monkeypatch.setattr(settings, "free_included_minutes_enabled", False, raising=False)

    import database
    import main

    monkeypatch.setattr(database, "DB_PATH", tmp_path / "test.db")
    monkeypatch.setattr(
        main,
        "verify_apple_identity_token",
        lambda token: "apple-subject-verified-by-server",
        raising=False,
    )

    with TestClient(main.app) as test_client:
        yield test_client


def sign_in(client, device_id):
    response = client.post(
        "/v1/auth/apple",
        json={"identity_token": "signed-token-from-apple", "device_id": device_id},
    )
    assert response.status_code == 200, response.text
    return response.json()


def test_verified_apple_subject_is_stable_across_devices(client):
    first = sign_in(client, "device-one-12345")
    second = sign_in(client, "device-two-12345")

    assert first["user_id"] == second["user_id"]
    assert first["minutes_limit"] == 0
    assert second["minutes_limit"] == 0


def test_apple_identity_token_grants_no_free_credit_while_flag_is_off(client):
    signed_in = sign_in(client, "device-one-12345")
    response = client.get(
        "/v1/usage",
        headers={"Authorization": f"Bearer {signed_in['access_token']}"},
    )

    assert response.status_code == 200
    assert response.json()["is_pro"] is False
    assert response.json()["minutes_limit"] == 0
