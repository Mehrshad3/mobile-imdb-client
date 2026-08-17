import re
from datetime import datetime

from fastapi import APIRouter, HTTPException, Path, Query

from ..services.imdb_client import ImdbClient, ImdbClientError
from ..services.omdb_client import OmdbClient, OmdbClientError


router = APIRouter(prefix="/titles", tags=["titles"])

imdb_client = ImdbClient()
omdb_client = OmdbClient()


@router.get("/search")
def search_titles(
    q: str = Query("", description="Movie/series name or IMDb title id."),
    type: str = Query("all", description="all, movie, series"),
    first: int = Query(20, ge=1, le=50),
):
    query = q.strip()
    if not query:
        return {"items": []}

    imdb_id = extract_imdb_title_id(query)
    if imdb_id:
        return {"items": title_summary_by_id(imdb_id, fallback_title=title_text_without_imdb_id(query))}

    normalized_type = type.strip().lower()
    try:
        if normalized_type == "movie":
            items = imdb_client.advanced_title_search(
                search_term=query,
                first=first,
                title_type_ids=["movie"],
            )
        elif normalized_type in ("series", "tv", "tvseries"):
            items = imdb_client.advanced_title_search(
                search_term=query,
                first=first,
                title_type_ids=["tvSeries", "tvMiniSeries"],
            )
        else:
            items = imdb_client.search_suggestions(query)
    except ImdbClientError as error:
        raise external_error(error)

    return {"items": items}


@router.get("/search-by-id/{title_id}")
def search_by_id(title_id: str):
    imdb_id = extract_imdb_title_id(title_id)
    if not imdb_id:
        raise HTTPException(status_code=400, detail="Valid IMDb title id is required.")
    return {"items": title_summary_by_id(imdb_id)}


@router.get("/advanced-search")
def advanced_search(
    q: str = "",
    type: str = "all",
    first: int = Query(20, ge=1, le=50),
    sort_by: str = "POPULARITY",
    sort_order: str = "ASC",
    release_date_start: str | None = None,
    release_date_end: str | None = None,
    minimum_rating: float | None = Query(None, ge=0, le=10),
    minimum_votes: int | None = Query(None, ge=0),
    top_rated_movies_only: bool = False,
):
    query = q.strip()
    imdb_id = extract_imdb_title_id(query)
    if imdb_id:
        return {"items": title_summary_by_id(imdb_id, fallback_title=title_text_without_imdb_id(query))}

    try:
        items = imdb_client.advanced_title_search(
            search_term=query,
            first=first,
            title_type_ids=title_type_ids_for_filter(type),
            sort_by=sort_by,
            sort_order=sort_order,
            release_date_start=release_date_start,
            release_date_end=release_date_end,
            minimum_rating=minimum_rating,
            minimum_votes=minimum_votes,
            top_rated_movies_only=top_rated_movies_only,
        )
    except ImdbClientError as error:
        raise external_error(error)

    return {"items": items}


@router.get("/trending")
def trending(first: int = Query(12, ge=1, le=50)):
    try:
        items = imdb_client.fetch_trending(first=first)
        return {"items": fill_missing_trending_images(items)}
    except ImdbClientError as error:
        raise external_error(error)


@router.get("/popular/movies")
def popular_movies(first: int = Query(12, ge=1, le=50)):
    return advanced_collection(
        first=first,
        title_type_ids=["movie"],
    )


@router.get("/popular/series")
def popular_series(first: int = Query(12, ge=1, le=50)):
    return advanced_collection(
        first=first,
        title_type_ids=["tvSeries", "tvMiniSeries"],
    )


@router.get("/new")
def new_titles(first: int = Query(12, ge=1, le=50)):
    now = datetime.utcnow()
    start = f"{now.year}-01-01"
    end = f"{now.year}-12-31"
    return advanced_collection(
        first=first,
        title_type_ids=["movie", "tvSeries", "tvMiniSeries"],
        release_date_start=start,
        release_date_end=end,
    )


@router.get("/top-rated")
def top_rated_movies(first: int = Query(12, ge=1, le=50)):
    return advanced_collection(
        first=first,
        title_type_ids=["movie"],
        minimum_rating=8,
        minimum_votes=50000,
        top_rated_movies_only=True,
    )


@router.get("/metadata")
def metadata(ids: str = Query("", description="Comma separated IMDb title ids.")):
    title_ids = [item.strip() for item in ids.split(",") if item.strip()]
    if not title_ids:
        return {"items": []}
    try:
        return {"items": imdb_client.fetch_title_metadata(title_ids)}
    except ImdbClientError as error:
        raise external_error(error)


@router.get("/{title_id}/overview")
def series_overview(title_id: str):
    imdb_id = require_imdb_title_id(title_id)
    try:
        return imdb_client.fetch_series_overview(imdb_id)
    except ImdbClientError as error:
        raise external_error(error)


@router.get("/{title_id}/seasons/{season_number}/episodes")
def season_episodes(title_id: str, season_number: int = Path(..., ge=1)):
    imdb_id = require_imdb_title_id(title_id)
    try:
        episodes = imdb_client.fetch_season_episodes(imdb_id, season_number)
        if episodes:
            return {"items": episodes, "source": "imdb"}
    except ImdbClientError as imdb_error:
        try:
            omdb_season = omdb_client.fetch_season(imdb_id, season_number)
        except OmdbClientError:
            raise external_error(imdb_error)
        if omdb_season and omdb_season.get("episodes"):
            return {"items": omdb_season["episodes"], "source": "omdb"}
        raise external_error(imdb_error)

    try:
        omdb_season = omdb_client.fetch_season(imdb_id, season_number)
    except OmdbClientError:
        omdb_season = None

    if omdb_season and omdb_season.get("episodes"):
        return {"items": omdb_season["episodes"], "source": "omdb"}
    return {"items": [], "source": "none"}


@router.get("/{title_id}")
def title_details(title_id: str):
    imdb_id = require_imdb_title_id(title_id)

    errors = []
    imdb_details = None
    omdb_details = None
    overview = None

    try:
        metadata = imdb_client.fetch_title_metadata([imdb_id])
        if metadata:
            imdb_details = metadata[0]
    except ImdbClientError as error:
        errors.append(error.message)

    try:
        omdb_details = omdb_client.fetch_title_by_id(imdb_id)
    except OmdbClientError as error:
        errors.append(error.message)

    summary = summary_from_details(imdb_details) or summary_from_omdb(omdb_details)
    if summary is None:
        summary = fallback_summary(imdb_id)

    if can_have_episodes(summary, imdb_details, omdb_details):
        try:
            overview = imdb_client.fetch_series_overview(imdb_id)
        except ImdbClientError as error:
            errors.append(error.message)

    return {
        "summary": summary,
        "imdbDetails": imdb_details,
        "omdbDetails": omdb_details,
        "seriesOverview": overview,
        "errors": errors,
    }


def advanced_collection(
    first,
    title_type_ids,
    release_date_start=None,
    release_date_end=None,
    minimum_rating=None,
    minimum_votes=None,
    top_rated_movies_only=False,
):
    try:
        items = imdb_client.advanced_title_search(
            first=first,
            title_type_ids=title_type_ids,
            release_date_start=release_date_start,
            release_date_end=release_date_end,
            minimum_rating=minimum_rating,
            minimum_votes=minimum_votes,
            top_rated_movies_only=top_rated_movies_only,
        )
        return {"items": items}
    except ImdbClientError as error:
        raise external_error(error)


def title_summary_by_id(imdb_id, fallback_title=None):
    try:
        details = imdb_client.fetch_title_metadata([imdb_id])
        if details:
            return [summary_from_details(details[0])]
    except ImdbClientError:
        pass

    try:
        omdb_details = omdb_client.fetch_title_by_id(imdb_id)
        summary = summary_from_omdb(omdb_details)
        if summary:
            return [summary]
    except OmdbClientError:
        pass

    return [fallback_summary(imdb_id, fallback_title=fallback_title)]


def fill_missing_trending_images(items):
    missing = [item["id"] for item in items if not item.get("imageUrl")]
    if not missing:
        return items

    try:
        details = imdb_client.fetch_title_metadata(missing)
    except ImdbClientError:
        return items

    by_id = {detail["id"]: summary_from_details(detail) for detail in details}
    result = []
    for item in items:
        detail = by_id.get(item["id"])
        if detail and not item.get("imageUrl"):
            merged = {**item}
            merged["imageUrl"] = detail.get("imageUrl")
            merged["rating"] = item.get("rating") or detail.get("rating")
            merged["voteCount"] = item.get("voteCount") or detail.get("voteCount")
            merged["canHaveEpisodes"] = item.get("canHaveEpisodes") or detail.get("canHaveEpisodes")
            result.append(merged)
        else:
            result.append(item)
    return result


def summary_from_details(details):
    if not details:
        return None
    return {
        "id": details.get("id") or "",
        "title": details.get("title") or "",
        "type": details.get("type"),
        "year": details.get("releaseYear"),
        "endYear": details.get("endYear"),
        "imageUrl": details.get("imageUrl"),
        "rank": None,
        "subtitle": details.get("plot"),
        "rating": details.get("rating"),
        "voteCount": details.get("voteCount"),
        "canHaveEpisodes": details.get("canHaveEpisodes") or False,
    }


def summary_from_omdb(details):
    if not details or not details.get("imdbId"):
        return None
    return {
        "id": details.get("imdbId"),
        "title": details.get("title") or details.get("imdbId"),
        "type": details.get("type"),
        "year": first_year(details.get("year")),
        "endYear": None,
        "imageUrl": details.get("poster"),
        "rank": None,
        "subtitle": details.get("plot"),
        "rating": details.get("imdbRating"),
        "voteCount": votes_to_int(details.get("imdbVotes")),
        "canHaveEpisodes": details.get("isSeries") or False,
    }


def fallback_summary(imdb_id, fallback_title=None):
    return {
        "id": imdb_id,
        "title": fallback_title or imdb_id,
        "type": "IMDb ID",
        "year": None,
        "endYear": None,
        "imageUrl": None,
        "rank": None,
        "subtitle": "IMDb id was detected. Open it to load details.",
        "rating": None,
        "voteCount": None,
        "canHaveEpisodes": False,
    }


def can_have_episodes(summary, imdb_details, omdb_details):
    return bool(
        (summary or {}).get("canHaveEpisodes")
        or (imdb_details or {}).get("canHaveEpisodes")
        or (omdb_details or {}).get("isSeries")
    )


def title_type_ids_for_filter(value):
    normalized = value.strip().lower()
    if normalized == "movie":
        return ["movie"]
    if normalized in ("series", "tv", "tvseries"):
        return ["tvSeries", "tvMiniSeries"]
    return ["movie", "tvSeries", "tvMiniSeries"]


def require_imdb_title_id(value):
    imdb_id = extract_imdb_title_id(value)
    if not imdb_id:
        raise HTTPException(status_code=400, detail="Valid IMDb title id is required.")
    return imdb_id


def extract_imdb_title_id(value):
    match = re.search(r"tt\d+", value.strip(), flags=re.IGNORECASE)
    return match.group(0).lower() if match else None


def title_text_without_imdb_id(value):
    cleaned = re.sub(r"tt\d+", " ", value, flags=re.IGNORECASE)
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    return cleaned or None


def first_year(value):
    if not value:
        return None
    match = re.search(r"\d{4}", str(value))
    return int(match.group(0)) if match else None


def votes_to_int(value):
    if not value:
        return None
    try:
        return int(str(value).replace(",", "").strip())
    except ValueError:
        return None


def external_error(error):
    status_code = 502
    return HTTPException(
        status_code=status_code,
        detail={
            "message": error.message,
            "upstream_status": getattr(error, "status_code", None),
        },
    )
