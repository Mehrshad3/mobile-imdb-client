import json
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from ..database import get_db
from ..security import get_current_user

router = APIRouter(prefix="/watchlist", tags=["watchlist"])

VALID_STATUSES = {"planned", "watching", "watched", "stopped", "dropped"}


class WatchlistCreate(BaseModel):
    title_id: str
    title: str
    type: str | None = None
    year: int | None = None
    end_year: int | None = None
    image_url: str | None = None
    subtitle: str | None = None
    imdb_rating: float | None = None
    vote_count: int | None = None
    genres: list[str] = []
    runtime_minutes: int | None = None
    can_have_episodes: bool = False
    status: str = "planned"
    favorite: bool = False


class WatchlistUpdate(BaseModel):
    title: str | None = None
    type: str | None = None
    year: int | None = None
    end_year: int | None = None
    image_url: str | None = None
    subtitle: str | None = None
    imdb_rating: float | None = None
    vote_count: int | None = None
    genres: list[str] | None = None
    runtime_minutes: int | None = None
    can_have_episodes: bool | None = None
    status: str | None = None
    favorite: bool | None = None


def now_iso():
    return datetime.utcnow().isoformat()


def validate_status(status: str):
    if status not in VALID_STATUSES:
        raise HTTPException(status_code=422, detail="Invalid watch status")


def row_to_item(row):
    return {
        "id": row["id"],
        "user_id": row["user_id"],
        "title_id": row["title_id"],
        "title": row["title"],
        "type": row["type"],
        "year": row["year"],
        "end_year": row["end_year"],
        "image_url": row["image_url"],
        "subtitle": row["subtitle"],
        "imdb_rating": row["imdb_rating"],
        "vote_count": row["vote_count"],
        "genres": json.loads(row["genres"] or "[]"),
        "runtime_minutes": row["runtime_minutes"],
        "can_have_episodes": bool(row["can_have_episodes"]),
        "status": row["status"],
        "favorite": bool(row["favorite"]),
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
    }


@router.get("")
def list_watchlist(user=Depends(get_current_user)):
    with get_db() as conn:
        rows = conn.execute(
            """
            SELECT * FROM watchlist_items
            WHERE user_id = ?
            ORDER BY updated_at DESC
            """,
            (user["id"],),
        ).fetchall()

    return {"items": [row_to_item(row) for row in rows]}


@router.post("")
def add_watchlist_item(payload: WatchlistCreate, user=Depends(get_current_user)):
    title_id = payload.title_id.strip()
    title = payload.title.strip()
    status = payload.status.strip()

    if not title_id:
        raise HTTPException(status_code=422, detail="title_id is required")
    if not title:
        raise HTTPException(status_code=422, detail="title is required")

    validate_status(status)

    timestamp = now_iso()

    with get_db() as conn:
        conn.execute(
            """
            INSERT INTO watchlist_items
            (
                user_id, title_id, title, type, year, end_year, image_url,
                subtitle, imdb_rating, vote_count, genres, runtime_minutes,
                can_have_episodes, status, favorite, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(user_id, title_id) DO UPDATE SET
                title = excluded.title,
                type = excluded.type,
                year = excluded.year,
                end_year = excluded.end_year,
                image_url = excluded.image_url,
                subtitle = excluded.subtitle,
                imdb_rating = excluded.imdb_rating,
                vote_count = excluded.vote_count,
                genres = excluded.genres,
                runtime_minutes = excluded.runtime_minutes,
                can_have_episodes = excluded.can_have_episodes,
                status = excluded.status,
                favorite = excluded.favorite,
                updated_at = excluded.updated_at
            """,
            (
                user["id"],
                title_id,
                title,
                payload.type,
                payload.year,
                payload.end_year,
                payload.image_url,
                payload.subtitle,
                payload.imdb_rating,
                payload.vote_count,
                json.dumps(payload.genres),
                payload.runtime_minutes,
                1 if payload.can_have_episodes else 0,
                status,
                1 if payload.favorite else 0,
                timestamp,
                timestamp,
            ),
        )

        row = conn.execute(
            "SELECT * FROM watchlist_items WHERE user_id = ? AND title_id = ?",
            (user["id"], title_id),
        ).fetchone()

    return {"item": row_to_item(row)}


@router.patch("/{title_id}")
def update_watchlist_item(
    title_id: str,
    payload: WatchlistUpdate,
    user=Depends(get_current_user),
):
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM watchlist_items WHERE user_id = ? AND title_id = ?",
            (user["id"], title_id),
        ).fetchone()

        if row is None:
            raise HTTPException(status_code=404, detail="Watchlist item not found")

        status = payload.status if payload.status is not None else row["status"]
        validate_status(status)

        title = payload.title.strip() if payload.title is not None else row["title"]
        if not title:
            raise HTTPException(status_code=422, detail="title is required")

        genres = (
            json.dumps(payload.genres)
            if payload.genres is not None
            else row["genres"]
        )

        conn.execute(
            """
            UPDATE watchlist_items
            SET
                title = ?,
                type = ?,
                year = ?,
                end_year = ?,
                image_url = ?,
                subtitle = ?,
                imdb_rating = ?,
                vote_count = ?,
                genres = ?,
                runtime_minutes = ?,
                can_have_episodes = ?,
                status = ?,
                favorite = ?,
                updated_at = ?
            WHERE user_id = ? AND title_id = ?
            """,
            (
                title,
                payload.type if payload.type is not None else row["type"],
                payload.year if payload.year is not None else row["year"],
                payload.end_year if payload.end_year is not None else row["end_year"],
                payload.image_url if payload.image_url is not None else row["image_url"],
                payload.subtitle if payload.subtitle is not None else row["subtitle"],
                payload.imdb_rating if payload.imdb_rating is not None else row["imdb_rating"],
                payload.vote_count if payload.vote_count is not None else row["vote_count"],
                genres,
                payload.runtime_minutes if payload.runtime_minutes is not None else row["runtime_minutes"],
                (
                    1 if payload.can_have_episodes else 0
                ) if payload.can_have_episodes is not None else row["can_have_episodes"],
                status,
                (
                    1 if payload.favorite else 0
                ) if payload.favorite is not None else row["favorite"],
                now_iso(),
                user["id"],
                title_id,
            ),
        )

        updated = conn.execute(
            "SELECT * FROM watchlist_items WHERE user_id = ? AND title_id = ?",
            (user["id"], title_id),
        ).fetchone()

    return {"item": row_to_item(updated)}


@router.delete("/{title_id}")
def delete_watchlist_item(title_id: str, user=Depends(get_current_user)):
    with get_db() as conn:
        cursor = conn.execute(
            "DELETE FROM watchlist_items WHERE user_id = ? AND title_id = ?",
            (user["id"], title_id),
        )

    if cursor.rowcount == 0:
        raise HTTPException(status_code=404, detail="Watchlist item not found")

    return {"message": "Watchlist item deleted"}
