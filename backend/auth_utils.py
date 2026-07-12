from datetime import datetime, timedelta, timezone
from typing import Any, Optional

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from config import settings

security = HTTPBearer(auto_error=False)


def create_access_token(user_id: str, device_id: str, expires_days: int = 30) -> str:
    payload = {
        "sub": user_id,
        "device_id": device_id,
        "exp": datetime.now(timezone.utc) + timedelta(days=expires_days),
        "iat": datetime.now(timezone.utc),
    }
    return jwt.encode(payload, settings.paperorg_jwt_secret, algorithm="HS256")


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
    token = credentials.credentials

    try:
        alg = jwt.get_unverified_header(token).get("alg")
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
        claims = validate_platform_token(token)
        return {
            "source": "platform",
            "sub": claims["sub"],
            "ent": claims.get("ent", []),
            "device_id": None,
            "bearer": token,
        }

    payload = decode_token(token)
    payload["source"] = "legacy"
    return payload
