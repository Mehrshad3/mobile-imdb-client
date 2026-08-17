from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from ..database import get_db
from ..security import get_current_user

router = APIRouter(prefix="/titles", tags=["ratings and reviews"])


class RatingRequest(BaseModel):
    rating: int = Field(..., ge=1, le=10)
    title: str | None = None
    year: str | None = None
    poster_url: str | None = None
    media_type: str | None = None


class ReviewRequest(BaseModel):
    text: str
    contains_spoiler: bool = False
    title: str | None = None
    year: str | None = None
    poster_url: str | None = None
    media_type: str | None = None


def now_utc():
    return datetime.utcnow().isoformat(timespec="seconds") + "Z"


def clean_title_id(title_id: str):
    value = title_id.strip()
    if not value:
        raise HTTPException(status_code=400, detail="title_id is required")
    return value


def ensure_tables(db):
    db.execute(
        """
        CREATE TABLE IF NOT EXISTS ratings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            title_id TEXT NOT NULL,
            title TEXT,
            year TEXT,
            poster_url TEXT,
            media_type TEXT,
            rating INTEGER NOT NULL CHECK(rating >= 1 AND rating <= 10),
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(user_id, title_id),
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        )
        """
    )
    db.execute(
        """
        CREATE TABLE IF NOT EXISTS reviews (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            title_id TEXT NOT NULL,
            title TEXT,
            year TEXT,
            poster_url TEXT,
            media_type TEXT,
            text TEXT NOT NULL,
            contains_spoiler INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(user_id, title_id),
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        )
        """
    )
    db.commit()


def rating_summary(db, title_id: str):
    row = db.execute(
        """
        SELECT COUNT(*) AS rating_count, AVG(rating) AS average_rating
        FROM ratings
        WHERE title_id = ?
        """,
        (title_id,),
    ).fetchone()

    count = int(row["rating_count"] or 0)
    average = row["average_rating"]

    return {
        "title_id": title_id,
        "rating_count": count,
        "average_rating": round(float(average), 2) if average is not None else None,
    }


def get_my_rating(db, user_id: int, title_id: str):
    row = db.execute(
        """
        SELECT rating, created_at, updated_at
        FROM ratings
        WHERE user_id = ? AND title_id = ?
        """,
        (user_id, title_id),
    ).fetchone()

    return dict(row) if row else None


def get_my_review(db, user_id: int, title_id: str):
    row = db.execute(
        """
        SELECT id, title_id, text, contains_spoiler, created_at, updated_at
        FROM reviews
        WHERE user_id = ? AND title_id = ?
        """,
        (user_id, title_id),
    ).fetchone()

    if not row:
        return None

    data = dict(row)
    data["contains_spoiler"] = bool(data["contains_spoiler"])
    return data


def list_reviews(db, title_id: str, current_user_id: int):
    rows = db.execute(
        """
        SELECT
            reviews.id,
            reviews.user_id,
            users.username,
            users.full_name,
            reviews.title_id,
            reviews.title,
            reviews.year,
            reviews.poster_url,
            reviews.media_type,
            reviews.text,
            reviews.contains_spoiler,
            reviews.created_at,
            reviews.updated_at
        FROM reviews
        JOIN users ON users.id = reviews.user_id
        WHERE reviews.title_id = ?
        ORDER BY reviews.updated_at DESC
        """,
        (title_id,),
    ).fetchall()

    result = []
    for row in rows:
        item = dict(row)
        item["contains_spoiler"] = bool(item["contains_spoiler"])
        item["is_mine"] = item["user_id"] == current_user_id
        result.append(item)

    return result


@router.get("/me/ratings")
def get_my_ratings(current_user=Depends(get_current_user)):
    with get_db() as db:
        ensure_tables(db)

        rows = db.execute(
            """
            SELECT title_id, title, year, poster_url, media_type, rating, created_at, updated_at
            FROM ratings
            WHERE user_id = ?
            ORDER BY updated_at DESC
            """,
            (current_user["id"],),
        ).fetchall()

        return {"items": [dict(row) for row in rows]}


@router.get("/me/reviews")
def get_my_reviews(current_user=Depends(get_current_user)):
    with get_db() as db:
        ensure_tables(db)

        rows = db.execute(
            """
            SELECT title_id, title, year, poster_url, media_type, text,
                   contains_spoiler, created_at, updated_at
            FROM reviews
            WHERE user_id = ?
            ORDER BY updated_at DESC
            """,
            (current_user["id"],),
        ).fetchall()

        items = []
        for row in rows:
            item = dict(row)
            item["contains_spoiler"] = bool(item["contains_spoiler"])
            items.append(item)

        return {"items": items}


@router.post("/{title_id}/rating")
def save_rating(title_id: str, payload: RatingRequest, current_user=Depends(get_current_user)):
    title_id = clean_title_id(title_id)

    with get_db() as db:
        ensure_tables(db)

        user_id = current_user["id"]
        timestamp = now_utc()

        db.execute(
            """
            INSERT INTO ratings (
                user_id, title_id, title, year, poster_url, media_type,
                rating, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(user_id, title_id) DO UPDATE SET
                rating = excluded.rating,
                title = excluded.title,
                year = excluded.year,
                poster_url = excluded.poster_url,
                media_type = excluded.media_type,
                updated_at = excluded.updated_at
            """,
            (
                user_id,
                title_id,
                payload.title,
                payload.year,
                payload.poster_url,
                payload.media_type,
                payload.rating,
                timestamp,
                timestamp,
            ),
        )
        db.commit()

        return {
            "message": "rating saved",
            "my_rating": get_my_rating(db, user_id, title_id),
            "rating_summary": rating_summary(db, title_id),
        }


@router.delete("/{title_id}/rating")
def delete_rating(title_id: str, current_user=Depends(get_current_user)):
    title_id = clean_title_id(title_id)

    with get_db() as db:
        ensure_tables(db)

        db.execute(
            """
            DELETE FROM ratings
            WHERE user_id = ? AND title_id = ?
            """,
            (current_user["id"], title_id),
        )
        db.commit()

        return {
            "message": "rating deleted",
            "rating_summary": rating_summary(db, title_id),
        }


@router.post("/{title_id}/review")
def save_review(title_id: str, payload: ReviewRequest, current_user=Depends(get_current_user)):
    title_id = clean_title_id(title_id)
    text = payload.text.strip()

    if len(text) < 2:
        raise HTTPException(status_code=400, detail="review text is too short")

    if len(text) > 2000:
        raise HTTPException(status_code=400, detail="review text is too long")

    with get_db() as db:
        ensure_tables(db)

        user_id = current_user["id"]
        timestamp = now_utc()

        db.execute(
            """
            INSERT INTO reviews (
                user_id, title_id, title, year, poster_url, media_type,
                text, contains_spoiler, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(user_id, title_id) DO UPDATE SET
                text = excluded.text,
                contains_spoiler = excluded.contains_spoiler,
                title = excluded.title,
                year = excluded.year,
                poster_url = excluded.poster_url,
                media_type = excluded.media_type,
                updated_at = excluded.updated_at
            """,
            (
                user_id,
                title_id,
                payload.title,
                payload.year,
                payload.poster_url,
                payload.media_type,
                text,
                1 if payload.contains_spoiler else 0,
                timestamp,
                timestamp,
            ),
        )
        db.commit()

        return {
            "message": "review saved",
            "my_review": get_my_review(db, user_id, title_id),
            "reviews": list_reviews(db, title_id, user_id),
            "rating_summary": rating_summary(db, title_id),
        }


@router.delete("/{title_id}/review")
def delete_review(title_id: str, current_user=Depends(get_current_user)):
    title_id = clean_title_id(title_id)

    with get_db() as db:
        ensure_tables(db)

        db.execute(
            """
            DELETE FROM reviews
            WHERE user_id = ? AND title_id = ?
            """,
            (current_user["id"], title_id),
        )
        db.commit()

        return {
            "message": "review deleted",
            "reviews": list_reviews(db, title_id, current_user["id"]),
            "rating_summary": rating_summary(db, title_id),
        }


@router.get("/{title_id}/reviews")
def get_reviews(title_id: str, current_user=Depends(get_current_user)):
    title_id = clean_title_id(title_id)

    with get_db() as db:
        ensure_tables(db)

        return {
            "title_id": title_id,
            "reviews": list_reviews(db, title_id, current_user["id"]),
            "rating_summary": rating_summary(db, title_id),
        }


@router.get("/{title_id}/feedback")
def get_feedback(title_id: str, current_user=Depends(get_current_user)):
    title_id = clean_title_id(title_id)

    with get_db() as db:
        ensure_tables(db)

        user_id = current_user["id"]

        return {
            "title_id": title_id,
            "my_rating": get_my_rating(db, user_id, title_id),
            "my_review": get_my_review(db, user_id, title_id),
            "reviews": list_reviews(db, title_id, user_id),
            "rating_summary": rating_summary(db, title_id),
        }
