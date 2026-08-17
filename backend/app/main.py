from fastapi import FastAPI

from .config import APP_NAME
from .database import init_db
from .routers import auth, progress, ratings, users, watchlist, titles, admin

app = FastAPI(title=APP_NAME, version="1.0.0")

app.include_router(admin.router)
app.include_router(auth.router)
app.include_router(users.router)
app.include_router(watchlist.router)
app.include_router(ratings.router)
app.include_router(progress.router)
app.include_router(titles.router)


@app.on_event("startup")
def on_startup():
    init_db()


@app.get("/health")
def health():
    return {"status": "ok", "message": "IMDb Tracker backend is running"}
