"""Contract tests for Notes' server-to-server credential-vault boundary."""

import sys
import time
from pathlib import Path

import httpx
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from config import settings
import platform_client


def response(status_code: int, payload: dict) -> httpx.Response:
    request = httpx.Request("GET", "https://poplatform.test/internal/v1/credentials/resolve")
    return httpx.Response(status_code, json=payload, request=request)


@pytest.fixture(autouse=True)
def reset_platform_credential_configuration(monkeypatch):
    monkeypatch.setattr(settings, "platform_api_url", "")
    monkeypatch.setattr(settings, "platform_internal_token", "")
    platform_client._credential_cache.clear()
    yield
    platform_client._credential_cache.clear()


def test_uses_local_environment_key_only_when_platform_vault_is_not_enabled():
    assert platform_client.resolve_provider_key("openai", "local-openai-key") == "local-openai-key"


def test_uses_notes_scoped_platform_credential_when_vault_is_enabled(monkeypatch):
    monkeypatch.setattr(settings, "platform_api_url", "https://poplatform.test")
    monkeypatch.setattr(settings, "platform_internal_token", "service-token")
    calls = []

    def fake_get(url, *, params, headers, timeout):
        calls.append((url, params, headers, timeout))
        return response(
            200,
            {
                "provider": "openai",
                "secret": "platform-openai-key",
                "scope": "app",
            },
        )

    monkeypatch.setattr(platform_client.httpx, "get", fake_get)

    assert platform_client.resolve_provider_key("openai", "local-openai-key") == "platform-openai-key"
    assert calls == [
        (
            "https://poplatform.test/internal/v1/credentials/resolve",
            {"provider": "openai", "app_id": "notes"},
            {"Authorization": "Bearer service-token"},
            10,
        )
    ]


def test_missing_platform_credential_fails_closed_instead_of_using_local_key(monkeypatch):
    monkeypatch.setattr(settings, "platform_api_url", "https://poplatform.test")
    monkeypatch.setattr(settings, "platform_internal_token", "service-token")
    monkeypatch.setattr(
        platform_client.httpx,
        "get",
        lambda *args, **kwargs: response(404, {"detail": "Not found"}),
    )

    assert platform_client.resolve_provider_key("openai", "old-local-key") == ""


def test_platform_failure_fails_closed_instead_of_using_local_key(monkeypatch):
    monkeypatch.setattr(settings, "platform_api_url", "https://poplatform.test")
    monkeypatch.setattr(settings, "platform_internal_token", "service-token")
    monkeypatch.setattr(
        platform_client.httpx,
        "get",
        lambda *args, **kwargs: response(503, {"detail": "Service unavailable"}),
    )

    assert platform_client.resolve_provider_key("openai", "old-local-key") == ""


@pytest.mark.parametrize(
    "payload",
    [
        {"provider": "elevenlabs", "secret": "wrong-provider-key"},
        {"provider": "openai", "secret": ""},
        {"provider": "openai"},
    ],
)
def test_malformed_platform_response_fails_closed(monkeypatch, payload):
    monkeypatch.setattr(settings, "platform_api_url", "https://poplatform.test")
    monkeypatch.setattr(settings, "platform_internal_token", "service-token")
    monkeypatch.setattr(
        platform_client.httpx,
        "get",
        lambda *args, **kwargs: response(200, payload),
    )

    assert platform_client.resolve_provider_key("openai", "old-local-key") == ""


def test_valid_credential_is_cached_only_briefly(monkeypatch):
    monkeypatch.setattr(settings, "platform_api_url", "https://poplatform.test")
    monkeypatch.setattr(settings, "platform_internal_token", "service-token")
    calls = 0

    def fake_get(*args, **kwargs):
        nonlocal calls
        calls += 1
        return response(200, {"provider": "openai", "secret": "platform-openai-key"})

    monkeypatch.setattr(platform_client.httpx, "get", fake_get)

    assert platform_client.resolve_provider_key("openai", "old-local-key") == "platform-openai-key"
    assert platform_client.resolve_provider_key("openai", "old-local-key") == "platform-openai-key"
    assert calls == 1

    platform_client._credential_cache["openai"] = (
        time.time() - platform_client._CREDENTIAL_TTL_SECONDS - 1,
        "platform-openai-key",
    )
    assert platform_client.resolve_provider_key("openai", "old-local-key") == "platform-openai-key"
    assert calls == 2
