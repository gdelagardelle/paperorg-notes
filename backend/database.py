import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

DB_PATH = Path(__file__).parent / "paperorg_pro.db"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def init_db() -> None:
    with connect() as conn:
        conn.executescript(
            """
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
            """
        )


@contextmanager
def connect():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def period_key(now: Optional[datetime] = None) -> str:
    current = now or datetime.now(timezone.utc)
    return current.strftime("%Y-%m")


def get_or_create_user(device_id: str) -> sqlite3.Row:
    with connect() as conn:
        row = conn.execute(
            "SELECT * FROM users WHERE device_id = ?", (device_id,)
        ).fetchone()
        if row:
            return row

        user_id = device_id
        now = utc_now()
        conn.execute(
            """
            INSERT INTO users (id, device_id, is_pro, created_at, updated_at)
            VALUES (?, ?, 0, ?, ?)
            """,
            (user_id, device_id, now, now),
        )
        return conn.execute(
            "SELECT * FROM users WHERE device_id = ?", (device_id,)
        ).fetchone()


def set_user_pro(user_id: str, is_pro: bool, expires_at: Optional[str] = None) -> None:
    with connect() as conn:
        conn.execute(
            """
            UPDATE users
            SET is_pro = ?, pro_expires_at = ?, updated_at = ?
            WHERE id = ?
            """,
            (1 if is_pro else 0, expires_at, utc_now(), user_id),
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
                minutes_used = minutes_used + excluded.minutes_used,
                updated_at = excluded.updated_at
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
