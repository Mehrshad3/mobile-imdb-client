import random
import re
import sqlite3
from datetime import datetime, timedelta

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..database import get_db
from ..email_otp import send_otp_email
from ..security import create_access_token, hash_password, verify_password

router = APIRouter(prefix="/auth", tags=["auth"])


class RegisterRequest(BaseModel):
    full_name: str
    username: str
    email: str
    password: str
    avatar_url: str | None = None
    bio: str | None = None


class ConfirmRegister(BaseModel):
    email: str
    code: str


class LoginRequest(BaseModel):
    email: str
    password: str


class ResetRequest(BaseModel):
    email: str


class ResetConfirm(BaseModel):
    email: str
    code: str
    new_password: str


def now_iso():
    return datetime.utcnow().isoformat()


def normalize_email(email: str) -> str:
    return email.strip().lower()


def normalize_username(username: str) -> str:
    return username.strip()


def validate_email(email: str):
    if not re.match(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", email):
        raise HTTPException(status_code=422, detail="Invalid email")


def validate_username(username: str):
    if not re.match(r"^[A-Za-z0-9_]{3,24}$", username):
        raise HTTPException(
            status_code=422,
            detail="Username must be 3-24 characters and contain only letters, numbers, or _",
        )


def validate_password(password: str, username: str = "", email: str = ""):
    if len(password) < 8:
        raise HTTPException(status_code=422, detail="Password must be at least 8 characters")
    if not re.search(r"[A-Za-z]", password) or not re.search(r"\d", password):
        raise HTTPException(status_code=422, detail="Password must contain letters and numbers")

    lower = password.lower()
    if "123456" in lower or "password" in lower or "qwerty" in lower:
        raise HTTPException(status_code=422, detail="Password is too simple")

    if username and username.lower() in lower:
        raise HTTPException(status_code=422, detail="Password must not contain username")

    email_name = email.split("@")[0].lower()
    if email_name and email_name in lower:
        raise HTTPException(status_code=422, detail="Password must not contain email name")


def public_user(row):
    return {
        "id": row["id"],
        "full_name": row["full_name"],
        "username": row["username"],
        "email": row["email"],
        "avatar_url": row["avatar_url"],
        "bio": row["bio"],
        "role": row["role"],
        "created_at": row["created_at"],
    }


def create_otp(email: str, purpose: str):
    code = str(random.randint(100000, 999999))
    expires_at = (datetime.utcnow() + timedelta(minutes=15)).isoformat()

    with get_db() as conn:
        conn.execute(
            "DELETE FROM otp_codes WHERE email = ? AND purpose = ?",
            (email, purpose),
        )
        conn.execute(
            """
            INSERT INTO otp_codes (email, purpose, code, expires_at, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            (email, purpose, code, expires_at, now_iso()),
        )

    send_otp_email(email, code)


def verify_otp(email: str, purpose: str, code: str):
    with get_db() as conn:
        otp = conn.execute(
            """
            SELECT * FROM otp_codes
            WHERE email = ? AND purpose = ? AND code = ?
            ORDER BY id DESC
            LIMIT 1
            """,
            (email, purpose, code.strip()),
        ).fetchone()

        if otp is None:
            raise HTTPException(status_code=400, detail="Invalid OTP")

        if otp["expires_at"] < now_iso():
            conn.execute(
                "DELETE FROM otp_codes WHERE email = ? AND purpose = ?",
                (email, purpose),
            )
            raise HTTPException(status_code=400, detail="OTP expired")

        conn.execute(
            "DELETE FROM otp_codes WHERE email = ? AND purpose = ?",
            (email, purpose),
        )


@router.post("/register/request-otp")
def register_request_otp(payload: RegisterRequest):
    email = normalize_email(payload.email)
    username = normalize_username(payload.username)
    full_name = payload.full_name.strip()

    if not full_name:
        raise HTTPException(status_code=422, detail="Full name is required")

    validate_email(email)
    validate_username(username)
    validate_password(payload.password, username, email)

    with get_db() as conn:
        exists = conn.execute(
            "SELECT id FROM users WHERE email = ? OR username = ?",
            (email, username),
        ).fetchone()

        if exists:
            raise HTTPException(status_code=409, detail="Email or username already exists")

        password_hash = hash_password(payload.password)
        expires_at = (datetime.utcnow() + timedelta(minutes=15)).isoformat()

        conn.execute(
            "DELETE FROM pending_registrations WHERE email = ?",
            (email,),
        )
        conn.execute(
            """
            INSERT INTO pending_registrations
            (email, full_name, username, password_hash, avatar_url, bio, expires_at, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                email,
                full_name,
                username,
                password_hash,
                payload.avatar_url,
                payload.bio,
                expires_at,
                now_iso(),
            ),
        )

    create_otp(email, "register")
    return {"message": "OTP sent"}


@router.post("/register/confirm")
def register_confirm(payload: ConfirmRegister):
    email = normalize_email(payload.email)
    verify_otp(email, "register", payload.code)

    with get_db() as conn:
        pending = conn.execute(
            "SELECT * FROM pending_registrations WHERE email = ?",
            (email,),
        ).fetchone()

        if pending is None:
            raise HTTPException(status_code=400, detail="Registration data expired")

        if pending["expires_at"] < now_iso():
            conn.execute(
                "DELETE FROM pending_registrations WHERE email = ?",
                (email,),
            )
            raise HTTPException(status_code=400, detail="Registration expired")

        try:
            cursor = conn.execute(
                """
                INSERT INTO users
                (full_name, username, email, password_hash, avatar_url, bio, role, created_at)
                VALUES (?, ?, ?, ?, ?, ?, 'user', ?)
                """,
                (
                    pending["full_name"],
                    pending["username"],
                    pending["email"],
                    pending["password_hash"],
                    pending["avatar_url"],
                    pending["bio"],
                    now_iso(),
                ),
            )
        except sqlite3.IntegrityError:
            raise HTTPException(status_code=409, detail="Email or username already exists")

        conn.execute(
            "DELETE FROM pending_registrations WHERE email = ?",
            (email,),
        )

        user = conn.execute(
            "SELECT * FROM users WHERE id = ?",
            (cursor.lastrowid,),
        ).fetchone()

    return {
        "access_token": create_access_token(user["id"], user["role"]),
        "token_type": "bearer",
        "user": public_user(user),
    }


@router.post("/login")
def login(payload: LoginRequest):
    email = normalize_email(payload.email)

    with get_db() as conn:
        user = conn.execute(
            "SELECT * FROM users WHERE email = ?",
            (email,),
        ).fetchone()

    if user is None or not verify_password(payload.password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid email or password")

    return {
        "access_token": create_access_token(user["id"], user["role"]),
        "token_type": "bearer",
        "user": public_user(user),
    }


@router.post("/password-reset/request")
def password_reset_request(payload: ResetRequest):
    email = normalize_email(payload.email)

    with get_db() as conn:
        user = conn.execute(
            "SELECT id FROM users WHERE email = ?",
            (email,),
        ).fetchone()

    if user is None:
        raise HTTPException(status_code=404, detail="User not found")

    create_otp(email, "password_reset")
    return {"message": "OTP sent"}


@router.post("/password-reset/confirm")
def password_reset_confirm(payload: ResetConfirm):
    email = normalize_email(payload.email)

    with get_db() as conn:
        user = conn.execute(
            "SELECT * FROM users WHERE email = ?",
            (email,),
        ).fetchone()

    if user is None:
        raise HTTPException(status_code=404, detail="User not found")

    validate_password(payload.new_password, user["username"], email)
    verify_otp(email, "password_reset", payload.code)

    with get_db() as conn:
        conn.execute(
            "UPDATE users SET password_hash = ? WHERE email = ?",
            (hash_password(payload.new_password), email),
        )

    return {"message": "Password changed"}
