#!/usr/bin/env python3
from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))

from config import settings  # noqa: E402
from database import DB_PATH, init_db, uses_postgres  # noqa: E402


def main() -> None:
    if not uses_postgres():
        raise SystemExit("Set DATABASE_URL to a postgresql:// connection string first.")

    if not DB_PATH.exists():
        print("No SQLite database found — initializing empty PostgreSQL schema.")
        init_db()
        return

    init_db()

    sqlite_conn = sqlite3.connect(DB_PATH)
    sqlite_conn.row_factory = sqlite3.Row

    import psycopg
    from psycopg.rows import dict_row

    with psycopg.connect(settings.database_url, row_factory=dict_row) as pg:
        users = sqlite_conn.execute("SELECT * FROM users").fetchall()
        for row in users:
            pg.execute(
                """
                INSERT INTO users (id, device_id, is_pro, pro_expires_at, created_at, updated_at)
                VALUES (%s, %s, %s, %s, %s, %s)
                ON CONFLICT (id) DO NOTHING
                """,
                (
                    row["id"],
                    row["device_id"],
                    bool(row["is_pro"]),
                    row["pro_expires_at"],
                    row["created_at"],
                    row["updated_at"],
                ),
            )

        usage = sqlite_conn.execute("SELECT * FROM usage_records").fetchall()
        for row in usage:
            pg.execute(
                """
                INSERT INTO usage_records (user_id, period_key, minutes_used, updated_at)
                VALUES (%s, %s, %s, %s)
                ON CONFLICT (user_id, period_key) DO UPDATE SET
                    minutes_used = EXCLUDED.minutes_used,
                    updated_at = EXCLUDED.updated_at
                """,
                (row["user_id"], row["period_key"], row["minutes_used"], row["updated_at"]),
            )

        events = sqlite_conn.execute("SELECT * FROM subscription_events").fetchall()
        for row in events:
            pg.execute(
                """
                INSERT INTO subscription_events (user_id, product_id, transaction_id, event_type, created_at)
                VALUES (%s, %s, %s, %s, %s)
                """,
                (
                    row["user_id"],
                    row["product_id"],
                    row["transaction_id"],
                    row["event_type"],
                    row["created_at"],
                ),
            )

        links = sqlite_conn.execute("SELECT * FROM subscription_links").fetchall()
        for row in links:
            pg.execute(
                """
                INSERT INTO subscription_links (original_transaction_id, user_id, product_id, updated_at)
                VALUES (%s, %s, %s, %s)
                ON CONFLICT (original_transaction_id) DO NOTHING
                """,
                (
                    row["original_transaction_id"],
                    row["user_id"],
                    row["product_id"],
                    row["updated_at"],
                ),
            )

        pg.commit()

    print(
        f"Migrated {len(users)} users, {len(usage)} usage rows, "
        f"{len(events)} subscription events, {len(links)} subscription links."
    )


if __name__ == "__main__":
    main()
