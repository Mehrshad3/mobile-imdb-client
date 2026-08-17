from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from ..database import get_db
from ..security import get_current_user

router = APIRouter(tags=["watch progress"])


class WatchEpisodeRequest(BaseModel):
    title: str | None = None
    year: str | None = None
    poster_url: str | None = None
    media_type: str | None = None
    season_number: int | None = None
    episode_number: int | None = None
    episode_title: str | None = None


def now_utc():
    return datetime.utcnow().isoformat(timespec="seconds") + "Z"


def clean(value: str, name: str):
    text = value.strip()
    if not text:
        raise HTTPException(status_code=400, detail=f"{name} is required")
    return text


def ensure_table(db):
    db.execute(
        """
        CREATE TABLE IF NOT EXISTS watched_episodes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            title_id TEXT NOT NULL,
            episode_id TEXT NOT NULL,
            title TEXT,
            year TEXT,
            poster_url TEXT,
            media_type TEXT,
            season_number INTEGER,
            episode_number INTEGER,
            episode_title TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(user_id, title_id, episode_id),
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        )
        """
    )
    db.commit()


def progress_for_title(db, user_id: int, title_id: str):
    rows = db.execute(
        """
        SELECT episode_id, season_number, episode_number, episode_title, created_at, updated_at
        FROM watched_episodes
        WHERE user_id = ? AND title_id = ?
        ORDER BY updated_at DESC
        """,
        (user_id, title_id),
    ).fetchall()

    items = [dict(row) for row in rows]
    episode_ids = [item["episode_id"] for item in items]

    return {
        "title_id": title_id,
        "watched_count": len(episode_ids),
        "watched_episode_ids": episode_ids,
        "items": items,
    }


@router.get("/progress")
def get_all_progress(current_user=Depends(get_current_user)):
    with get_db() as db:
        ensure_table(db)
        rows = db.execute(
            """
            SELECT title_id, title, year, poster_url, media_type,
                   GROUP_CONCAT(episode_id) AS episode_ids,
                   COUNT(*) AS watched_count,
                   MAX(updated_at) AS updated_at
            FROM watched_episodes
            WHERE user_id = ?
            GROUP BY title_id
            ORDER BY updated_at DESC
            """,
            (current_user["id"],),
        ).fetchall()

        items = []
        for row in rows:
            item = dict(row)
            item["watched_episode_ids"] = (
                item.pop("episode_ids").split(",") if item["episode_ids"] else []
            )
            items.append(item)

        return {"items": items}


@router.get("/progress/{title_id}")
def get_title_progress(title_id: str, current_user=Depends(get_current_user)):
    title_id = clean(title_id, "title_id")
    with get_db() as db:
        ensure_table(db)
        return progress_for_title(db, current_user["id"], title_id)


@router.post("/progress/{title_id}/episodes/{episode_id}")
def mark_episode_watched(
    title_id: str,
    episode_id: str,
    payload: WatchEpisodeRequest | None = None,
    current_user=Depends(get_current_user),
):
    title_id = clean(title_id, "title_id")
    episode_id = clean(episode_id, "episode_id")
    payload = payload or WatchEpisodeRequest()
    timestamp = now_utc()

    with get_db() as db:
        ensure_table(db)
        db.execute(
            """
            INSERT INTO watched_episodes (
                user_id, title_id, episode_id, title, year, poster_url, media_type,
                season_number, episode_number, episode_title, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(user_id, title_id, episode_id) DO UPDATE SET
                title = excluded.title,
                year = excluded.year,
                poster_url = excluded.poster_url,
                media_type = excluded.media_type,
                season_number = excluded.season_number,
                episode_number = excluded.episode_number,
                episode_title = excluded.episode_title,
                updated_at = excluded.updated_at
            """,
            (
                current_user["id"],
                title_id,
                episode_id,
                payload.title,
                payload.year,
                payload.poster_url,
                payload.media_type,
                payload.season_number,
                payload.episode_number,
                payload.episode_title,
                timestamp,
                timestamp,
            ),
        )
        db.commit()
        return progress_for_title(db, current_user["id"], title_id)


@router.delete("/progress/{title_id}/episodes/{episode_id}")
def unmark_episode_watched(
    title_id: str,
    episode_id: str,
    current_user=Depends(get_current_user),
):
    title_id = clean(title_id, "title_id")
    episode_id = clean(episode_id, "episode_id")

    with get_db() as db:
        ensure_table(db)
        db.execute(
            """
            DELETE FROM watched_episodes
            WHERE user_id = ? AND title_id = ? AND episode_id = ?
            """,
            (current_user["id"], title_id, episode_id),
        )
        db.commit()
        return progress_for_title(db, current_user["id"], title_id)
