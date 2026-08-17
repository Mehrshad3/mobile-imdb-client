import hashlib
import json
import os
import re

import requests

try:
    from .cache import JsonApiCache
except ImportError:
    from cache import JsonApiCache


OMDB_URL = "http://www.omdbapi.com/"


class OmdbClientError(Exception):
    def __init__(self, message, status_code=None, response_body=None):
        super().__init__(message)
        self.message = message
        self.status_code = status_code
        self.response_body = response_body


class OmdbClient:
    def __init__(self, api_key=None, timeout=10, cache=None):
        self.api_key = (api_key if api_key is not None else os.getenv("OMDB_API_KEY", "")).strip()
        self.timeout = timeout
        self.session = requests.Session()
        self.cache = cache if cache is not None else JsonApiCache()

    @property
    def is_configured(self):
        return bool(self.api_key)

    def fetch_title_by_id(self, imdb_id):
        imdb_id = imdb_id.strip()
        if not self.is_configured or not imdb_id:
            return None
        data = self._get({"i": imdb_id, "plot": "full", "r": "json"})
        return omdb_title_from_json(data)

    def search_titles(self, query, title_type=None, page=1):
        query = query.strip()
        if not self.is_configured or not query:
            return []

        params = {"s": query, "page": str(page), "r": "json"}
        if title_type:
            params["type"] = title_type

        data = self._get(params)
        results = []
        for item in as_list(data.get("Search")):
            title = omdb_title_from_json(item)
            if title.get("imdbId"):
                results.append(title)
        return results

    def fetch_season(self, imdb_id, season_number):
        imdb_id = imdb_id.strip()
        if not self.is_configured or not imdb_id or season_number < 1:
            return None
        data = self._get({"i": imdb_id, "Season": str(season_number), "r": "json"})
        return omdb_season_from_json(data, requested_season=season_number)

    def _get(self, params):
        query = {"apikey": self.api_key, **params}
        cache_key = request_cache_key("omdb", OMDB_URL, query)
        cached = self.cache.get(cache_key)
        if cached is not None:
            return cached

        try:
            response = self.session.get(
                OMDB_URL,
                params=query,
                headers={"Accept": "application/json"},
                timeout=self.timeout,
            )
        except requests.RequestException as error:
            raise OmdbClientError(f"Network error while connecting to OMDb: {error}") from error

        text = response.text
        if response.status_code < 200 or response.status_code >= 300:
            raise OmdbClientError(
                "OMDb API returned an HTTP error.",
                status_code=response.status_code,
                response_body=text,
            )

        try:
            data = response.json()
        except ValueError as error:
            raise OmdbClientError(
                f"Could not decode OMDb JSON response: {error}",
                response_body=text,
            ) from error

        if not isinstance(data, dict):
            raise OmdbClientError(
                "OMDb API returned a non-object JSON response.",
                response_body=text,
            )

        if clean(data.get("Response")) == "False":
            raise OmdbClientError(clean(data.get("Error")) or "OMDb API returned an error.")

        self.cache.set(cache_key, data)
        return data


def omdb_title_from_json(data):
    data = as_map(data) or {}
    imdb_id = clean(data.get("imdbID")) or ""
    title_type = clean(data.get("Type"))
    total_seasons = as_int(clean(data.get("totalSeasons")))
    runtime = clean(data.get("Runtime"))
    return {
        "imdbId": imdb_id,
        "id": imdb_id,
        "title": clean(data.get("Title")) or "Untitled",
        "year": clean(data.get("Year")),
        "type": title_type,
        "rated": clean(data.get("Rated")),
        "released": clean(data.get("Released")),
        "runtime": runtime,
        "runtimeMinutes": runtime_minutes(runtime),
        "genre": clean(data.get("Genre")),
        "genres": split_list(clean(data.get("Genre"))),
        "director": clean(data.get("Director")),
        "directors": split_list(clean(data.get("Director"))),
        "writer": clean(data.get("Writer")),
        "writers": split_list(clean(data.get("Writer"))),
        "actors": clean(data.get("Actors")),
        "actorList": split_list(clean(data.get("Actors"))),
        "plot": clean(data.get("Plot")),
        "language": clean(data.get("Language")),
        "country": clean(data.get("Country")),
        "awards": clean(data.get("Awards")),
        "poster": clean(data.get("Poster")),
        "imageUrl": clean(data.get("Poster")),
        "imdbRating": as_double(clean(data.get("imdbRating"))),
        "imdbVotes": clean(data.get("imdbVotes")),
        "totalSeasons": total_seasons,
        "isSeries": title_type == "series" or total_seasons is not None,
    }


def omdb_season_from_json(data, requested_season):
    data = as_map(data) or {}
    season_number = as_int(clean(data.get("Season"))) or requested_season
    episodes = []
    for item in as_list(data.get("Episodes")):
        episode = episode_from_omdb_json(item, season_number)
        if episode.get("id") and episode.get("title"):
            episodes.append(episode)
    return {
        "title": clean(data.get("Title")) or "",
        "seasonNumber": season_number,
        "totalSeasons": as_int(clean(data.get("totalSeasons"))),
        "episodes": episodes,
    }


def episode_from_omdb_json(data, season_number):
    data = as_map(data) or {}
    return {
        "id": clean(data.get("imdbID")) or "",
        "title": clean(data.get("Title")) or "Untitled",
        "seasonNumber": season_number,
        "episodeNumber": as_int(clean(data.get("Episode"))),
        "releaseDate": clean(data.get("Released")),
        "plot": None,
        "imageUrl": None,
        "rating": as_double(clean(data.get("imdbRating"))),
        "voteCount": None,
    }


def as_map(value):
    return value if isinstance(value, dict) else None


def as_list(value):
    return value if isinstance(value, list) else []


def as_int(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, str):
        try:
            return int(value.strip().replace(",", ""))
        except ValueError:
            return None
    return None


def as_double(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value.strip().replace(",", ""))
        except ValueError:
            return None
    return None


def clean(value):
    if value is None:
        return None
    text = str(value).strip()
    if not text or text == "N/A":
        return None
    return text


def split_list(value):
    if not value:
        return []
    return [item.strip() for item in value.split(",") if item.strip()]


def runtime_minutes(value):
    if not value:
        return None
    match = re.search(r"\d+", value)
    return int(match.group(0)) if match else None


def request_cache_key(namespace, url, params):
    sanitized_params = {
        key: value
        for key, value in sorted(params.items())
        if key.lower() != "apikey"
    }
    material = {
        "method": "GET",
        "url": url,
        "params": sanitized_params,
    }
    encoded = json.dumps(material, sort_keys=True, separators=(",", ":"), default=str)
    digest = hashlib.sha256(encoded.encode("utf-8")).hexdigest()
    return f"{namespace}:{digest}"
