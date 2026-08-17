import argparse
import os
import sqlite3
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description="Add admin role support to the backend database.")
    parser.add_argument("--db", help="Path to the main backend SQLite database.")
    args = parser.parse_args()

    db_path = resolve_db_path(args.db)
    if not db_path.exists():
        print(f"Database file was not found: {db_path}")
        return 2

    connection = sqlite3.connect(str(db_path))
    try:
        connection.row_factory = sqlite3.Row
        migrate(connection)
    finally:
        connection.close()

    print(f"Admin migration completed for: {db_path}")
    return 0


def migrate(connection):
    if not table_exists(connection, "users"):
        raise RuntimeError("The users table was not found.")

    user_columns = table_columns(connection, "users")
    if "role" not in user_columns:
        connection.execute("ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT 'user'")
        print("Added users.role")
    else:
        print("users.role already exists")

    connection.execute("UPDATE users SET role = 'user' WHERE role IS NULL OR TRIM(role) = ''")
    connection.execute("CREATE INDEX IF NOT EXISTS idx_users_role ON users(role)")

    if table_exists(connection, "reviews"):
        review_columns = table_columns(connection, "reviews")
        if "title_id" in review_columns:
            connection.execute("CREATE INDEX IF NOT EXISTS idx_reviews_title_id ON reviews(title_id)")
        if "user_id" in review_columns:
            connection.execute("CREATE INDEX IF NOT EXISTS idx_reviews_user_id ON reviews(user_id)")

    connection.commit()


def resolve_db_path(value):
    if value:
        return Path(value).expanduser().resolve()

    for env_name in ["DATABASE_PATH", "IMDB_DATABASE_PATH", "SQLITE_DB_PATH"]:
        env_value = os.environ.get(env_name)
        if env_value:
            return Path(env_value).expanduser().resolve()

    try:
        sys.path.insert(0, str(Path.cwd()))
        from app import database

        for attribute in ["DATABASE_PATH", "DB_PATH", "DATABASE_FILE", "SQLITE_PATH"]:
            configured = getattr(database, attribute, None)
            if configured:
                return Path(str(configured)).expanduser().resolve()

        database_url = getattr(database, "DATABASE_URL", None)
        if isinstance(database_url, str) and database_url.startswith("sqlite:///"):
            return Path(database_url.removeprefix("sqlite:///")).expanduser().resolve()
    except Exception:
        pass

    candidates = [
        "imdb_backend.sqlite3",
        "imdb.sqlite3",
        "database.sqlite3",
        "backend.sqlite3",
        "db.sqlite3",
        "app.sqlite3",
    ]
    for candidate in candidates:
        path = Path.cwd() / candidate
        if path.exists():
            return path.resolve()

    return (Path.cwd() / "imdb_backend.sqlite3").resolve()


def table_exists(connection, table):
    row = connection.execute(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        (table,),
    ).fetchone()
    return row is not None


def table_columns(connection, table):
    rows = connection.execute(f"PRAGMA table_info({table})").fetchall()
    return {row["name"] for row in rows}


if __name__ == "__main__":
    raise SystemExit(main())
