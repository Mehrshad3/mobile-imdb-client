import hashlib
import json
import re
from datetime import datetime, timedelta

import requests

try:
    from .cache import JsonApiCache
except ImportError:
    from cache import JsonApiCache


GRAPHQL_URL = "https://caching.graphql.imdb.com/"
SUGGESTION_URL = "https://v3.sg.media-imdb.com/suggestion/{bucket}/{query}.json"

TRENDING_HASH = "419b4fc66817a78c3046e0cedef747033d5ac2711080338a59a366630f9742c1"
ADVANCED_SEARCH_HASH = "78932519bc74ceb6be628fe452c0e59a48bcf8ca91fc550dd5de43ab200acd52"
FAVORITE_TITLES_METADATA_HASH = "d326f6473ec76e947098d2585c35f0891c4b47c2ef261c14b7c82902ae196d1b"
SERIES_OVERVIEW_HASH = "3f56a4c9c2cca81733ebabbf5e317e3da7f2a4a02069d406bec001ed611c80e4"
SEASON_EPISODES_HASH = "5cd1a7aa5ba917bd6e519570375e6f3f570ad3503e6a9d202b1fa4cb5ae6a56d"

DEFAULT_HEADERS = {
    "Accept": "application/graphql+json, application/json",
    "Accept-Language": "en-US,en;q=0.9",
    "Content-Type": "application/json",
    "Referer": "https://www.imdb.com/",
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36"
    ),
    "x-imdb-client-name": "imdb-web-next-localized",
    "x-imdb-user-language": "en-US",
    "x-imdb-user-country": "US",
}


class ImdbClientError(Exception):
    def __init__(self, message, status_code=None, response_body=None):
        super().__init__(message)
        self.message = message
        self.status_code = status_code
        self.response_body = response_body


class ImdbClient:
    def __init__(self, timeout=12, cache=None):
        self.timeout = timeout
        self.session = requests.Session()
        self.cache = cache if cache is not None else JsonApiCache()

    def search_suggestions(self, query):
        trimmed = query.strip()
        if not trimmed:
            return []

        bucket = suggestion_bucket(trimmed)
        url = SUGGESTION_URL.format(bucket=bucket, query=trimmed)
        data = self._send_json("GET", url, params={"includeVideos": "1"})

        results = []
        for item in as_list(data.get("d")):
            summary = title_summary_from_suggestion(item)
            if is_valid_title(summary):
                results.append(summary)
        return results

    def fetch_trending(self, first=8):
        data = self._get_graphql_persisted(
            operation_name="Trending",
            variables={
                "first": first,
                "input": {"dataWindow": "HOURS", "trafficSource": "XWW"},
            },
            hash_value=TRENDING_HASH,
        )
        edges = as_list(read_path(data, ["data", "topTrendingTitles", "edges"]))
        results = []
        for edge in edges:
            summary = title_summary_from_trending_edge(edge)
            if is_valid_title(summary):
                results.append(summary)
        return results

    def advanced_title_search(
        self,
        search_term="",
        first=20,
        title_type_ids=None,
        sort_by="POPULARITY",
        sort_order="ASC",
        release_date_start=None,
        release_date_end=None,
        minimum_rating=None,
        minimum_votes=None,
        top_rated_movies_only=False,
    ):
        title_type_ids = title_type_ids or ["movie", "tvSeries"]
        variables = {
            "locale": "en-US",
            "first": first,
            "sortBy": sort_by,
            "sortOrder": sort_order,
        }

        trimmed = search_term.strip()
        if trimmed:
            variables["titleTextConstraint"] = {"searchTerm": trimmed}

        if title_type_ids:
            variables["titleTypeConstraint"] = {"anyTitleTypeIds": title_type_ids}

        if release_date_start or release_date_end:
            date_range = {}
            if release_date_start:
                date_range["start"] = release_date_start
            if release_date_end:
                date_range["end"] = release_date_end
            variables["releaseDateConstraint"] = {"releaseDateRange": date_range}

        if minimum_rating is not None or minimum_votes is not None:
            ratings = {}
            if minimum_rating is not None:
                ratings["aggregateRatingRange"] = {
                    "min": minimum_rating,
                    "max": 10,
                }
            if minimum_votes is not None:
                ratings["ratingsCountRange"] = {"min": minimum_votes}
            variables["userRatingsConstraint"] = ratings

        if top_rated_movies_only:
            variables["rankedTitleListConstraint"] = {
                "allRankedTitleLists": [
                    {
                        "rankedTitleListType": "TOP_RATED_MOVIES",
                        "rankRange": {"max": 250},
                    }
                ],
                "excludeRankedTitleLists": [],
            }

        data = self._post_graphql_persisted(
            operation_name="AdvancedTitleSearch",
            variables=variables,
            hash_value=ADVANCED_SEARCH_HASH,
        )
        edges = as_list(read_path(data, ["data", "advancedTitleSearch", "edges"]))

        results = []
        for edge in edges:
            summary = title_summary_from_advanced_edge(edge)
            if is_valid_title(summary):
                results.append(summary)
        return results

    def fetch_title_metadata(self, title_ids):
        ids = sorted({title_id.strip() for title_id in title_ids if title_id.strip()})
        if not ids:
            return []

        data = self._get_graphql_persisted(
            operation_name="FavoriteTitlesMetadata",
            variables={"locale": "en-US", "tconsts": ids},
            hash_value=FAVORITE_TITLES_METADATA_HASH,
        )

        results = []
        for item in as_list(read_path(data, ["data", "titles"])):
            details = title_details_from_metadata(item)
            if details.get("id") and details.get("title"):
                results.append(details)
        return results

    def fetch_series_overview(self, title_id):
        title_id = title_id.strip()
        if not title_id:
            raise ImdbClientError("Title id is required.")

        data = self._get_graphql_persisted(
            operation_name="HERO_SUB_NAV_EPISODE",
            variables=series_overview_variables(title_id),
            hash_value=SERIES_OVERVIEW_HASH,
        )
        return series_overview_from_hero_sub_nav(title_id, data)

    def fetch_season_episodes(self, title_id, season_number):
        title_id = title_id.strip()
        if not title_id:
            raise ImdbClientError("Title id is required.")
        if season_number < 1:
            raise ImdbClientError("Season number must be positive.")

        data = self._get_graphql_persisted(
            operation_name="EpisodeRatings_SeasonDetail",
            variables={
                "id": title_id,
                "locale": "en-US",
                "seasons": [str(season_number)],
            },
            hash_value=SEASON_EPISODES_HASH,
        )

        edges = as_list(read_path(data, ["data", "title", "episodes", "episodes", "edges"]))
        episodes = []
        for edge in edges:
            node = as_map(read_path(edge, ["node"]))
            if node is None:
                continue
            episode = episode_from_node(node)
            if episode.get("id") and episode.get("title"):
                episodes.append(episode)
        return episodes

    def _get_graphql_persisted(self, operation_name, variables, hash_value):
        return self._send_json(
            "GET",
            GRAPHQL_URL,
            params={
                "operationName": operation_name,
                "variables": json.dumps(variables, separators=(",", ":")),
                "extensions": json.dumps(persisted_query(hash_value), separators=(",", ":")),
            },
        )

    def _post_graphql_persisted(self, operation_name, variables, hash_value):
        return self._send_json(
            "POST",
            GRAPHQL_URL,
            payload={
                "operationName": operation_name,
                "variables": variables,
                "extensions": persisted_query(hash_value),
            },
        )

    def _send_json(self, method, url, params=None, payload=None):
        cache_key = request_cache_key("imdb", method, url, params=params, payload=payload)
        cached = self.cache.get(cache_key)
        if cached is not None:
            return cached

        try:
            response = self.session.request(
                method,
                url,
                params=params,
                json=payload,
                headers=DEFAULT_HEADERS,
                timeout=self.timeout,
            )
        except requests.RequestException as error:
            raise ImdbClientError(f"Network error while connecting to IMDb: {error}") from error

        text = response.text
        if response.status_code < 200 or response.status_code >= 300:
            raise ImdbClientError(
                "IMDb API returned an HTTP error.",
                status_code=response.status_code,
                response_body=shorten(text),
            )

        try:
            data = response.json()
        except ValueError as error:
            raise ImdbClientError(
                f"Could not decode IMDb JSON response: {error}",
                response_body=shorten(text),
            ) from error

        if not isinstance(data, dict):
            raise ImdbClientError(
                "IMDb API returned a non-object JSON response.",
                response_body=shorten(text),
            )

        errors = as_list(data.get("errors"))
        if errors:
            raise ImdbClientError(
                graphql_error_message(errors),
                response_body=shorten(text),
            )

        self.cache.set(cache_key, data)
        return data


def title_summary_from_suggestion(data):
    data = as_map(data) or {}
    title_type = as_string(data.get("q")) or as_string(data.get("qid"))
    year_range = as_string(data.get("yr"))
    can_have_episodes = (
        as_string(data.get("qid")) == "tvSeries"
        or ("tv" in (title_type or "").lower())
    )

    return {
        "id": as_string(data.get("id")) or "",
        "title": read_title_text(data) or "Untitled",
        "type": title_type,
        "year": as_int(data.get("y")) or first_year(year_range),
        "endYear": end_year(year_range),
        "imageUrl": read_image_url(data),
        "rank": as_int(data.get("rank")),
        "subtitle": as_string(data.get("s")),
        "rating": None,
        "voteCount": None,
        "canHaveEpisodes": can_have_episodes,
    }


def title_summary_from_title_node(data, rank=None):
    data = as_map(data) or {}
    title_type = as_map(data.get("titleType")) or {}
    release_year = as_map(data.get("releaseYear")) or {}
    ratings = as_map(data.get("ratingsSummary")) or {}
    year_range = as_string(data.get("yr"))
    type_text = (
        read_text(title_type.get("displayableProperty"))
        or as_string(title_type.get("text"))
        or as_string(title_type.get("id"))
        or as_string(data.get("q"))
        or as_string(data.get("qid"))
    )

    return {
        "id": as_string(data.get("id")) or "",
        "title": read_title_text(data) or "Untitled",
        "type": type_text,
        "year": as_int(release_year.get("year")) or as_int(data.get("y")) or first_year(year_range),
        "endYear": as_int(release_year.get("endYear")) or end_year(year_range),
        "imageUrl": read_image_url(data),
        "rank": rank if rank is not None else as_int(data.get("rank")),
        "subtitle": as_string(data.get("s")) or read_text(data.get("plot")),
        "rating": as_double(ratings.get("aggregateRating")),
        "voteCount": as_int(ratings.get("voteCount")),
        "canHaveEpisodes": as_bool(title_type.get("canHaveEpisodes")) or False,
    }


def title_summary_from_trending_edge(edge):
    edge = as_map(edge) or {}
    node = as_map(edge.get("node")) or edge
    item_node = as_map(node.get("item"))
    title_node = (
        as_map(read_path(item_node, ["title"]))
        or item_node
        or as_map(node.get("title"))
        or node
    )
    rank = (
        as_int(node.get("currentRank"))
        or as_int(node.get("rank"))
        or as_int(node.get("position"))
        or as_int(edge.get("currentRank"))
        or as_int(edge.get("rank"))
    )
    summary = title_summary_from_title_node(title_node, rank=rank)
    if not summary.get("imageUrl"):
        summary["imageUrl"] = read_image_url(edge)
    return summary


def title_summary_from_advanced_edge(edge):
    edge = as_map(edge) or {}
    node = as_map(edge.get("node")) or edge
    title_node = as_map(node.get("title")) or as_map(node.get("item")) or node
    rank = (
        as_int(node.get("position"))
        or as_int(node.get("rank"))
        or as_int(edge.get("position"))
        or as_int(edge.get("rank"))
    )
    return title_summary_from_title_node(title_node, rank=rank)


def title_details_from_metadata(data):
    data = as_map(data) or {}
    title_type = as_map(data.get("titleType")) or {}
    release_year = as_map(data.get("releaseYear")) or {}
    ratings = as_map(data.get("ratingsSummary")) or {}
    runtime = as_map(data.get("runtime")) or {}
    certificate = as_map(data.get("certificate")) or {}
    latest_trailer = as_map(data.get("latestTrailer")) or {}

    runtime_seconds = as_int(runtime.get("seconds"))
    return {
        "id": as_string(data.get("id")) or "",
        "title": read_title_text(data) or "Untitled",
        "originalTitle": as_string(read_path(data, ["originalTitleText", "text"])),
        "type": (
            read_text(title_type.get("displayableProperty"))
            or as_string(title_type.get("text"))
            or as_string(title_type.get("id"))
        ),
        "canHaveEpisodes": as_bool(title_type.get("canHaveEpisodes")) or False,
        "imageUrl": read_image_url(data),
        "releaseYear": as_int(release_year.get("year")),
        "endYear": as_int(release_year.get("endYear")),
        "rating": as_double(ratings.get("aggregateRating")),
        "voteCount": as_int(ratings.get("voteCount")),
        "runtimeSeconds": runtime_seconds,
        "runtimeMinutes": round(runtime_seconds / 60) if runtime_seconds else None,
        "certificate": as_string(certificate.get("rating")),
        "genres": read_genres(data),
        "plot": read_text(data.get("plot")),
        "releaseDate": read_release_date(data.get("releaseDate")),
        "productionStatus": read_text(read_path(data, ["productionStatus", "currentProductionStage"])),
        "latestTrailerId": as_string(latest_trailer.get("id")),
    }


def episode_from_node(data):
    data = as_map(data) or {}
    ratings = as_map(data.get("ratingsSummary")) or {}
    displayable_episode_number = read_path(data, ["series", "displayableEpisodeNumber"])
    return {
        "id": as_string(data.get("id")) or "",
        "title": read_title_text(data) or "Untitled",
        "seasonNumber": as_int(
            read_path(displayable_episode_number, ["displayableSeason", "season"])
        ),
        "episodeNumber": as_int(
            read_path(displayable_episode_number, ["episodeNumber", "episodeNumber"])
        ),
        "releaseDate": read_release_date(data.get("releaseDate")),
        "plot": read_text(data.get("plot")),
        "imageUrl": read_image_url(data),
        "rating": as_double(ratings.get("aggregateRating")),
        "voteCount": as_int(ratings.get("voteCount")),
    }


def series_overview_from_hero_sub_nav(title_id, data):
    episodes = as_map(read_path(data, ["data", "title", "episodes"])) or {}
    latest_node = first_edge_node(episodes.get("TMD_Hero_MostRecentEpisode"))
    next_node = first_edge_node(episodes.get("TMD_Hero_NextEpisode"))
    return {
        "titleId": title_id,
        "isOngoing": as_bool(episodes.get("isOngoing")) or False,
        "totalEpisodes": as_int(read_path(episodes, ["TMD_Hero_EpisodeCount", "total"])),
        "latestSeasonNumber": as_int(read_path(latest_node, ["series", "episodeNumber", "seasonNumber"])),
        "latestEpisodeNumber": as_int(read_path(latest_node, ["series", "episodeNumber", "episodeNumber"])),
        "latestReleaseDate": read_release_date(read_path(latest_node, ["releaseDate"])),
        "nextSeasonNumber": as_int(read_path(next_node, ["series", "episodeNumber", "seasonNumber"])),
        "nextEpisodeNumber": as_int(read_path(next_node, ["series", "episodeNumber", "episodeNumber"])),
        "nextReleaseDate": read_release_date(read_path(next_node, ["releaseDate"])),
    }


def as_map(value):
    return value if isinstance(value, dict) else None


def as_list(value):
    return value if isinstance(value, list) else []


def as_string(value):
    if isinstance(value, str):
        text = value.strip()
        return text or None
    if isinstance(value, (int, float, bool)):
        return str(value)
    return None


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


def as_bool(value):
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered == "true":
            return True
        if lowered == "false":
            return False
    return None


def read_path(source, path):
    current = source
    for segment in path:
        current_map = as_map(current)
        if current_map is None:
            return None
        current = current_map.get(segment)
    return current


def read_text(source):
    direct = as_string(source)
    if direct:
        return direct
    for path in [
        ["text"],
        ["plainText"],
        ["value", "plainText"],
        ["displayableProperty", "value", "plainText"],
        ["plotText", "plainText"],
        ["genre", "text"],
    ]:
        text = as_string(read_path(source, path))
        if text:
            return text
    return None


def read_title_text(source):
    for path in [
        ["titleText", "text"],
        ["originalTitleText", "text"],
        ["l"],
        ["title"],
        ["name"],
        ["text"],
    ]:
        text = as_string(read_path(source, path))
        if text:
            return text
    return read_text(source)


def read_image_url(source):
    paths = [
        ["primaryImage", "url"],
        ["primaryImage", "imageUrl"],
        ["primaryImage", "urlWithSize"],
        ["primaryImage", "captionedImage", "url"],
        ["item", "primaryImage", "url"],
        ["item", "primaryImage", "imageUrl"],
        ["item", "primaryImage", "urlWithSize"],
        ["item", "title", "primaryImage", "url"],
        ["item", "title", "primaryImage", "imageUrl"],
        ["item", "title", "primaryImage", "urlWithSize"],
        ["title", "primaryImage", "url"],
        ["title", "primaryImage", "imageUrl"],
        ["title", "primaryImage", "urlWithSize"],
        ["node", "item", "primaryImage", "url"],
        ["node", "item", "primaryImage", "imageUrl"],
        ["node", "item", "primaryImage", "urlWithSize"],
        ["node", "item", "title", "primaryImage", "url"],
        ["node", "item", "title", "primaryImage", "imageUrl"],
        ["node", "item", "title", "primaryImage", "urlWithSize"],
        ["node", "title", "primaryImage", "url"],
        ["node", "title", "primaryImage", "imageUrl"],
        ["node", "title", "primaryImage", "urlWithSize"],
        ["node", "primaryImage", "url"],
        ["node", "primaryImage", "imageUrl"],
        ["node", "primaryImage", "urlWithSize"],
        ["i", "url"],
        ["i", "imageUrl"],
        ["i", "urlWithSize"],
        ["image", "url"],
        ["image", "imageUrl"],
        ["image", "urlWithSize"],
        ["imageUrl"],
        ["url"],
    ]
    for path in paths:
        url = as_string(read_path(source, path))
        normalized = normalize_image_url(url)
        if normalized:
            return normalized
    for path in [["primaryImage"], ["image"], ["i"]]:
        url = as_string(read_path(source, path))
        normalized = normalize_image_url(url)
        if normalized:
            return normalized
    return None


def normalize_image_url(value):
    if not value:
        return None
    trimmed = value.strip()
    if not trimmed:
        return None
    if trimmed.startswith("//"):
        return f"https:{trimmed}"
    if trimmed.startswith("http://"):
        return "https://" + trimmed[len("http://") :]
    if trimmed.startswith("https://"):
        return trimmed
    return None


def read_release_date(source):
    display = read_text(read_path(source, ["displayableProperty"]))
    if display:
        return display
    data = as_map(source)
    if data is None:
        return None
    return format_date_parts(
        day=data.get("day"),
        month=data.get("month"),
        year=data.get("year"),
    )


def format_date_parts(day=None, month=None, year=None):
    parsed_year = as_int(year)
    if parsed_year is None:
        return None
    parsed_month = as_int(month)
    parsed_day = as_int(day)
    if parsed_month is None or parsed_day is None:
        return str(parsed_year)
    return f"{parsed_year}-{parsed_month:02d}-{parsed_day:02d}"


def read_genres(data):
    genres = []
    for raw_genre in as_list(read_path(data, ["titleGenres", "genres"])):
        text = read_text(raw_genre)
        if text:
            genres.append(text)
    return genres


def first_edge_node(connection):
    edges = as_list(read_path(connection, ["edges"]))
    if not edges:
        return None
    return as_map(read_path(edges[0], ["node"]))


def suggestion_bucket(query):
    first = query[0].lower()
    if re.match(r"^[a-z0-9]$", first):
        return first
    return "a"


def first_year(value):
    if not value:
        return None
    match = re.search(r"\d{4}", value)
    return int(match.group(0)) if match else None


def end_year(value):
    if not value:
        return None
    matches = re.findall(r"\d{4}", value)
    if len(matches) < 2:
        return None
    return int(matches[1])


def is_valid_title(summary):
    return bool(summary.get("id") and summary.get("title"))


def persisted_query(hash_value):
    return {"persistedQuery": {"version": 1, "sha256Hash": hash_value}}


def series_overview_variables(title_id):
    now = datetime.utcnow()
    yesterday = now - timedelta(days=1)
    return {
        "heroNowDateDay": now.day,
        "heroNowDateMonth": now.month,
        "heroNowDateYear": now.year,
        "heroYesterdayDateDay": yesterday.day,
        "heroYesterdayDateMonth": yesterday.month,
        "heroYesterdayDateYear": yesterday.year,
        "locale": "en-US",
        "titleId": title_id,
    }


def graphql_error_message(errors):
    messages = []
    for error in errors:
        message = as_string(read_path(error, ["message"]))
        if message:
            messages.append(message)
    if not messages:
        return "IMDb GraphQL returned an error."
    return "IMDb GraphQL error: " + " | ".join(messages)


def shorten(value, max_length=700):
    if value is None or len(value) <= max_length:
        return value
    return value[:max_length] + "..."


def request_cache_key(namespace, method, url, params=None, payload=None):
    material = {
        "method": method.upper(),
        "url": url,
        "params": stable_value(params),
        "payload": stable_value(payload),
    }
    encoded = json.dumps(material, sort_keys=True, separators=(",", ":"), default=str)
    digest = hashlib.sha256(encoded.encode("utf-8")).hexdigest()
    return f"{namespace}:{digest}"


def stable_value(value):
    if isinstance(value, dict):
        return {str(key): stable_value(value[key]) for key in sorted(value)}
    if isinstance(value, list):
        return [stable_value(item) for item in value]
    if isinstance(value, tuple):
        return [stable_value(item) for item in value]
    return value
