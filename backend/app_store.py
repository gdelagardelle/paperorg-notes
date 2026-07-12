"""App Store Server API + JWS verification for Paperorg Pro subscriptions."""

from __future__ import annotations

import base64
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Optional

import httpx
import jwt
from cryptography import x509
from cryptography.hazmat.backends import default_backend

PRODUCTION_BASE_URL = "https://api.storekit.itunes.apple.com"
SANDBOX_BASE_URL = "https://api.storekit-sandbox.itunes.apple.com"


class AppStoreVerificationError(Exception):
    """Raised when Apple subscription verification fails."""


def _load_private_key_bytes(private_key: str) -> bytes:
    if private_key.strip().startswith("-----BEGIN"):
        return private_key.encode("utf-8")
    path = Path(private_key).expanduser()
    return path.read_bytes()


def generate_app_store_api_token(
    issuer_id: str,
    key_id: str,
    private_key: str,
    bundle_id: str,
) -> str:
    private_key_bytes = _load_private_key_bytes(private_key)
    now = int(time.time())
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + 3600,
        "aud": "appstoreconnect-v1",
        "bid": bundle_id,
    }
    headers = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    return jwt.encode(payload, private_key_bytes, algorithm="ES256", headers=headers)


def _public_key_from_x5c(x5c_chain: list[str]) -> Any:
    cert_der = base64.b64decode(x5c_chain[0])
    cert = x509.load_der_x509_certificate(cert_der, default_backend())
    return cert.public_key()


def decode_and_verify_jws(
    signed_payload: str,
    *,
    bundle_id: str,
    product_id: Optional[str] = None,
) -> dict[str, Any]:
    header = jwt.get_unverified_header(signed_payload)
    x5c = header.get("x5c")
    if not x5c:
        raise AppStoreVerificationError("Missing certificate chain in Apple JWS.")

    public_key = _public_key_from_x5c(x5c)
    payload = jwt.decode(
        signed_payload,
        public_key,
        algorithms=["ES256"],
        options={"verify_aud": False},
    )

    if payload.get("bundleId") and payload.get("bundleId") != bundle_id:
        raise AppStoreVerificationError("Subscription bundle ID does not match this app.")
    if product_id and payload.get("productId") and payload.get("productId") != product_id:
        raise AppStoreVerificationError("Subscription product ID does not match Paperorg Pro.")

    if payload.get("revocationDate") and product_id:
        raise AppStoreVerificationError("This subscription transaction was revoked.")

    return payload


def fetch_signed_transaction_info(
    transaction_id: str,
    *,
    issuer_id: str,
    key_id: str,
    private_key: str,
    bundle_id: str,
    use_sandbox: bool,
) -> str:
    if not issuer_id or not key_id or not private_key:
        raise AppStoreVerificationError(
            "App Store Server API credentials are not configured on the backend."
        )

    token = generate_app_store_api_token(issuer_id, key_id, private_key, bundle_id)
    base_url = SANDBOX_BASE_URL if use_sandbox else PRODUCTION_BASE_URL
    url = f"{base_url}/inApps/v1/transactions/{transaction_id}"

    with httpx.Client(timeout=30) as client:
        response = client.get(url, headers={"Authorization": f"Bearer {token}"})

    if response.status_code == 404:
        raise AppStoreVerificationError("Transaction not found in App Store.")
    if response.status_code >= 400:
        raise AppStoreVerificationError(
            f"App Store Server API error ({response.status_code})."
        )

    payload = response.json()
    signed = payload.get("signedTransactionInfo")
    if not signed:
        raise AppStoreVerificationError("App Store response did not include transaction info.")
    return signed


def expires_at_from_transaction(
    payload: dict[str, Any],
    *,
    allow_expired: bool = False,
) -> Optional[str]:
    expires_ms = payload.get("expiresDate")
    if expires_ms:
        expiry = datetime.fromtimestamp(int(expires_ms) / 1000, tz=timezone.utc)
        if expiry <= datetime.now(timezone.utc) and not allow_expired:
            raise AppStoreVerificationError("Subscription has expired.")
        return expiry.isoformat()

    return (datetime.now(timezone.utc) + timedelta(days=32)).isoformat()


def verify_pro_subscription(
    *,
    product_id: str,
    transaction_id: Optional[str],
    signed_transaction_info: Optional[str],
    bundle_id: str,
    issuer_id: str,
    key_id: str,
    private_key: str,
    use_sandbox: bool,
) -> dict[str, Any]:
    signed_payload = signed_transaction_info

    if not signed_payload:
        if not transaction_id:
            raise AppStoreVerificationError(
                "transaction_id or signed_transaction_info is required."
            )
        signed_payload = fetch_signed_transaction_info(
            transaction_id,
            issuer_id=issuer_id,
            key_id=key_id,
            private_key=private_key,
            bundle_id=bundle_id,
            use_sandbox=use_sandbox,
        )

    payload = decode_and_verify_jws(
        signed_payload,
        bundle_id=bundle_id,
        product_id=product_id,
    )
    return {
        "expires_at": expires_at_from_transaction(payload),
        "original_transaction_id": payload.get("originalTransactionId"),
        "transaction_id": payload.get("transactionId") or transaction_id,
        "product_id": payload.get("productId") or product_id,
    }
