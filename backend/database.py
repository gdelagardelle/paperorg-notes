"""Database access for Paperorg Pro backend (SQLite dev, PostgreSQL production)."""

from __future__ import annotations

import sqlite3
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator, Optional, Protocol

from config import settings

DB_PATH = Path(__file__).parent / "paperorg_pro.db"

_SQLITE_SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    device_id TEXT UNIQUE NOT NULL,
    apple_subject TEXT,
    is_pro INTEGER NOT NULL DEFAULT 0,
    pro_expires_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS usage_records (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL,
    period_key TEXT NOT NULL,
    minutes_used REAL NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL,
    UNIQUE(user_id, period_key),
    FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS subscription_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL,
    product_id TEXT NOT NULL,
    transaction_id TEXT,
    event_type TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS subscription_links (
    original_transaction_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    product_id TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS request_rate_limits (
    user_id TEXT NOT NULL,
    operation TEXT NOT NULL,
    window_key TEXT NOT NULL,
    request_count INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL,
    PRIMARY KEY (user_id, operation, window_key),
    FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS rate_limit_windows (
    bucket TEXT NOT NULL,
    window_start INTEGER NOT NULL,
    hits INTEGER NOT NULL,
    PRIMARY KEY(bucket, window_start)
);

CREATE TABLE IF NOT EXISTS app_attest_challenges (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    challenge BLOB NOT NULL,
    challenge_hash BLOB NOT NULL,
    expires_at TEXT NOT NULL,
    used_at TEXT,
    FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS app_attest_keys (
    user_id TEXT NOT NULL,
    key_id TEXT NOT NULL,
    public_key_pem TEXT NOT NULL,
    assertion_counter INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    PRIMARY KEY(user_id, key_id),
    FOREIGN KEY(user_id) REFERENCES users(id)
);
"""

_POSTGRES_SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    device_id TEXT UNIQUE NOT NULL,
    apple_subject TEXT,
    is_pro BOOLEAN NOT NULL DEFAULT FALSE,
    pro_expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS usage_records (
    id BIGSERIAL PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id),
    period_key TEXT NOT NULL,
    minutes_used DOUBLE PRECISION NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL,
    UNIQUE(user_id, period_key)
);

CREATE TABLE IF NOT EXISTS subscription_events (
    id BIGSERIAL PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id),
    product_id TEXT NOT NULL,
    transaction_id TEXT,
    event_type TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS subscription_links (
    original_transaction_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id),
    product_id TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS request_rate_limits (
    user_id TEXT NOT NULL REFERENCES users(id),
    operation TEXT NOT NULL,
    window_key TEXT NOT NULL,
    request_count INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (user_id, operation, window_key)
);

CREATE TABLE IF NOT EXISTS rate_limit_windows (
    bucket TEXT NOT NULL,
    window_start BIGINT NOT NULL,
    hits INTEGER NOT NULL,
    PRIMARY KEY(bucket, window_start)
);

CREATE TABLE IF NOT EXISTS app_attest_challenges (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id),
    challenge BYTEA NOT NULL,
    challenge_hash BYTEA NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS app_attest_keys (
    user_id TEXT NOT NULL REFERENCES users(id),
    key_id TEXT NOT NULL,
    public_key_pem TEXT NOT NULL,
    assertion_counter BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY(user_id, key_id)
);
"""


class RowLike(Protocol):
    def __getitem__(self, key: str) -> Any: ...


def uses_postgres() -> bool:
    return settings.database_url.startswith("postgresql")


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _adapt_sql(sql: str) -> str:
    return sql.replace("?", "%s") if uses_postgres() else sql


class _Connection:
    def __init__(self, conn: Any, *, postgres: bool) -> None:
        self._conn = conn
        self._postgres = postgres

    def execute(self, sql: str, params: tuple[Any, ...] = ()) -> Any:
        if self._postgres:
            cursor = self._conn.cursor()
            cursor.execute(_adapt_sql(sql), params)
            return cursor
        return self._conn.execute(sql, params)

    def executescript(self, sql: str) -> None:
        if self._postgres:
            cursor = self._conn.cursor()
            for statement in _split_sql_statements(sql):
                if statement.strip():
                    cursor.execute(statement)
            return
        self._conn.executescript(sql)


def _split_sql_statements(sql: str) -> list[str]:
    return [part.strip() for part in sql.split(";") if part.strip()]


@contextmanager
def connect() -> Iterator[_Connection]:
    if uses_postgres():
        import psycopg
        from psycopg.rows import dict_row

        with psycopg.connect(settings.database_url, row_factory=dict_row) as conn:
            wrapper = _Connection(conn, postgres=True)
            yield wrapper
            conn.commit()
    else:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        wrapper = _Connection(conn, postgres=False)
        try:
            yield wrapper
            conn.commit()
        finally:
            conn.close()


def init_db() -> None:
    schema = _POSTGRES_SCHEMA if uses_postgres() else _SQLITE_SCHEMA
    with connect() as conn:
        conn.executescript(schema)
        if uses_postgres():
            conn.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS apple_subject TEXT")
            conn.execute("ALTER TABLE app_attest_challenges ADD COLUMN IF NOT EXISTS challenge BYTEA")
        else:
            columns = conn.execute("PRAGMA table_info(users)").fetchall()
            if "apple_subject" not in {row["name"] for row in columns}:
                conn.execute("ALTER TABLE users ADD COLUMN apple_subject TEXT")
            attest_columns = conn.execute("PRAGMA table_info(app_attest_challenges)").fetchall()
            if attest_columns and "challenge" not in {row["name"] for row in attest_columns}:
                conn.execute("ALTER TABLE app_attest_challenges ADD COLUMN challenge BLOB")
        conn.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS users_apple_subject_unique "
            "ON users (apple_subject)"
        )


def check_connection() -> bool:
    try:
        with connect() as conn:
            conn.execute("SELECT 1")
        return True
    except Exception:
        return False


def period_key(now: Optional[datetime] = None) -> str:
    current = now or datetime.now(timezone.utc)
    return current.strftime("%Y-%m")


def get_or_create_user(device_id: str) -> RowLike:
    with connect() as conn:
        row = conn.execute(
            "SELECT * FROM users WHERE device_id = ?",
            (device_id,),
        ).fetchone()
        if row:
            return row

        user_id = device_id
        now = utc_now()
        conn.execute(
            """
            INSERT INTO users (id, device_id, is_pro, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            (user_id, device_id, False if uses_postgres() else 0, now, now),
        )
        return conn.execute(
            "SELECT * FROM users WHERE device_id = ?",
            (device_id,),
        ).fetchone()


def get_user_by_id(user_id: str) -> Optional[RowLike]:
    with connect() as conn:
        return conn.execute(
            "SELECT * FROM users WHERE id = ?",
            (user_id,),
        ).fetchone()


def get_or_create_apple_user(apple_subject: str, device_id: str) -> RowLike:
    """Resolve an Apple account, adopting a legacy device row when available."""
    with connect() as conn:
        row = conn.execute(
            "SELECT * FROM users WHERE apple_subject = ?",
            (apple_subject,),
        ).fetchone()
        if row:
            return row

        device_user = conn.execute(
            "SELECT * FROM users WHERE device_id = ?",
            (device_id,),
        ).fetchone()
        now = utc_now()
        if device_user and device_user["apple_subject"] is None:
            conn.execute(
                "UPDATE users SET apple_subject = ?, updated_at = ? WHERE id = ?",
                (apple_subject, now, device_user["id"]),
            )
            return conn.execute(
                "SELECT * FROM users WHERE id = ?", (device_user["id"],)
            ).fetchone()

        user_id = str(uuid.uuid4())
        stored_device_id = device_id if not device_user else f"apple:{user_id}"
        conn.execute(
            """
            INSERT INTO users
                (id, device_id, apple_subject, is_pro, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                user_id,
                stored_device_id,
                apple_subject,
                False if uses_postgres() else 0,
                now,
                now,
            ),
        )
        return conn.execute(
            "SELECT * FROM users WHERE apple_subject = ?",
            (apple_subject,),
        ).fetchone()


def set_user_pro(user_id: str, is_pro: bool, expires_at: Optional[str] = None) -> None:
    pro_value: Any = is_pro if uses_postgres() else (1 if is_pro else 0)
    with connect() as conn:
        conn.execute(
            """
            UPDATE users
            SET is_pro = ?, pro_expires_at = ?, updated_at = ?
            WHERE id = ?
            """,
            (pro_value, expires_at, utc_now(), user_id),
        )


def get_usage_minutes(user_id: str, key: Optional[str] = None) -> float:
    key = key or period_key()
    with connect() as conn:
        row = conn.execute(
            """
            SELECT minutes_used FROM usage_records
            WHERE user_id = ? AND period_key = ?
            """,
            (user_id, key),
        ).fetchone()
        return float(row["minutes_used"]) if row else 0.0


def add_usage_minutes(user_id: str, minutes: float, key: Optional[str] = None) -> float:
    key = key or period_key()
    now = utc_now()
    with connect() as conn:
        conn.execute(
            """
            INSERT INTO usage_records (user_id, period_key, minutes_used, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(user_id, period_key) DO UPDATE SET
                minutes_used = usage_records.minutes_used + EXCLUDED.minutes_used,
                updated_at = EXCLUDED.updated_at
            """,
            (user_id, key, minutes, now),
        )
        row = conn.execute(
            """
            SELECT minutes_used FROM usage_records
            WHERE user_id = ? AND period_key = ?
            """,
            (user_id, key),
        ).fetchone()
        return float(row["minutes_used"])


def reserve_usage_minutes(
    user_id: str,
    minutes: float,
    monthly_limit: float,
    key: Optional[str] = None,
) -> Optional[float]:
    """Atomically reserve metered time without allowing a concurrent overspend.

    The conditional upsert is the enforcement point: a request only obtains a
    reservation if adding its server-measured duration keeps the monthly total
    at or below the applicable plan limit.  Checking and incrementing in
    separate calls is unsafe because concurrent uploads can both pass a stale
    read before either one records usage.
    """
    if minutes <= 0 or monthly_limit <= 0 or minutes > monthly_limit:
        return None

    key = key or period_key()
    now = utc_now()
    with connect() as conn:
        row = conn.execute(
            """
            INSERT INTO usage_records (user_id, period_key, minutes_used, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(user_id, period_key) DO UPDATE SET
                minutes_used = usage_records.minutes_used + EXCLUDED.minutes_used,
                updated_at = EXCLUDED.updated_at
            WHERE usage_records.minutes_used + EXCLUDED.minutes_used <= ?
            RETURNING minutes_used
            """,
            (user_id, key, minutes, now, monthly_limit),
        ).fetchone()
        return float(row["minutes_used"]) if row else None


def release_usage_minutes(
    user_id: str,
    minutes: float,
    key: Optional[str] = None,
) -> None:
    """Release a reservation when the upstream provider rejects the work."""
    if minutes <= 0:
        return
    key = key or period_key()
    with connect() as conn:
        floor = "GREATEST" if uses_postgres() else "MAX"
        conn.execute(
            f"""
            UPDATE usage_records
            SET minutes_used = {floor}(0, minutes_used - ?), updated_at = ?
            WHERE user_id = ? AND period_key = ?
            """,
            (minutes, utc_now(), user_id, key),
        )


def reserve_rate_limited_request(
    user_id: str,
    operation: str,
    window_key: str,
    max_requests: int,
) -> bool:
    """Persistently admit one request, including across workers and restarts."""
    if max_requests <= 0:
        return False
    with connect() as conn:
        row = conn.execute(
            """
            INSERT INTO request_rate_limits
                (user_id, operation, window_key, request_count, updated_at)
            VALUES (?, ?, ?, 1, ?)
            ON CONFLICT(user_id, operation, window_key) DO UPDATE SET
                request_count = request_rate_limits.request_count + 1,
                updated_at = EXCLUDED.updated_at
            WHERE request_rate_limits.request_count < ?
            RETURNING request_count
            """,
            (user_id, operation, window_key, utc_now(), max_requests),
        ).fetchone()
        return row is not None


def consume_rate_limit(bucket: str, max_requests: int, window_seconds: int, now_epoch: int) -> bool:
    """Persist a public IP window independently of authenticated-user limits."""
    window_start = now_epoch - (now_epoch % window_seconds)
    with connect() as conn:
        cursor = conn.execute(
            """INSERT INTO rate_limit_windows (bucket, window_start, hits)
               VALUES (?, ?, 1)
               ON CONFLICT(bucket, window_start) DO UPDATE SET hits = rate_limit_windows.hits + 1
               WHERE rate_limit_windows.hits < ?
               RETURNING hits""",
            (bucket, window_start, max_requests),
        )
        accepted = cursor.fetchone() is not None
        conn.execute(
            "DELETE FROM rate_limit_windows WHERE window_start < ?",
            (window_start - (window_seconds * 2),),
        )
        return accepted


def log_subscription_event(
    user_id: str,
    product_id: str,
    transaction_id: Optional[str],
    event_type: str,
) -> None:
    with connect() as conn:
        conn.execute(
            """
            INSERT INTO subscription_events (user_id, product_id, transaction_id, event_type, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            (user_id, product_id, transaction_id, event_type, utc_now()),
        )


def link_subscription(
    user_id: str,
    original_transaction_id: str,
    product_id: str,
) -> None:
    if not original_transaction_id:
        return
    with connect() as conn:
        conn.execute(
            """
            INSERT INTO subscription_links (original_transaction_id, user_id, product_id, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(original_transaction_id) DO UPDATE SET
                user_id = EXCLUDED.user_id,
                product_id = EXCLUDED.product_id,
                updated_at = EXCLUDED.updated_at
            """,
            (original_transaction_id, user_id, product_id, utc_now()),
        )


def find_user_by_original_transaction(original_transaction_id: Optional[str]) -> Optional[str]:
    if not original_transaction_id:
        return None
    with connect() as conn:
        row = conn.execute(
            """
            SELECT user_id FROM subscription_links
            WHERE original_transaction_id = ?
            """,
            (original_transaction_id,),
        ).fetchone()
        return row["user_id"] if row else None
