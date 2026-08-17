import importlib
import os
import re
import sqlite3
from datetime import datetime
from pathlib import Path
from typing import Any

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from pydantic import BaseModel

from .. import database as database_module


router = APIRouter(prefix="/admin", tags=["admin"])

VALID_ROLES = {"user", "admin"}


class UserRoleUpdate(BaseModel):
    role: str


def admin_db_dependency():
    source = getattr(database_module, "get_db", None)
    if callable(source):
        resource = source()
        if hasattr(resource, "__enter__") and hasattr(resource, "__exit__"):
            with resource as db:
                yield db
            return
        if hasattr(resource, "__next__"):
            generator = resource
            try:
                db = next(generator)
                yield db
            finally:
                try:
                    next(generator)
                except StopIteration:
                    pass
                if hasattr(generator, "close"):
                    generator.close()
            return
        yield resource
        return

    connection = sqlite3.connect(str(resolve_database_path()), timeout=15)
    connection.row_factory = sqlite3.Row
    try:
        yield connection
    finally:
        connection.close()


def resolve_database_path():
    for attribute in ["DATABASE_PATH", "DB_PATH", "DATABASE_FILE", "SQLITE_PATH"]:
        configured = getattr(database_module, attribute, None)
        if configured:
            return Path(str(configured)).expanduser().resolve()

    database_url = getattr(database_module, "DATABASE_URL", None)
    if isinstance(database_url, str) and database_url.startswith("sqlite:///"):
        return Path(database_url.removeprefix("sqlite:///")).expanduser().resolve()

    for env_name in ["DATABASE_PATH", "IMDB_DATABASE_PATH", "SQLITE_DB_PATH"]:
        env_value = os.environ.get(env_name)
        if env_value:
            return Path(env_value).expanduser().resolve()

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


def current_user_dependency(
    db=Depends(admin_db_dependency),
    authorization: str | None = Header(default=None),
):
    ensure_admin_schema(db)
    token = bearer_token_from_header(authorization)
    payload = decode_token_with_available_helpers(token)
    user = resolve_user_from_token_payload(db, payload)
    if user is None:
        raise HTTPException(status_code=401, detail="Invalid authentication token.")
    return user


def require_admin(current_user=Depends(current_user_dependency)):
    if current_user.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Admin access is required.")
    return current_user


@router.get("/users")
def list_users(
    q: str = Query("", description="Optional username/email/name filter."),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    admin_user=Depends(require_admin),
    db=Depends(admin_db_dependency),
):
    ensure_admin_schema(db)
    columns = table_columns(db, "users")
    selected = [
        column
        for column in [
            "id",
            "username",
            "email",
            "full_name",
            "display_name",
            "avatar_url",
            "profile_image_url",
            "bio",
            "role",
            "created_at",
            "updated_at",
        ]
        if column in columns
    ]
    if not selected:
        selected = ["*"]

    where_sql = ""
    params: list[Any] = []
    search = q.strip()
    if search:
        searchable = [
            column
            for column in ["username", "email", "full_name", "display_name"]
            if column in columns
        ]
        if searchable:
            where_sql = " WHERE " + " OR ".join(
                f"LOWER({quote_identifier(column)}) LIKE ?" for column in searchable
            )
            params.extend([f"%{search.lower()}%"] * len(searchable))

    order_column = "created_at" if "created_at" in columns else "id"
    rows = fetchall_dicts(
        db,
        (
            f"SELECT {', '.join(quote_identifier(column) for column in selected)} "
            f"FROM users{where_sql} "
            f"ORDER BY {quote_identifier(order_column)} DESC "
            "LIMIT ? OFFSET ?"
        ),
        [*params, limit, offset],
    )
    total_row = fetchone_dict(
        db,
        f"SELECT COUNT(*) AS total FROM users{where_sql}",
        params,
    )

    return {
        "items": [public_user(row) for row in rows],
        "total": int(total_row.get("total", 0)) if total_row else len(rows),
        "limit": limit,
        "offset": offset,
    }


@router.patch("/users/{user_id}/role")
def update_user_role(
    user_id: str,
    payload: UserRoleUpdate,
    admin_user=Depends(require_admin),
    db=Depends(admin_db_dependency),
):
    ensure_admin_schema(db)
    role = payload.role.strip().lower()
    if role not in VALID_ROLES:
        raise HTTPException(status_code=400, detail="Role must be 'user' or 'admin'.")

    target = find_user_by_id(db, user_id)
    if target is None:
        raise HTTPException(status_code=404, detail="User was not found.")

    if str(target.get("id")) == str(admin_user.get("id")) and role != "admin":
        if admin_count(db) <= 1:
            raise HTTPException(status_code=400, detail="The last admin cannot be demoted.")

    if target.get("role") == "admin" and role != "admin" and admin_count(db) <= 1:
        raise HTTPException(status_code=400, detail="The last admin cannot be demoted.")

    db.execute("UPDATE users SET role = ? WHERE id = ?", (role, target.get("id")))
    commit(db)
    updated = find_user_by_id(db, str(target.get("id")))
    return {"user": public_user(updated)}


@router.delete("/users/{user_id}")
def delete_user(
    user_id: str,
    admin_user=Depends(require_admin),
    db=Depends(admin_db_dependency),
):
    ensure_admin_schema(db)
    target = find_user_by_id(db, user_id)
    if target is None:
        raise HTTPException(status_code=404, detail="User was not found.")

    if str(target.get("id")) == str(admin_user.get("id")):
        raise HTTPException(status_code=400, detail="Admins cannot delete their own account.")

    if target.get("role") == "admin" and admin_count(db) <= 1:
        raise HTTPException(status_code=400, detail="The last admin cannot be deleted.")

    deleted_from = delete_user_related_data(db, target.get("id"))
    db.execute("DELETE FROM users WHERE id = ?", (target.get("id"),))
    commit(db)
    return {
        "deleted_user_id": target.get("id"),
        "deleted_related_rows": deleted_from,
    }


@router.get("/reviews")
def list_reviews(
    title_id: str = Query("", description="Optional IMDb title id filter."),
    q: str = Query("", description="Optional text/user/title filter."),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    admin_user=Depends(require_admin),
    db=Depends(admin_db_dependency),
):
    ensure_admin_schema(db)
    if not table_exists(db, "reviews"):
        return {"items": [], "total": 0, "limit": limit, "offset": offset}

    columns = table_columns(db, "reviews")
    where_parts = []
    params: list[Any] = []

    if title_id.strip() and "title_id" in columns:
        where_parts.append("title_id = ?")
        params.append(title_id.strip())

    search = q.strip()
    if search:
        searchable = [column for column in ["text", "review", "title"] if column in columns]
        if searchable:
            where_parts.append(
                "("
                + " OR ".join(
                    f"LOWER({quote_identifier(column)}) LIKE ?" for column in searchable
                )
                + ")"
            )
            params.extend([f"%{search.lower()}%"] * len(searchable))

    where_sql = f" WHERE {' AND '.join(where_parts)}" if where_parts else ""
    order_column = "created_at" if "created_at" in columns else (
        "updated_at" if "updated_at" in columns else ("id" if "id" in columns else "title_id")
    )
    rows = fetchall_dicts(
        db,
        (
            f"SELECT * FROM reviews{where_sql} "
            f"ORDER BY {quote_identifier(order_column)} DESC "
            "LIMIT ? OFFSET ?"
        ),
        [*params, limit, offset],
    )
    total_row = fetchone_dict(
        db,
        f"SELECT COUNT(*) AS total FROM reviews{where_sql}",
        params,
    )

    return {
        "items": [review_payload(db, row) for row in rows],
        "total": int(total_row.get("total", 0)) if total_row else len(rows),
        "limit": limit,
        "offset": offset,
    }


@router.delete("/reviews/{review_id}")
def delete_review(
    review_id: str,
    admin_user=Depends(require_admin),
    db=Depends(admin_db_dependency),
):
    ensure_admin_schema(db)
    if not table_exists(db, "reviews"):
        raise HTTPException(status_code=404, detail="Review was not found.")

    columns = table_columns(db, "reviews")
    deleted = 0

    if "id" in columns and review_id.isdigit():
        cursor = db.execute("DELETE FROM reviews WHERE id = ?", (int(review_id),))
        deleted = cursor.rowcount
    elif "title_id" in columns and "user_id" in columns:
        title_id, user_id = parse_synthetic_review_id(review_id)
        if title_id is None or user_id is None:
            raise HTTPException(
                status_code=400,
                detail="Review id must be numeric or in title_id:user_id format.",
            )
        cursor = db.execute(
            "DELETE FROM reviews WHERE title_id = ? AND user_id = ?",
            (title_id, user_id),
        )
        deleted = cursor.rowcount
    else:
        raise HTTPException(status_code=500, detail="Reviews table cannot be addressed.")

    if deleted <= 0:
        raise HTTPException(status_code=404, detail="Review was not found.")

    commit(db)
    return {"deleted_review_id": review_id}


@router.get("/stats")
def admin_stats(admin_user=Depends(require_admin), db=Depends(admin_db_dependency)):
    ensure_admin_schema(db)
    return {
        "users": count_rows(db, "users"),
        "admins": admin_count(db),
        "watchlist_items": count_rows(db, "watchlist"),
        "ratings": count_rows(db, "ratings"),
        "reviews": count_rows(db, "reviews"),
        "progress_items": count_rows(db, "progress") + count_rows(db, "watch_progress"),
        "generated_at": datetime.utcnow().isoformat() + "Z",
    }


def bearer_token_from_header(value: str | None) -> str:
    if not value:
        raise HTTPException(status_code=401, detail="Authorization header is required.")
    match = re.match(r"Bearer\s+(.+)", value.strip(), flags=re.IGNORECASE)
    if not match:
        raise HTTPException(status_code=401, detail="Bearer token is required.")
    return match.group(1).strip()


def decode_token_with_available_helpers(token: str) -> dict[str, Any]:
    modules = candidate_auth_modules()

    for function_name in [
        "decode_access_token",
        "decode_token",
        "decode_jwt",
        "verify_access_token",
        "verify_token",
        "get_token_payload",
    ]:
        for module in modules:
            function = getattr(module, function_name, None)
            if callable(function):
                try:
                    payload = function(token)
                    if isinstance(payload, dict):
                        return payload
                    if isinstance(payload, (str, int)):
                        return {"sub": str(payload)}
                except HTTPException:
                    raise
                except TypeError:
                    continue
                except Exception:
                    continue

    secret = first_non_empty(
        *collect_setting_values(
            modules,
            [
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
            ],
        ),
        os.environ.get("SECRET_KEY"),
        os.environ.get("JWT_SECRET"),
        os.environ.get("JWT_SECRET_KEY"),
        os.environ.get("ACCESS_TOKEN_SECRET"),
        os.environ.get("ACCESS_TOKEN_SECRET_KEY"),
        os.environ.get("TOKEN_SECRET"),
        os.environ.get("TOKEN_SECRET_KEY"),
    )
    algorithm = first_non_empty(
        *collect_setting_values(
            modules,
            [
                "ALGORITHM",
                "JWT_ALGORITHM",
                "ACCESS_TOKEN_ALGORITHM",
                "TOKEN_ALGORITHM",
                "algorithm",
                "jwt_algorithm",
            ],
        ),
        os.environ.get("JWT_ALGORITHM"),
        os.environ.get("ACCESS_TOKEN_ALGORITHM"),
        "HS256",
    )

    if secret:
        for module_name in ["jose.jwt", "jwt"]:
            try:
                jwt_module = importlib.import_module(module_name)
                decoded = jwt_module.decode(token, secret, algorithms=[algorithm])
                if isinstance(decoded, dict):
                    return decoded
            except Exception:
                continue

    raise HTTPException(status_code=401, detail="Token cannot be decoded by the admin router.")


def candidate_auth_modules():
    modules = []
    for module_name in [
        "..security",
        "..config",
        ".auth",
        "..auth",
        ".users",
        "..dependencies",
        "..settings",
    ]:
        module = import_module_if_available(module_name)
        if module is not None:
            modules.append(module)
    return modules


def collect_setting_values(modules, names):
    values = []
    for module in modules:
        for name in names:
            values.append(getattr(module, name, None))
        for object_name in ["settings", "Settings", "config", "CONFIG"]:
            settings_object = getattr(module, object_name, None)
            if settings_object is None:
                continue
            for name in names:
                values.append(getattr(settings_object, name, None))
    return values


def import_module_if_available(module_name: str):
    try:
        return importlib.import_module(module_name, package=__package__)
    except Exception:
        return None


def first_non_empty(*values):
    for value in values:
        if value:
            return value
    return None


def resolve_user_from_dependency_value(db, value):
    if value is None:
        return None
    if isinstance(value, dict):
        nested = value.get("user")
        if isinstance(nested, dict):
            value = nested
        return find_user_by_identity(
            db,
            user_id=value.get("id") or value.get("user_id") or value.get("sub"),
            email=value.get("email"),
            username=value.get("username"),
        )
    if hasattr(value, "keys"):
        return resolve_user_from_dependency_value(db, row_to_dict(value))
    return find_user_by_identity(db, user_id=value)


def resolve_user_from_token_payload(db, payload):
    nested = payload.get("user")
    if isinstance(nested, dict):
        payload = nested
    return find_user_by_identity(
        db,
        user_id=payload.get("user_id") or payload.get("id") or payload.get("sub"),
        email=payload.get("email"),
        username=payload.get("username"),
    )


def find_user_by_identity(db, user_id=None, email=None, username=None):
    for candidate in [user_id, clean_server_user_id(user_id)]:
        if candidate is not None:
            user = find_user_by_id(db, str(candidate))
            if user is not None:
                return user

    columns = table_columns(db, "users")
    if email and "email" in columns:
        user = fetchone_dict(db, "SELECT * FROM users WHERE LOWER(email) = LOWER(?)", (email,))
        if user is not None:
            return user
    if username and "username" in columns:
        user = fetchone_dict(db, "SELECT * FROM users WHERE username = ?", (username,))
        if user is not None:
            return user
    return None


def find_user_by_id(db, user_id: str):
    if not table_exists(db, "users"):
        return None
    return fetchone_dict(db, "SELECT * FROM users WHERE id = ?", (clean_server_user_id(user_id),))


def clean_server_user_id(value):
    if value is None:
        return None
    text = str(value).strip()
    if text.startswith("server_"):
        text = text.removeprefix("server_")
    return text


def ensure_admin_schema(db):
    if not table_exists(db, "users"):
        return
    columns = table_columns(db, "users")
    if "role" not in columns:
        db.execute("ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT 'user'")
        commit(db)
    try:
        db.execute("CREATE INDEX IF NOT EXISTS idx_users_role ON users(role)")
        if table_exists(db, "reviews"):
            review_columns = table_columns(db, "reviews")
            if "title_id" in review_columns:
                db.execute("CREATE INDEX IF NOT EXISTS idx_reviews_title_id ON reviews(title_id)")
            if "user_id" in review_columns:
                db.execute("CREATE INDEX IF NOT EXISTS idx_reviews_user_id ON reviews(user_id)")
        commit(db)
    except Exception:
        pass


def admin_count(db):
    if not table_exists(db, "users") or "role" not in table_columns(db, "users"):
        return 0
    row = fetchone_dict(db, "SELECT COUNT(*) AS count FROM users WHERE role = 'admin'")
    return int(row.get("count", 0)) if row else 0


def delete_user_related_data(db, user_id):
    result = {}
    for table in list_tables(db):
        if table == "users":
            continue
        columns = table_columns(db, table)
        if "user_id" not in columns:
            continue
        cursor = db.execute(
            f"DELETE FROM {quote_identifier(table)} WHERE user_id = ?",
            (user_id,),
        )
        if cursor.rowcount:
            result[table] = cursor.rowcount
    return result


def public_user(row):
    if row is None:
        return None
    return {
        "id": row.get("id"),
        "username": row.get("username"),
        "email": row.get("email"),
        "full_name": row.get("full_name") or row.get("display_name"),
        "display_name": row.get("display_name") or row.get("full_name") or row.get("username"),
        "avatar_url": row.get("avatar_url") or row.get("profile_image_url"),
        "profile_image_url": row.get("profile_image_url") or row.get("avatar_url"),
        "bio": row.get("bio"),
        "role": row.get("role") or "user",
        "created_at": row.get("created_at"),
        "updated_at": row.get("updated_at"),
    }


def review_payload(db, row):
    user = find_user_by_id(db, str(row.get("user_id"))) if row.get("user_id") is not None else None
    review_id = row.get("id")
    if review_id is None and row.get("title_id") is not None and row.get("user_id") is not None:
        review_id = f"{row.get('title_id')}:{row.get('user_id')}"
    return {
        "id": review_id,
        "title_id": row.get("title_id"),
        "title": row.get("title"),
        "user_id": row.get("user_id"),
        "username": (user or {}).get("username") or row.get("username"),
        "full_name": (user or {}).get("full_name") or (user or {}).get("display_name"),
        "email": (user or {}).get("email"),
        "text": row.get("text") or row.get("review"),
        "contains_spoiler": bool(row.get("contains_spoiler") or row.get("has_spoiler") or False),
        "created_at": row.get("created_at"),
        "updated_at": row.get("updated_at"),
    }


def parse_synthetic_review_id(value: str):
    for separator in [":", "|", ","]:
        if separator in value:
            title_id, user_id = value.split(separator, 1)
            title_id = title_id.strip()
            user_id = user_id.strip()
            if title_id and user_id:
                return title_id, clean_server_user_id(user_id)
    return None, None


def count_rows(db, table):
    if not table_exists(db, table):
        return 0
    row = fetchone_dict(db, f"SELECT COUNT(*) AS count FROM {quote_identifier(table)}")
    return int(row.get("count", 0)) if row else 0


def table_exists(db, table):
    row = fetchone_dict(
        db,
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        (table,),
    )
    return row is not None


def list_tables(db):
    rows = fetchall_dicts(
        db,
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
    )
    return [row["name"] for row in rows if row.get("name")]


def table_columns(db, table):
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", table):
        return set()
    rows = fetchall_dicts(db, f"PRAGMA table_info({quote_identifier(table)})")
    return {row["name"] for row in rows if row.get("name")}


def quote_identifier(value):
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", value):
        raise ValueError(f"Unsafe SQL identifier: {value}")
    return f'"{value}"'


def fetchone_dict(db, sql, params=()):
    cursor = db.execute(sql, params)
    row = cursor.fetchone()
    return row_to_dict(row, cursor.description) if row is not None else None


def fetchall_dicts(db, sql, params=()):
    cursor = db.execute(sql, params)
    return [row_to_dict(row, cursor.description) for row in cursor.fetchall()]


def row_to_dict(row, description=None):
    if isinstance(row, dict):
        return dict(row)
    if hasattr(row, "keys"):
        return {key: row[key] for key in row.keys()}
    if description is not None:
        return {description[index][0]: row[index] for index in range(len(description))}
    return {}


def commit(db):
    if hasattr(db, "commit"):
        db.commit()
