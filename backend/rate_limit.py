"""Database-backed rate limiting for public endpoints."""

from __future__ import annotations

from time import time

from fastapi import HTTPException, Request, status

from database import consume_rate_limit


def enforce_rate_limit(
    request: Request,
    *,
    key_prefix: str,
    max_requests: int,
    window_seconds: int,
) -> None:
    client = request.client.host if request.client else "unknown"
    key = f"{key_prefix}:{client}"
    if not consume_rate_limit(key, max_requests, window_seconds, int(time())):
        raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail="Too many requests. Try again later.")


def enforce_user_rate_limit(
    user_key: str,
    *,
    key_prefix: str,
    max_requests: int,
    window_seconds: int,
) -> None:
    key = f"{key_prefix}:{user_key}"
    if not consume_rate_limit(key, max_requests, window_seconds, int(time())):
        raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail="Daily email limit reached. Try again tomorrow.")
