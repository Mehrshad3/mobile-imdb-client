import argparse
import importlib
import json
import os
import sqlite3
import sys
from pathlib import Path


MODULE_NAMES = [
    "app.security",
    "app.config",
    "app.routers.auth",
    "app.auth",
    "app.routers.users",
    "app.dependencies",
    "app.settings",
]

SECRET_NAMES = [
    "SECRET_KEY",
    "JWT_SECRET",
    "JWT_SECRET_KEY",
    "ACCESS_TOKEN_SECRET",
    "ACCESS_TOKEN_SECRET_KEY",
    "JWT_ACCESS_SECRET",
    "JWT_ACCESS_SECRET_KEY",
    "TOKEN_SECRET",
    "TOKEN_SECRET_KEY",
    "AUTH_SECRET",
    "AUTH_SECRET_KEY",
    "APP_SECRET_KEY",
    "secret_key",
    "jwt_secret",
    "jwt_secret_key",
]

ALGORITHM_NAMES = [
    "ALGORITHM",
    "JWT_ALGORITHM",
    "ACCESS_TOKEN_ALGORITHM",
    "TOKEN_ALGORITHM",
    "algorithm",
    "jwt_algorithm",
]

DECODE_FUNCTION_NAMES = [
    "decode_access_token",
    "decode_token",
    "decode_jwt",
    "verify_access_token",
    "verify_token",
    "get_token_payload",
]


def main():
    parser = argparse.ArgumentParser(description="Diagnose admin auth/database setup.")
    parser.add_argument("--token", help="Optional access token to test local decode.")
    parser.add_argument("--db", help="Optional SQLite database path.")
    args = parser.parse_args()

    sys.path.insert(0, str(Path.cwd()))

    print("Python:", sys.version.split()[0])
    print("CWD:", Path.cwd())
    print()

    modules = load_modules()
    inspect_auth_modules(modules)
    inspect_jwt_libraries()
    inspect_database(args.db)

    if args.token:
        print()
        inspect_token_decode(args.token, modules)

    print()
    inspect_app_import()
    return 0


def load_modules():
    modules = {}
    for name in MODULE_NAMES:
        try:
            modules[name] = importlib.import_module(name)
            print(f"[OK] import {name}")
        except Exception as error:
            modules[name] = None
            print(f"[MISS] import {name}: {error.__class__.__name__}: {error}")
    print()
    return modules


def inspect_auth_modules(modules):
    print("Auth/config candidates")
    for module_name, module in modules.items():
        if module is None:
            continue
        functions = [name for name in DECODE_FUNCTION_NAMES if callable(getattr(module, name, None))]
        secrets = []
        algorithms = []
        for name in SECRET_NAMES:
            if value_exists(getattr(module, name, None)):
                secrets.append(name)
        for name in ALGORITHM_NAMES:
            if value_exists(getattr(module, name, None)):
                algorithms.append(name)
        for object_name in ["settings", "Settings", "config", "CONFIG"]:
            settings_object = getattr(module, object_name, None)
            if settings_object is None:
                continue
            for name in SECRET_NAMES:
                if value_exists(getattr(settings_object, name, None)):
                    secrets.append(f"{object_name}.{name}")
            for name in ALGORITHM_NAMES:
                if value_exists(getattr(settings_object, name, None)):
                    algorithms.append(f"{object_name}.{name}")
        print(
            f"- {module_name}: "
            f"decode_functions={functions or '-'} "
            f"secret_fields={secrets or '-'} "
            f"algorithm_fields={algorithms or '-'}"
        )

    env_secrets = [name for name in SECRET_NAMES if value_exists(os.environ.get(name))]
    env_algorithms = [name for name in ALGORITHM_NAMES if value_exists(os.environ.get(name))]
    print(f"- environment: secret_fields={env_secrets or '-'} algorithm_fields={env_algorithms or '-'}")


def inspect_jwt_libraries():
    print()
    print("JWT libraries")
    for name in ["jose.jwt", "jwt"]:
        try:
            importlib.import_module(name)
            print(f"[OK] import {name}")
        except Exception as error:
            print(f"[MISS] import {name}: {error.__class__.__name__}: {error}")


def inspect_database(db_path):
    print()
    print("Database")
    path = resolve_db_path(db_path)
    print("path:", path)
    if not path.exists():
        print("[FAIL] database file was not found")
        return

    connection = sqlite3.connect(str(path))
    connection.row_factory = sqlite3.Row
    try:
        tables = [
            row["name"]
            for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
            ).fetchall()
        ]
        print("tables:", ", ".join(tables) or "-")
        for table in ["users", "reviews", "ratings", "watchlist", "progress", "watch_progress"]:
            if table not in tables:
                continue
            columns = [
                row["name"]
                for row in connection.execute(f"PRAGMA table_info({table})").fetchall()
            ]
            count = connection.execute(f"SELECT COUNT(*) AS count FROM {table}").fetchone()["count"]
            print(f"- {table}: rows={count} columns={columns}")
        if "users" in tables:
            admin_count = connection.execute(
                "SELECT COUNT(*) AS count FROM users WHERE role='admin'"
            ).fetchone()["count"]
            print("admin_count:", admin_count)
    finally:
        connection.close()


def inspect_token_decode(token, modules):
    print("Token decode")
    for module_name, module in modules.items():
        if module is None:
            continue
        for function_name in DECODE_FUNCTION_NAMES:
            function = getattr(module, function_name, None)
            if not callable(function):
                continue
            try:
                payload = function(token)
                print(f"[OK] {module_name}.{function_name}: {safe_payload(payload)}")
                return
            except TypeError as error:
                print(f"[SKIP] {module_name}.{function_name}: TypeError: {error}")
            except Exception as error:
                print(f"[FAIL] {module_name}.{function_name}: {error.__class__.__name__}: {error}")

    secret = first_non_empty(*collect_setting_values(modules, SECRET_NAMES), *env_values(SECRET_NAMES))
    algorithm = first_non_empty(*collect_setting_values(modules, ALGORITHM_NAMES), *env_values(ALGORITHM_NAMES), "HS256")
    if not secret:
        print("[FAIL] no secret candidate found")
        return

    for jwt_module_name in ["jose.jwt", "jwt"]:
        try:
            jwt_module = importlib.import_module(jwt_module_name)
            payload = jwt_module.decode(token, secret, algorithms=[algorithm])
            print(f"[OK] {jwt_module_name}.decode with discovered secret: {safe_payload(payload)}")
            return
        except Exception as error:
            print(f"[FAIL] {jwt_module_name}.decode: {error.__class__.__name__}: {error}")


def inspect_app_import():
    print("FastAPI app import")
    try:
        from app.main import app

        routes = sorted(getattr(route, "path", "?") for route in app.routes)
        print("[OK] from app.main import app")
        print("admin routes:", [route for route in routes if route.startswith("/admin")])
    except Exception as error:
        print(f"[FAIL] app import: {error.__class__.__name__}: {error}")


def resolve_db_path(value):
    if value:
        return Path(value).expanduser().resolve()

    for env_name in ["DATABASE_PATH", "IMDB_DATABASE_PATH", "SQLITE_DB_PATH"]:
        env_value = os.environ.get(env_name)
        if env_value:
            return Path(env_value).expanduser().resolve()

    try:
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

    for candidate in [
        "imdb_backend.sqlite3",
        "imdb.sqlite3",
        "database.sqlite3",
        "backend.sqlite3",
        "db.sqlite3",
        "app.sqlite3",
    ]:
        path = Path.cwd() / candidate
        if path.exists():
            return path.resolve()
    return (Path.cwd() / "imdb_backend.sqlite3").resolve()


def collect_setting_values(modules, names):
    values = []
    for module in modules.values():
        if module is None:
            continue
        for name in names:
            values.append(getattr(module, name, None))
        for object_name in ["settings", "Settings", "config", "CONFIG"]:
            settings_object = getattr(module, object_name, None)
            if settings_object is None:
                continue
            for name in names:
                values.append(getattr(settings_object, name, None))
    return values


def env_values(names):
    return [os.environ.get(name) for name in names]


def first_non_empty(*values):
    for value in values:
        if value:
            return value
    return None


def value_exists(value):
    return value is not None and str(value).strip() != ""


def safe_payload(payload):
    if isinstance(payload, dict):
        cleaned = {
            key: value
            for key, value in payload.items()
            if "secret" not in str(key).lower() and "password" not in str(key).lower()
        }
        return json.dumps(cleaned, ensure_ascii=False)
    return repr(payload)


if __name__ == "__main__":
    raise SystemExit(main())
