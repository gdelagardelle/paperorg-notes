"""Dual-stack auth tests: legacy HS256 tokens keep working, Platform RS256
tokens are validated against a (stubbed) JWKS and metered via the Platform."""

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import jwt as pyjwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

from config import settings


@pytest.fixture(scope="session")
def platform_keypair():
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    return key, key.public_key()


@pytest.fixture(autouse=True)
def platform_config(monkeypatch, platform_keypair):
    import platform_client

    monkeypatch.setattr(settings, "platform_api_url", "https://poplatform.test")
    _, public_key = platform_keypair
    monkeypatch.setitem(platform_client._jwks_cache, "keys", {"test-kid": public_key})
    monkeypatch.setitem(platform_client._jwks_cache, "fetched_at", time.time())


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "database_url", "")
    monkeypatch.setenv("PAPERORG_DB_PATH", str(tmp_path / "test.db"))
    import database

    monkeypatch.setattr(
        database, "DB_PATH", str(tmp_path / "test.db"), raising=False
    )
    from main import app

    with TestClient(app) as test_client:
        yield test_client


def platform_token(platform_keypair, ent=("notes.pro",), expired=False):
    key, _ = platform_keypair
    now = int(time.time())
    payload = {
        "sub": "11111111-2222-3333-4444-555555555555",
        "inst": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        "app": "notes",
        "ent": list(ent),
        "iss": "paperorg-platform",
        "iat": now - (7200 if expired else 0),
        "exp": now + (-3600 if expired else 3600),
    }
    return pyjwt.encode(
        payload, key, algorithm="RS256", headers={"kid": "test-kid"}
    )


def test_legacy_token_still_works(client):
    reg = client.post(
        "/v1/auth/register", json={"device_id": "legacy-device-123"}
    ).json()
    resp = client.get(
        "/v1/usage", headers={"Authorization": f"Bearer {reg['access_token']}"}
    )
    assert resp.status_code == 200


def test_platform_token_accepted_and_pro_enforced(client, platform_keypair, monkeypatch):
    import main

    # Pro platform user passes require_pro_user without touching local DB
    token = platform_token(platform_keypair)
    calls = {}
    monkeypatch.setattr(
        main, "platform_minutes_remaining", lambda bearer: calls.setdefault("checked", 500.0)
    )
    monkeypatch.setattr(
        main,
        "report_platform_usage",
        lambda bearer, user_id, minutes, provider: calls.setdefault(
            "reported", (user_id, minutes, provider)
        ),
    )
    principal = main.require_pro_user(
        {"source": "platform", "sub": "u-1", "ent": ["notes.pro"], "bearer": token}
    )
    assert principal["platform"] is True
    main.enforce_usage_limit(principal, 3.0)
    main.record_usage(principal, 3.0, "openai")
    assert calls["checked"] == 500.0
    assert calls["reported"] == ("u-1", 3.0, "openai")


def test_platform_token_without_pro_gets_402(client, platform_keypair):
    import main

    with pytest.raises(Exception) as exc_info:
        main.require_pro_user(
            {"source": "platform", "sub": "u-1", "ent": [], "bearer": "x"}
        )
    assert getattr(exc_info.value, "status_code", None) == 402


def test_platform_over_limit_gets_429(client, platform_keypair, monkeypatch):
    import main

    monkeypatch.setattr(main, "platform_minutes_remaining", lambda bearer: 1.5)
    with pytest.raises(Exception) as exc_info:
        main.enforce_usage_limit({"platform": True, "id": "u", "bearer": "x"}, 5.0)
    assert getattr(exc_info.value, "status_code", None) == 429


def test_expired_platform_token_rejected(client, platform_keypair):
    token = platform_token(platform_keypair, expired=True)
    resp = client.get(
        "/v1/usage", headers={"Authorization": f"Bearer {token}"}
    )
    assert resp.status_code == 401


def test_platform_token_on_legacy_endpoint_gets_clear_400(client, platform_keypair):
    token = platform_token(platform_keypair)
    resp = client.get("/v1/usage", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 400
    assert "Platform" in resp.json()["detail"]


def test_rs256_rejected_when_platform_disabled(client, platform_keypair, monkeypatch):
    monkeypatch.setattr(settings, "platform_api_url", "")
    token = platform_token(platform_keypair)
    resp = client.get("/v1/usage", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 401
