"""Apple App Attest verification for metered Paperorg Notes requests.

Implements Apple's documented checks: certificate chain, challenge nonce,
key identifier, App ID RP hash, AAGUID, and monotonic assertion counter.
"""

from __future__ import annotations

import base64
import hashlib
import io
import os
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

import cbor2
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import ObjectIdentifier

from config import settings
from database import connect, utc_now

_NONCE_OID = ObjectIdentifier("1.2.840.113635.100.8.2")
_PRODUCTION_AAGUID = b"appattest" + (b"\0" * 7)
_DEVELOPMENT_AAGUID = b"appattestdevelop"


class AppAttestError(Exception):
    pass


def _b64(value: str) -> bytes:
    try:
        return base64.b64decode(value, validate=True)
    except Exception as exc:
        raise AppAttestError("Malformed App Attest data.") from exc


def _der_nonce(value: bytes) -> bytes:
    """Extract the 32-byte nonce from Apple's DER certificate extension.

    Apple's certificate extension is a DER SEQUENCE containing the nonce as an
    OCTET STRING.  App Attest certificates in the wild may put that OCTET
    STRING behind an explicit context-0 wrapper.  Decode only those documented
    shapes; do not recursively search the certificate for a convenient value.
    """
    def read_element(data: bytes, index: int = 0) -> tuple[int, bytes, int]:
        if index >= len(data):
            raise AppAttestError("Invalid App Attest nonce extension.")
        tag = data[index]
        index += 1
        if index >= len(data):
            raise AppAttestError("Invalid App Attest nonce extension.")
        first = data[index]
        index += 1
        if first < 0x80:
            length = first
        else:
            size = first & 0x7F
            if size == 0 or size > 2 or index + size > len(data):
                raise AppAttestError("Invalid App Attest nonce extension.")
            length_bytes = data[index : index + size]
            # DER requires the shortest possible length encoding.
            if length_bytes[0] == 0 or (size == 1 and length_bytes[0] < 0x80):
                raise AppAttestError("Invalid App Attest nonce extension.")
            length = int.from_bytes(length_bytes, "big")
            index += size
        end = index + length
        if end > len(data):
            raise AppAttestError("Invalid App Attest nonce extension.")
        return tag, data[index:end], end

    # cryptography exposes the extension's inner DER value. Accepting the
    # optional outer OCTET STRING makes this safe for decoders that retain it.
    tag, content, end = read_element(value)
    if end != len(value):
        raise AppAttestError("Invalid App Attest nonce extension.")
    if tag == 0x04:
        wrapped = content
        tag, content, end = read_element(wrapped)
        if end != len(wrapped):
            raise AppAttestError("Invalid App Attest nonce extension.")
    if tag != 0x30:
        raise AppAttestError("Invalid App Attest nonce extension.")

    tag, nonce, end = read_element(content)
    if end != len(content):
        raise AppAttestError("Invalid App Attest nonce extension.")
    if tag == 0xA0:
        wrapped = nonce
        tag, nonce, end = read_element(wrapped)
        if end != len(wrapped):
            raise AppAttestError("Invalid App Attest nonce extension.")
    if tag != 0x04 or len(nonce) != 32:
        raise AppAttestError("Invalid App Attest nonce extension.")
    return nonce


def _verify_chain(certs: list[x509.Certificate]) -> x509.Certificate:
    if len(certs) < 2 or not settings.app_attest_root_certificate_path:
        raise AppAttestError("App Attest certificate chain is not configured.")
    root = x509.load_pem_x509_certificate(open(settings.app_attest_root_certificate_path, "rb").read())
    chain = certs + [root]
    now = datetime.now(timezone.utc)
    for cert in chain:
        if cert.not_valid_before_utc > now or cert.not_valid_after_utc < now:
            raise AppAttestError("Expired App Attest certificate.")
    for cert, issuer in zip(chain, chain[1:]):
        if cert.issuer != issuer.subject:
            raise AppAttestError("Invalid App Attest certificate issuer.")
        issuer.public_key().verify(cert.signature, cert.tbs_certificate_bytes, ec.ECDSA(cert.signature_hash_algorithm))
    return certs[0]


def _attestation_auth_data(raw: bytes) -> tuple[bytes, int, bytes, bytes, dict[str, Any]]:
    if len(raw) < 55:
        raise AppAttestError("Malformed authenticator data.")
    rp_hash, flags, counter = raw[:32], raw[32], int.from_bytes(raw[33:37], "big")
    if flags & 0x40 == 0:
        raise AppAttestError("Attested credential data is missing.")
    aaguid = raw[37:53]
    cred_len = int.from_bytes(raw[53:55], "big")
    credential_id = raw[55 : 55 + cred_len]
    decoder = cbor2.CBORDecoder(io.BytesIO(raw[55 + cred_len :]))
    cose_key = decoder.decode()
    remainder = decoder.fp.read()
    extensions = cbor2.loads(remainder) if remainder else {}
    return rp_hash, counter, aaguid, credential_id, {"cose": cose_key, "extensions": extensions}


def create_challenge(user_id: str) -> tuple[str, bytes, str]:
    challenge = os.urandom(32)
    challenge_id = str(uuid.uuid4())
    expires = datetime.now(timezone.utc) + timedelta(seconds=settings.app_attest_challenge_ttl_seconds)
    with connect() as conn:
        conn.execute(
            """INSERT INTO app_attest_challenges
               (id, user_id, challenge, challenge_hash, expires_at)
               VALUES (?, ?, ?, ?, ?)""",
            (challenge_id, user_id, challenge, hashlib.sha256(challenge).digest(), expires.isoformat()),
        )
    return challenge_id, challenge, expires.isoformat()


def has_attested_key(user_id: str, key_id: str | None) -> bool:
    """Whether this device key is currently registered for this user.

    The device asks this before every protected request. It means a server
    restore or key-record loss triggers a fresh Apple attestation instead of
    producing an opaque assertion failure.
    """
    if not key_id:
        return False
    with connect() as conn:
        row = conn.execute(
            """SELECT 1 FROM app_attest_keys
               WHERE user_id = ? AND key_id = ?""",
            (user_id, key_id),
        ).fetchone()
    return row is not None


def _consume_challenge(user_id: str, challenge_id: str) -> bytes:
    with connect() as conn:
        row = conn.execute(
            """SELECT challenge, expires_at FROM app_attest_challenges
               WHERE id = ? AND user_id = ? AND used_at IS NULL""", (challenge_id, user_id)
        ).fetchone()
        if row is None:
            raise AppAttestError("App Attest challenge is missing or already used.")
        expiry = datetime.fromisoformat(str(row["expires_at"]).replace("Z", "+00:00"))
        if expiry < datetime.now(timezone.utc):
            raise AppAttestError("App Attest challenge expired.")
        conn.execute("UPDATE app_attest_challenges SET used_at = ? WHERE id = ?", (utc_now(), challenge_id))
        return bytes(row["challenge"])


def _challenge_for_assertion(user_id: str, challenge_id: str) -> bytes:
    with connect() as conn:
        row = conn.execute(
            """SELECT challenge, expires_at FROM app_attest_challenges
               WHERE id = ? AND user_id = ? AND used_at IS NULL""", (challenge_id, user_id)
        ).fetchone()
        if row is None:
            raise AppAttestError("App Attest challenge is missing or already used.")
        expiry = datetime.fromisoformat(str(row["expires_at"]).replace("Z", "+00:00"))
        if expiry < datetime.now(timezone.utc):
            raise AppAttestError("App Attest challenge expired.")
        return bytes(row["challenge"])


def verify_attestation(user_id: str, challenge_id: str, key_id: str, object_b64: str) -> None:
    challenge = _consume_challenge(user_id, challenge_id)
    obj = cbor2.loads(_b64(object_b64))
    if obj.get("fmt") != "apple-appattest":
        raise AppAttestError("Unexpected attestation format.")
    certs = [x509.load_der_x509_certificate(value) for value in obj.get("attStmt", {}).get("x5c", [])]
    leaf = _verify_chain(certs)
    auth_data = obj.get("authData")
    if not isinstance(auth_data, bytes):
        raise AppAttestError("Attestation has no authenticator data.")
    rp_hash, counter, aaguid, credential_id, extra = _attestation_auth_data(auth_data)
    expected_app_id = f"{settings.app_attest_team_id}.{settings.apple_bundle_id}".encode()
    if rp_hash != hashlib.sha256(expected_app_id).digest() or counter != 0:
        raise AppAttestError("App Attest authenticator data does not match this app.")
    expected_aaguid = _DEVELOPMENT_AAGUID if settings.paperorg_dev_mode else _PRODUCTION_AAGUID
    if aaguid != expected_aaguid or credential_id != _b64(key_id):
        raise AppAttestError("App Attest key does not match this environment.")
    nonce = hashlib.sha256(auth_data + hashlib.sha256(challenge).digest()).digest()
    if _der_nonce(leaf.extensions.get_extension_for_oid(_NONCE_OID).value.value) != nonce:
        raise AppAttestError("App Attest nonce check failed.")
    point = leaf.public_key().public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)
    if hashlib.sha256(point).digest() != _b64(key_id):
        raise AppAttestError("App Attest public key does not match key ID.")
    if not isinstance(extra["extensions"], dict) or "apple_validation_category_01" not in extra["extensions"]:
        raise AppAttestError("App Attest validation category is missing.")
    pem = leaf.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo).decode()
    with connect() as conn:
        conn.execute(
            """INSERT INTO app_attest_keys (user_id, key_id, public_key_pem, assertion_counter, created_at)
               VALUES (?, ?, ?, 0, ?)
               ON CONFLICT(user_id, key_id) DO UPDATE SET public_key_pem = EXCLUDED.public_key_pem""",
            (user_id, key_id, pem, utc_now()),
        )


def verify_assertion(user_id: str, challenge_id: str, key_id: str, assertion_b64: str, protected_payload: bytes) -> None:
    """Verify an assertion bound to an exact audio payload and route.

    The one-time challenge and monotonically increasing Apple counter make a
    captured assertion unusable for replay or for a different provider route.
    """
    challenge = _challenge_for_assertion(user_id, challenge_id)
    try:
        assertion = cbor2.loads(_b64(assertion_b64))
        auth_data = assertion["authenticatorData"]
        signature = assertion["signature"]
    except (KeyError, TypeError) as exc:
        raise AppAttestError("Malformed App Attest assertion.") from exc
    if not isinstance(auth_data, bytes) or len(auth_data) < 37 or not isinstance(signature, bytes):
        raise AppAttestError("Malformed App Attest assertion.")
    expected_app_id = f"{settings.app_attest_team_id}.{settings.apple_bundle_id}".encode()
    if auth_data[:32] != hashlib.sha256(expected_app_id).digest():
        raise AppAttestError("Assertion was issued for a different app.")
    counter = int.from_bytes(auth_data[33:37], "big")
    with connect() as conn:
        row = conn.execute(
            """SELECT public_key_pem, assertion_counter FROM app_attest_keys
               WHERE user_id = ? AND key_id = ?""", (user_id, key_id)
        ).fetchone()
        if row is None or counter <= int(row["assertion_counter"]):
            raise AppAttestError("App Attest assertion was replayed or is unknown.")
        client_hash = hashlib.sha256(challenge + hashlib.sha256(protected_payload).digest()).digest()
        public_key = serialization.load_pem_public_key(str(row["public_key_pem"]).encode())
        try:
            public_key.verify(signature, auth_data + client_hash, ec.ECDSA(hashes.SHA256()))
        except Exception as exc:
            raise AppAttestError("App Attest assertion signature is invalid.") from exc
        used = conn.execute(
            """UPDATE app_attest_challenges SET used_at = ?
               WHERE id = ? AND user_id = ? AND used_at IS NULL""", (utc_now(), challenge_id, user_id)
        )
        updated = conn.execute(
            """UPDATE app_attest_keys SET assertion_counter = ?
               WHERE user_id = ? AND key_id = ? AND assertion_counter < ?""",
            (counter, user_id, key_id, counter),
        )
        if used.rowcount != 1 or updated.rowcount != 1:
            raise AppAttestError("App Attest assertion was replayed.")
