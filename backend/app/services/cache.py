import json
import os
import sqlite3
import threading
import time
from pathlib import Path


DEFAULT_TTL_SECONDS = 10 * 60


class JsonApiCache:
    def __init__(self, db_path=None, ttl_seconds=DEFAULT_TTL_SECONDS):
        self.db_path = Path(db_path or default_cache_db_path())
        self.ttl_seconds = ttl_seconds
        self._lock = threading.Lock()
        self._initialized = False

    def get(self, key):
        self._ensure_table()
        now = int(time.time())
        with self._connect() as connection:
            row = connection.execute(
                """
                SELECT response_json
                FROM api_cache
                WHERE cache_key = ? AND expires_at > ?
                """,
                (key, now),
            ).fetchone()

        if row is None:
            return None

        try:
            return json.loads(row[0])
        except json.JSONDecodeError:
            self.delete(key)
            return None

    def set(self, key, value):
        self._ensure_table()
        now = int(time.time())
        expires_at = now + self.ttl_seconds
        payload = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
        with self._lock:
            with self._connect() as connection:
                connection.execute(
                    """
                    INSERT INTO api_cache (
                        cache_key,
                        response_json,
                        created_at,
                        expires_at
                    )
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(cache_key) DO UPDATE SET
                        response_json = excluded.response_json,
                        created_at = excluded.created_at,
                        expires_at = excluded.expires_at
                    """,
                    (key, payload, now, expires_at),
                )
                connection.commit()

    def delete(self, key):
        self._ensure_table()
        with self._lock:
            with self._connect() as connection:
                connection.execute("DELETE FROM api_cache WHERE cache_key = ?", (key,))
                connection.commit()

    def cleanup_expired(self):
        self._ensure_table()
        now = int(time.time())
        with self._lock:
            with self._connect() as connection:
                connection.execute("DELETE FROM api_cache WHERE expires_at <= ?", (now,))
                connection.commit()

    def _connect(self):
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        connection = sqlite3.connect(str(self.db_path), timeout=15)
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("PRAGMA busy_timeout=5000")
        return connection

    def _ensure_table(self):
        if self._initialized:
            return

        with self._lock:
            if self._initialized:
                return
            with self._connect() as connection:
                connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS api_cache (
                        cache_key TEXT PRIMARY KEY,
                        response_json TEXT NOT NULL,
                        created_at INTEGER NOT NULL,
                        expires_at INTEGER NOT NULL
                    )
                    """
                )
                connection.execute(
                    """
                    CREATE INDEX IF NOT EXISTS idx_api_cache_expires_at
                    ON api_cache(expires_at)
                    """
                )
                connection.commit()
            self._initialized = True


def default_cache_db_path():
    configured = os.getenv("API_CACHE_DB_PATH", "").strip()
    if configured:
        return configured
    return Path(__file__).resolve().parents[2] / "api_cache.sqlite3"
