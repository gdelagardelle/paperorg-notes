"""Contract tests for the 30-minute Apple-account Free entitlement."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pytest
from fastapi import HTTPException

from config import settings


@pytest.fixture
def free_user(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "database_url", "")
    monkeypatch.setattr(settings, "free_included_minutes_enabled", True)
    monkeypatch.setattr(settings, "free_minutes_per_month", 30)

    import database
    import main

    monkeypatch.setattr(database, "DB_PATH", tmp_path / "test.db")
    database.init_db()
    user = database.get_or_create_apple_user("verified-apple-subject", "free-device-12345")
    return main, database, user


def test_verified_free_user_receives_thirty_monthly_minutes(free_user):
    main, _, user = free_user

    usage = main.build_usage_response(user)

    assert usage.is_pro is False
    assert usage.minutes_limit == 30
    assert usage.minutes_remaining == 30


def test_device_only_user_never_receives_included_provider_credit(free_user):
    main, database, _ = free_user
    device_user = database.get_or_create_user("device-only-12345")

    with pytest.raises(HTTPException) as error:
        main.require_processing_user({"source": "legacy", "device_id": device_user["device_id"]})

    assert error.value.status_code == 402


def test_free_quota_rejects_any_request_over_the_remaining_minutes(free_user):
    main, database, user = free_user
    database.add_usage_minutes(user["id"], 29.5)

    main.enforce_usage_limit(user, 0.5)
    with pytest.raises(HTTPException) as error:
        main.enforce_usage_limit(user, 0.51)

    assert error.value.status_code == 429


def test_duration_reader_uses_m4a_metadata_not_client_duration():
    from audio_duration import duration_seconds

    # moov/mvhd version 0: 48 kHz timescale, 90 seconds duration.
    mvhd_payload = (
        b"\x00\x00\x00\x00"
        + (0).to_bytes(4, "big")
        + (0).to_bytes(4, "big")
        + (48_000).to_bytes(4, "big")
        + (4_320_000).to_bytes(4, "big")
    )
    mvhd = (8 + len(mvhd_payload)).to_bytes(4, "big") + b"mvhd" + mvhd_payload
    m4a = (8 + len(mvhd)).to_bytes(4, "big") + b"moov" + mvhd

    assert duration_seconds(m4a) == pytest.approx(90.0)


def test_duration_reader_rejects_audio_without_parseable_metadata():
    from audio_duration import AudioDurationError, duration_seconds

    with pytest.raises(AudioDurationError):
        duration_seconds(b"not an m4a")
