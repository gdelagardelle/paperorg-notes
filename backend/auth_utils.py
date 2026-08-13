from datetime import datetime, timedelta, timezone
from typing import Any, Optional

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from config import settings

security = HTTPBearer(auto_error=False)
APPLE_ISSUER = "https://appleid.apple.com"
APPLE_JWKS_URL = f"{APPLE_ISSUER}/auth/keys"


def create_access_token(
    user_id: str,
    device_id: str,
    expires_days: int = 30,
    *,
    auth_type: str = "legacy",
) -> str:
    payload = {
        "sub": user_id,
        "device_id": device_id,
        "auth_type": auth_type,
        "exp": datetime.now(timezone.utc) + timedelta(days=expires_days),
        "iat": datetime.now(timezone.utc),
    }
    return jwt.encode(payload, settings.paperorg_jwt_secret, algorithm="HS256")


def verify_apple_identity_token(identity_token: str) -> str:
    """Validate an Apple identity JWT and return only its verified subject."""
    signing_key = jwt.PyJWKClient(APPLE_JWKS_URL).get_signing_key_from_jwt(
        identity_token
    )
    claims = jwt.decode(
        identity_token,
        signing_key.key,
        algorithms=["RS256"],
        audience=settings.apple_bundle_id,
        issuer=APPLE_ISSUER,
        options={"require": ["exp", "iss", "aud", "sub"]},
    )
    subject = claims.get("sub")
    if not isinstance(subject, str) or not subject:
        raise jwt.InvalidTokenError("Apple identity token has no subject")
    return subject


def decode_token(token: str) -> dict[str, Any]:
    try:
        return jwt.decode(token, settings.paperorg_jwt_secret, algorithms=["HS256"])
    except jwt.PyJWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token.",
        ) from exc


def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
) -> dict[str, Any]:
    """Dual-stack principal: legacy HS256 tokens (this backend's own) and,
    when PLATFORM_API_URL is configured, Platform RS256 tokens
    validated against the Platform JWKS."""
    if credentials is None or not credentials.credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization required.",
        )
    bearer_value = credentials.credentials

    try:
        alg = jwt.get_unverified_header(bearer_value).get("alg")
    except jwt.PyJWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token.",
        ) from exc

    if alg == "RS256":
        from platform_client import platform_enabled, validate_platform_token

        if not platform_enabled():
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Platform tokens are not accepted by this server.",
            )
        claims = validate_platform_token(bearer_value)
        return {
            "source": "platform",
            "sub": claims["sub"],
            "ent": claims.get("ent", []),
            "device_id": None,
            "bearer": bearer_value,
        }

    payload = decode_token(bearer_value)
    payload["source"] = "apple" if payload.get("auth_type") == "apple" else "legacy"
    return payload
