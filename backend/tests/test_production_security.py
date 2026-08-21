"""Startup safety checks for deployment-shaped configuration."""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import main
from config import settings


def configure_production(monkeypatch):
    monkeypatch.setattr(settings, "database_url", "postgresql://notes:test@localhost/notes")
    monkeypatch.setattr(settings, "paperorg_dev_mode", False)
    monkeypatch.setattr(settings, "paperorg_jwt_secret", "a" * 32)


def test_production_refuses_a_weak_jwt_secret(monkeypatch):
    configure_production(monkeypatch)
    monkeypatch.setattr(settings, "paperorg_jwt_secret", "short")

    with pytest.raises(RuntimeError, match="JWT"):
        main.validate_production_security()


def test_free_minutes_require_the_platform_vault(monkeypatch):
    configure_production(monkeypatch)
    monkeypatch.setattr(settings, "free_included_minutes_enabled", True)
    monkeypatch.setattr(settings, "platform_api_url", "")
    monkeypatch.setattr(settings, "platform_internal_token", "")

    with pytest.raises(RuntimeError, match="credential vault"):
        main.validate_production_security()


def test_production_allows_configured_free_minutes(monkeypatch):
    configure_production(monkeypatch)
    monkeypatch.setattr(settings, "free_included_minutes_enabled", True)
    monkeypatch.setattr(settings, "platform_api_url", "https://poplatform.paperorg.com")
    monkeypatch.setattr(settings, "platform_internal_token", "internal-token")
    monkeypatch.setattr(settings, "app_attest_enabled", True)

    main.validate_production_security()


def test_free_minutes_require_app_attest(monkeypatch):
    configure_production(monkeypatch)
    monkeypatch.setattr(settings, "free_included_minutes_enabled", True)
    monkeypatch.setattr(settings, "platform_api_url", "https://poplatform.paperorg.com")
    monkeypatch.setattr(settings, "platform_internal_token", "internal-token")
    monkeypatch.setattr(settings, "app_attest_enabled", False)

    with pytest.raises(RuntimeError, match="App Attest"):
        main.validate_production_security()
