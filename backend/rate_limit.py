"""Simple in-memory rate limiting for public endpoints."""

from __future__ import annotations

from collections import defaultdict
from threading import Lock
from time import time

from fastapi import HTTPException, Request, status

_lock = Lock()
_buckets: dict[str, list[float]] = defaultdict(list)


def enforce_rate_limit(
    request: Request,
    *,
    key_prefix: str,
    max_requests: int,
    window_seconds: int,
) -> None:
    client = request.client.host if request.client else "unknown"
    key = f"{key_prefix}:{client}"
    now = time()
    window_start = now - window_seconds

    with _lock:
        hits = [stamp for stamp in _buckets[key] if stamp > window_start]
        if len(hits) >= max_requests:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many requests. Try again later.",
            )
        hits.append(now)
        _buckets[key] = hits
