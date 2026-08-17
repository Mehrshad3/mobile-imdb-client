import argparse
import os
import sqlite3
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description="Promote or demote a backend user.")
    parser.add_argument("identifier", nargs="?", help="User email or username.")
    parser.add_argument("--db", help="Path to the main backend SQLite database.")
    parser.add_argument("--role", choices=["user", "admin"], default="admin")
    parser.add_argument("--list-admins", action="store_true")
    args = parser.parse_args()

    db_path = resolve_db_path(args.db)
    if not db_path.exists():
        print(f"Database file was not found: {db_path}")
        return 2

    connection = sqlite3.connect(str(db_path))
    try:
        connection.row_factory = sqlite3.Row
        ensure_schema(connection)

        if args.list_admins:
            list_admins(connection)
            return 0

        if not args.identifier:
            print("Email or username is required.")
            return 2

        user = find_user(connection, args.identifier)
        if user is None:
            print(f"User was not found: {args.identifier}")
            return 1

        if user["role"] == "admin" and args.role != "admin" and admin_count(connection) <= 1:
            print("Cannot demote the last admin.")
            return 1

        connection.execute("UPDATE users SET role = ? WHERE id = ?", (args.role, user["id"]))
        connection.commit()
        updated = find_user_by_id(connection, user["id"])
        print(
            "Updated user:",
            f"id={updated['id']}",
            f"username={updated_value(updated, 'username')}",
            f"email={updated_value(updated, 'email')}",
            f"role={updated['role']}",
        )
    finally:
        connection.close()

    return 0


def ensure_schema(connection):
    if not table_exists(connection, "users"):
        raise RuntimeError("The users table was not found.")
    if "role" not in table_columns(connection, "users"):
        connection.execute("ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT 'user'")
        connection.commit()


def list_admins(connection):
    rows = connection.execute(
        "SELECT id, username, email, role FROM users WHERE role = 'admin' ORDER BY id"
    ).fetchall()
    if not rows:
        print("No admin users found.")
        return
    for row in rows:
        print(
            f"id={row['id']}",
            f"username={updated_value(row, 'username')}",
            f"email={updated_value(row, 'email')}",
            f"role={row['role']}",
        )


def find_user(connection, identifier):
    text = identifier.strip()
    columns = table_columns(connection, "users")
    checks = []
    params = []
    if "email" in columns:
        checks.append("LOWER(email) = LOWER(?)")
        params.append(text)
    if "username" in columns:
        checks.append("username = ?")
        params.append(text)
    if text.isdigit() and "id" in columns:
        checks.append("id = ?")
        params.append(int(text))
    if not checks:
        return None
    return connection.execute(
        f"SELECT * FROM users WHERE {' OR '.join(checks)} LIMIT 1",
        params,
    ).fetchone()


def find_user_by_id(connection, user_id):
    return connection.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()


def admin_count(connection):
    row = connection.execute("SELECT COUNT(*) AS count FROM users WHERE role = 'admin'").fetchone()
    return int(row["count"]) if row else 0


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


def updated_value(row, key):
    try:
        value = row[key]
    except Exception:
        value = None
    return value or "-"


if __name__ == "__main__":
    raise SystemExit(main())
