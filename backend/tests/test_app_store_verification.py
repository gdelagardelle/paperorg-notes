"""Unit contracts for the App Store signed-data verification boundary."""

import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import app_store
from config import settings


class FakeVerifier:
    def verify_and_decode_signed_transaction(self, _signed_payload):
        return SimpleNamespace(
            bundleId="com.paperorg.notes",
            productId="com.paperorg.notes.pro.monthly",
            expiresDate=1_800_000_000_000,
            originalTransactionId="original-1",
            transactionId="transaction-1",
            revocationDate=None,
        )

    def verify_and_decode_notification(self, _signed_payload):
        return SimpleNamespace(
            notificationType=SimpleNamespace(value="DID_RENEW"),
            subtype=None,
            data=SimpleNamespace(signedTransactionInfo="nested-jws"),
        )


def test_transaction_verification_uses_the_server_verifier(monkeypatch):
    monkeypatch.setattr(app_store, "_signed_data_verifier", lambda: FakeVerifier())

    payload = app_store.decode_and_verify_transaction(
        "signed-jws",
        bundle_id="com.paperorg.notes",
        product_id="com.paperorg.notes.pro.monthly",
    )

    assert payload["originalTransactionId"] == "original-1"
    assert payload["transactionId"] == "transaction-1"


def test_transaction_rejects_a_valid_jws_for_another_product(monkeypatch):
    monkeypatch.setattr(app_store, "_signed_data_verifier", lambda: FakeVerifier())

    with pytest.raises(app_store.AppStoreVerificationError):
        app_store.decode_and_verify_transaction(
            "signed-jws",
            bundle_id="com.paperorg.notes",
            product_id="com.paperorg.notes.pro.yearly",
        )


def test_notification_is_decoded_only_after_server_verification(monkeypatch):
    monkeypatch.setattr(app_store, "_signed_data_verifier", lambda: FakeVerifier())

    payload = app_store.decode_and_verify_notification("notification-jws")

    assert payload == {
        "notificationType": "DID_RENEW",
        "subtype": None,
        "data": {"signedTransactionInfo": "nested-jws"},
    }


def test_missing_apple_roots_fail_closed(monkeypatch):
    monkeypatch.setattr(settings, "apple_root_certificates_dir", "")

    with pytest.raises(app_store.AppStoreVerificationError):
        app_store._signed_data_verifier()
