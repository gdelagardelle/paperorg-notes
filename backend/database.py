"""Database access for Paperorg Pro backend (SQLite dev, PostgreSQL production)."""

from __future__ import annotations

import sqlite3
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
"""

_POSTGRES_SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    device_id TEXT UNIQUE NOT NULL,
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
