import re

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from ..database import get_db
from ..security import get_current_user

router = APIRouter(prefix="/users", tags=["users"])


class UpdateProfileRequest(BaseModel):
    full_name: str | None = None
    username: str | None = None
    avatar_url: str | None = None
    bio: str | None = None


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


def validate_username(username: str):
    if not re.match(r"^[A-Za-z0-9_]{3,24}$", username):
        raise HTTPException(
            status_code=422,
            detail="Username must be 3-24 characters and contain only letters, numbers, or _",
        )


@router.get("/me")
def me(user=Depends(get_current_user)):
    return {"user": public_user(user)}


@router.patch("/me")
def update_me(payload: UpdateProfileRequest, user=Depends(get_current_user)):
    full_name = payload.full_name.strip() if payload.full_name is not None else user["full_name"]
    username = payload.username.strip() if payload.username is not None else user["username"]
    avatar_url = payload.avatar_url.strip() if payload.avatar_url is not None else user["avatar_url"]
    bio = payload.bio.strip() if payload.bio is not None else user["bio"]

    if not full_name:
        raise HTTPException(status_code=422, detail="Full name is required")

    validate_username(username)

    with get_db() as conn:
        duplicate = conn.execute(
            "SELECT id FROM users WHERE username = ? AND id != ?",
            (username, user["id"]),
        ).fetchone()

        if duplicate:
            raise HTTPException(status_code=409, detail="Username already exists")

        conn.execute(
            """
            UPDATE users
            SET full_name = ?, username = ?, avatar_url = ?, bio = ?
            WHERE id = ?
            """,
            (full_name, username, avatar_url, bio, user["id"]),
        )

        updated = conn.execute(
            "SELECT * FROM users WHERE id = ?",
            (user["id"],),
        ).fetchone()

    return {"user": public_user(updated)}
