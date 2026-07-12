"""Paperorg Platform integration for notes-api (Phase C/D).

Three capabilities, each independently env-gated:
- Validate Platform-issued RS256 JWTs via the Platform's JWKS
  (PLATFORM_API_URL) — lets iOS builds with USE_PLATFORM_AUTH=YES call transcribe/summarize here with their Platform token.
- Check/report usage against the Platform ledger, acting as the user
  (their own bearer token is forwarded — no service credential involved).
- Resolve provider API keys from the Platform credentials vault
  (PLATFORM_INTERNAL_TOKEN), falling back to local env vars.
"""

from __future__ import annotations

import time
import uuid
from typing import Any, Optional

import httpx
import jwt
from fastapi import HTTPException, status

from config import settings

_JWKS_TTL_SECONDS = 3600
_jwks_cache: dict[str, Any] = {"keys": None, "fetched_at": 0.0}

_CREDENTIAL_TTL_SECONDS = 600
_credential_cache: dict[str, tuple[float, Optional[str]]] = {}


def platform_enabled() -> bool:
    return bool(settings.platform_api_url)


def _jwks() -> dict[str, Any]:
    now = time.time()
    if _jwks_cache["keys"] is None or now - _jwks_cache["fetched_at"] > _JWKS_TTL_SECONDS:
        response = httpx.get(
            f"{settings.platform_api_url}/.well-known/jwks.json", timeout=10
        )
        response.raise_for_status()
        _jwks_cache["keys"] = {
            key["kid"]: jwt.PyJWK.from_dict(key).key
            for key in response.json()["keys"]
        }
        _jwks_cache["fetched_at"] = now
    return _jwks_cache["keys"]


def validate_platform_token(token: str) -> dict[str, Any]:
    """Verify an RS256 Platform JWT against the Platform JWKS."""
    try:
        kid = jwt.get_unverified_header(token).get("kid")
        keys = _jwks()
        public_key = keys.get(kid)
        if public_key is None:
            # key rotation: refetch once
            _jwks_cache["keys"] = None
            public_key = _jwks().get(kid)
        if public_key is None:
            raise jwt.InvalidTokenError("Unknown key id")
        return jwt.decode(
            token,
            public_key,
            algorithms=["RS256"],
            issuer="paperorg-platform",
            options={"require": ["exp", "iat", "sub"]},
        )
    except jwt.PyJWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token.",
        ) from exc
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Platform unavailable for token validation.",
        ) from exc


def platform_minutes_remaining(bearer: str) -> Optional[float]:
    """Current period remaining minutes for the token's user, or None if
    the Platform can't answer (fail open — the ledger still records)."""
    try:
        response = httpx.get(
            f"{settings.platform_api_url}/v1/usage",
            params={"app_id": "notes"},
            headers={"Authorization": f"Bearer {bearer}"},
            timeout=10,
        )
        if response.status_code != 200:
            return None
        minutes = response.json()["metrics"].get("transcription.minutes") or {}
        return minutes.get("remaining")
    except httpx.HTTPError:
        return None


def report_platform_usage(
    bearer: str, user_id: str, minutes: float, provider: str
) -> None:
    """Best-effort post-work usage report to the Platform ledger."""
    from datetime import datetime, timezone

    event = {
        "idempotency_key": f"notes-api-{uuid.uuid4()}",
        "app_id": "notes",
        "user_id": user_id,
        "metric": "transcription.minutes",
        "quantity": max(minutes, 0.1),
        "occurred_at": datetime.now(timezone.utc).isoformat(),
        "metadata": {"provider": provider, "reported_by": "notes-api"},
    }
    try:
        httpx.post(
            f"{settings.platform_api_url}/v1/usage/events",
            json={"events": [event]},
            headers={"Authorization": f"Bearer {bearer}"},
            timeout=10,
        )
        # 429 here means the limit tripped AFTER this work completed; the
        # event is still ledgered and the next pre-check will block.
    except httpx.HTTPError:
        pass


def resolve_provider_key(provider: str, env_value: str) -> str:
    """Vault key if the internal token is configured, else the env value."""
    if not settings.platform_api_url or not settings.platform_internal_token:
        return env_value
    cached = _credential_cache.get(provider)
    if cached and time.time() - cached[0] < _CREDENTIAL_TTL_SECONDS:
        return cached[1] or env_value
    secret: Optional[str] = None
    try:
        response = httpx.get(
            f"{settings.platform_api_url}/internal/v1/credentials/resolve",
            params={"provider": provider, "app_id": "notes"},
            headers={"Authorization": f"Bearer {settings.platform_internal_token}"},
            timeout=10,
        )
        if response.status_code == 200:
            secret = response.json().get("secret")
    except httpx.HTTPError:
        secret = None
    _credential_cache[provider] = (time.time(), secret)
    return secret or env_value
