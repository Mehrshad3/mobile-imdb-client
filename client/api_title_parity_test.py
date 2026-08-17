import argparse
import json
import os
import sys
from pathlib import Path
from urllib import error, parse, request


DEFAULT_BASE_URL = "http://52.16.58.211:8000"
DEFAULT_TITLE_ID = "tt2560140"
DEFAULT_SERIES_ID = "tt2560140"
DEFAULT_SEARCH_QUERY = "Attack on Titan"
DEFAULT_MOVIE_QUERY = "Inception"
DEFAULT_SEASON = 1
DEFAULT_FIRST = 5


def load_upstream_clients(services_dir):
    root = Path(__file__).resolve().parent
    candidates = []
    if services_dir:
        candidates.append(Path(services_dir).resolve())
    candidates.extend(
        [
            root / "new_server_api" / "services",
            root / "app" / "services",
            Path.cwd() / "app" / "services",
        ]
    )

    for candidate in candidates:
        if (candidate / "imdb_client.py").exists() and (candidate / "omdb_client.py").exists():
            sys.path.insert(0, str(candidate))
            from imdb_client import ImdbClient, ImdbClientError
            from omdb_client import OmdbClient, OmdbClientError

            return ImdbClient, ImdbClientError, OmdbClient, OmdbClientError, candidate

    searched = "\n".join(f"- {candidate}" for candidate in candidates)
    raise RuntimeError(
        "Could not find imdb_client.py and omdb_client.py. Searched:\n" + searched
    )


class ServerApiError(Exception):
    def __init__(self, method, url, status, payload):
        super().__init__(f"{method} {url} failed with status {status}")
        self.method = method
        self.url = url
        self.status = status
        self.payload = payload


class ServerApiClient:
    def __init__(self, base_url, timeout=35):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    def get(self, path, params=None):
        query = ""
        if params:
            query = "?" + parse.urlencode(
                {key: value for key, value in params.items() if value is not None}
            )
        url = f"{self.base_url}{path}{query}"
        req = request.Request(url, headers={"Accept": "application/json"}, method="GET")

        try:
            with request.urlopen(req, timeout=self.timeout) as response:
                raw = response.read().decode("utf-8", errors="replace")
                return response.status, parse_json(raw)
        except error.HTTPError as exc:
            raw = exc.read().decode("utf-8", errors="replace")
            return exc.code, parse_json(raw)
        except error.URLError as exc:
            return 0, {"error": str(exc.reason)}
        except TimeoutError:
            return 0, {"error": "request timed out"}

    def expect_get(self, path, params=None, expected_status=200):
        status, payload = self.get(path, params=params)
        if status != expected_status:
            query = ""
            if params:
                query = "?" + parse.urlencode(
                    {key: value for key, value in params.items() if value is not None}
                )
            raise ServerApiError("GET", f"{self.base_url}{path}{query}", status, payload)
        return payload


class TestRunner:
    def __init__(self):
        self.results = []

    def check(self, name, func):
        try:
            detail = func()
            self.results.append((name, True, detail or "ok"))
            print(f"\n[PASS] {name}")
            if detail:
                print(detail)
        except Exception as exc:
            self.results.append((name, False, str(exc)))
            print(f"\n[FAIL] {name}")
            print(str(exc))
            if isinstance(exc, ServerApiError):
                print(pretty(exc.payload))

    def summary(self):
        passed = sum(1 for _, ok, _ in self.results if ok)
        total = len(self.results)
        failed = total - passed
        print("\n==============================")
        print(f"Title API parity summary: {passed}/{total} passed")
        if failed:
            print("\nFailed tests:")
            for name, ok, detail in self.results:
                if not ok:
                    print(f"- {name}: {detail}")
            return False
        print("All title API parity checks passed.")
        return True


def parse_json(raw):
    if not raw:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return raw


def pretty(value):
    if isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=False, indent=2)
    return str(value)


def as_list(value):
    return value if isinstance(value, list) else []


def as_dict(value):
    return value if isinstance(value, dict) else {}


def as_float(value):
    if value is None or isinstance(value, bool):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def ids(items):
    return [item.get("id") or item.get("imdbId") for item in as_list(items) if isinstance(item, dict)]


def require_items(payload, label):
    data = as_dict(payload)
    items = data.get("items")
    if not isinstance(items, list):
        raise AssertionError(f"{label} must return an object with an items list.")
    return items


def require_keys(data, keys, label):
    if not isinstance(data, dict):
        raise AssertionError(f"{label} must be an object.")
    missing = [key for key in keys if key not in data]
    if missing:
        raise AssertionError(f"{label} is missing keys: {', '.join(missing)}")


def require_summary_schema(items, label):
    required = [
        "id",
        "title",
        "type",
        "year",
        "endYear",
        "imageUrl",
        "rank",
        "subtitle",
        "rating",
        "voteCount",
        "canHaveEpisodes",
    ]
    for index, item in enumerate(as_list(items)):
        require_keys(item, required, f"{label}[{index}]")
        if not item.get("id") or not item.get("title"):
            raise AssertionError(f"{label}[{index}] must have id and title.")


def require_details_schema(payload):
    require_keys(
        payload,
        ["summary", "imdbDetails", "omdbDetails", "seriesOverview", "errors"],
        "title details response",
    )
    require_summary_schema([payload.get("summary")], "title details summary")
    if payload.get("imdbDetails") is not None:
        require_keys(
            payload["imdbDetails"],
            [
                "id",
                "title",
                "originalTitle",
                "type",
                "canHaveEpisodes",
                "imageUrl",
                "releaseYear",
                "endYear",
                "rating",
                "voteCount",
                "runtimeSeconds",
                "runtimeMinutes",
                "certificate",
                "genres",
                "plot",
                "releaseDate",
                "productionStatus",
                "latestTrailerId",
            ],
            "imdbDetails",
        )
    if payload.get("omdbDetails") is not None:
        require_keys(
            payload["omdbDetails"],
            [
                "imdbId",
                "id",
                "title",
                "year",
                "type",
                "poster",
                "imageUrl",
                "imdbRating",
                "imdbVotes",
                "totalSeasons",
                "isSeries",
            ],
            "omdbDetails",
        )


def require_episode_schema(items, label):
    required = [
        "id",
        "title",
        "seasonNumber",
        "episodeNumber",
        "releaseDate",
        "plot",
        "imageUrl",
        "rating",
        "voteCount",
    ]
    for index, item in enumerate(as_list(items)):
        require_keys(item, required, f"{label}[{index}]")
        if not item.get("id") or not item.get("title"):
            raise AssertionError(f"{label}[{index}] must have id and title.")


def compare_id_order(expected, actual, label, minimum=3):
    expected_ids = ids(expected)
    actual_ids = ids(actual)
    if not expected_ids:
        raise AssertionError(f"Upstream {label} returned no ids, cannot compare.")
    if not actual_ids:
        raise AssertionError(f"Server {label} returned no ids.")

    size = min(minimum, len(expected_ids), len(actual_ids))
    if actual_ids[:size] != expected_ids[:size]:
        raise AssertionError(
            f"{label} id order mismatch.\n"
            f"expected first {size}: {expected_ids[:size]}\n"
            f"actual first {size}:   {actual_ids[:size]}"
        )


def compare_id_overlap(expected, actual, label, minimum_overlap=3):
    expected_ids = ids(expected)
    actual_ids = ids(actual)
    if not expected_ids:
        raise AssertionError(f"Upstream {label} returned no ids, cannot compare.")
    if not actual_ids:
        raise AssertionError(f"Server {label} returned no ids.")

    overlap = [item_id for item_id in actual_ids if item_id in set(expected_ids)]
    required = min(minimum_overlap, len(expected_ids), len(actual_ids))
    if len(overlap) < required:
        raise AssertionError(
            f"{label} id overlap mismatch.\n"
            f"expected ids: {expected_ids}\n"
            f"actual ids:   {actual_ids}\n"
            f"overlap:      {overlap}"
        )


def compare_fields(expected, actual, fields, label, rating_tolerance=0.05):
    for field in fields:
        left = expected.get(field)
        right = actual.get(field)
        if field in ("rating", "imdbRating"):
            left_float = as_float(left)
            right_float = as_float(right)
            if left_float is None and right_float is None:
                continue
            if left_float is None or right_float is None:
                raise AssertionError(f"{label}.{field} mismatch: expected {left}, got {right}")
            if abs(left_float - right_float) > rating_tolerance:
                raise AssertionError(f"{label}.{field} mismatch: expected {left}, got {right}")
            continue
        if left != right:
            raise AssertionError(f"{label}.{field} mismatch: expected {left}, got {right}")


def summary_from_imdb_details(details):
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


def summary_from_omdb_details(details):
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


def first_year(value):
    if not value:
        return None
    import re

    match = re.search(r"\d{4}", str(value))
    return int(match.group(0)) if match else None


def votes_to_int(value):
    if not value:
        return None
    try:
        return int(str(value).replace(",", "").strip())
    except ValueError:
        return None


def direct_summary_by_id(imdb, omdb, title_id):
    metadata = imdb.fetch_title_metadata([title_id])
    if metadata:
        return [summary_from_imdb_details(metadata[0])]
    omdb_details = omdb.fetch_title_by_id(title_id)
    if omdb_details:
        return [summary_from_omdb_details(omdb_details)]
    return []


def fetch_omdb_title_if_configured(omdb, title_id, require_omdb):
    if not omdb.is_configured:
        if require_omdb:
            raise AssertionError("OMDB_API_KEY is required for OMDb parity checks.")
        return None
    return omdb.fetch_title_by_id(title_id)


def fetch_omdb_season_if_configured(omdb, title_id, season, require_omdb):
    if not omdb.is_configured:
        if require_omdb:
            raise AssertionError("OMDB_API_KEY is required for OMDb season parity checks.")
        return None
    return omdb.fetch_season(title_id, season)


def title_type_ids(value):
    if value == "movie":
        return ["movie"]
    if value == "series":
        return ["tvSeries", "tvMiniSeries"]
    return ["movie", "tvSeries", "tvMiniSeries"]


def run_checks(args, imdb_client_cls, omdb_client_cls):
    if args.omdb_api_key:
        os.environ["OMDB_API_KEY"] = args.omdb_api_key

    server = ServerApiClient(args.base_url, timeout=args.timeout)
    imdb = imdb_client_cls(timeout=args.timeout)
    omdb = omdb_client_cls(timeout=args.timeout)
    runner = TestRunner()

    first = args.first
    title_id = args.title_id.strip()
    series_id = args.series_id.strip()
    season = args.season

    runner.check(
        "GET /health",
        lambda: check_health(server),
    )

    runner.check(
        "GET /titles/search suggestion parity",
        lambda: check_search_suggestions(server, imdb, args.search_query, first),
    )

    runner.check(
        "GET /titles/search movie parity",
        lambda: check_search_typed(server, imdb, args.movie_query, "movie", first),
    )

    runner.check(
        "GET /titles/search series parity",
        lambda: check_search_typed(server, imdb, args.search_query, "series", first),
    )

    runner.check(
        "GET /titles/search with IMDb id parity",
        lambda: check_search_id_route(server, imdb, omdb, title_id),
    )

    runner.check(
        "GET /titles/search-by-id/{title_id} parity",
        lambda: check_search_by_id(server, imdb, omdb, title_id),
    )

    runner.check(
        "GET /titles/advanced-search parity",
        lambda: check_advanced_search(server, imdb, args.movie_query, first),
    )

    runner.check(
        "GET /titles/trending parity",
        lambda: check_trending(server, imdb, first),
    )

    runner.check(
        "GET /titles/popular/movies parity",
        lambda: check_popular(server, imdb, "movies", first),
    )

    runner.check(
        "GET /titles/popular/series parity",
        lambda: check_popular(server, imdb, "series", first),
    )

    runner.check(
        "GET /titles/new parity",
        lambda: check_new_titles(server, imdb, first),
    )

    runner.check(
        "GET /titles/top-rated parity",
        lambda: check_top_rated(server, imdb, first),
    )

    runner.check(
        "GET /titles/metadata parity",
        lambda: check_metadata(server, imdb, [title_id, series_id]),
    )

    runner.check(
        "GET /titles/{title_id} IMDb/OMDb detail parity",
        lambda: check_details(server, imdb, omdb, title_id, args.require_omdb),
    )

    runner.check(
        "GET /titles/{series_id}/overview parity",
        lambda: check_overview(server, imdb, series_id),
    )

    runner.check(
        "GET /titles/{series_id}/seasons/{season}/episodes parity",
        lambda: check_episodes(server, imdb, omdb, series_id, season, args.require_omdb),
    )

    return runner.summary()


def check_health(server):
    payload = server.expect_get("/health")
    if not isinstance(payload, dict):
        raise AssertionError("/health must return a JSON object.")
    return pretty(payload)


def check_search_suggestions(server, imdb, query, first):
    expected = imdb.search_suggestions(query)
    payload = server.expect_get("/titles/search", {"q": query, "first": first})
    actual = require_items(payload, "/titles/search")
    require_summary_schema(actual, "/titles/search items")
    compare_id_order(expected, actual, "/titles/search suggestion", minimum=3)
    return f"matched ids: {ids(actual)[:3]}"


def check_search_typed(server, imdb, query, media_type, first):
    expected = imdb.advanced_title_search(
        search_term=query,
        first=first,
        title_type_ids=title_type_ids(media_type),
    )
    payload = server.expect_get(
        "/titles/search",
        {"q": query, "type": media_type, "first": first},
    )
    actual = require_items(payload, f"/titles/search type={media_type}")
    require_summary_schema(actual, f"/titles/search type={media_type} items")
    compare_id_order(expected, actual, f"/titles/search type={media_type}", minimum=3)
    return f"matched ids: {ids(actual)[:3]}"


def check_search_id_route(server, imdb, omdb, title_id):
    expected = direct_summary_by_id(imdb, omdb, title_id)
    payload = server.expect_get("/titles/search", {"q": title_id})
    actual = require_items(payload, "/titles/search id")
    require_summary_schema(actual, "/titles/search id items")
    compare_id_order(expected, actual, "/titles/search id", minimum=1)
    compare_fields(expected[0], actual[0], ["id", "title", "year"], "/titles/search id item")
    return pretty(actual[0])


def check_search_by_id(server, imdb, omdb, title_id):
    expected = direct_summary_by_id(imdb, omdb, title_id)
    payload = server.expect_get(f"/titles/search-by-id/{parse.quote(title_id)}")
    actual = require_items(payload, "/titles/search-by-id")
    require_summary_schema(actual, "/titles/search-by-id items")
    compare_id_order(expected, actual, "/titles/search-by-id", minimum=1)
    compare_fields(expected[0], actual[0], ["id", "title", "year"], "/titles/search-by-id item")
    return pretty(actual[0])


def check_advanced_search(server, imdb, query, first):
    expected = imdb.advanced_title_search(
        search_term=query,
        first=first,
        title_type_ids=["movie"],
        sort_by="POPULARITY",
        sort_order="ASC",
    )
    payload = server.expect_get(
        "/titles/advanced-search",
        {"q": query, "type": "movie", "first": first},
    )
    actual = require_items(payload, "/titles/advanced-search")
    require_summary_schema(actual, "/titles/advanced-search items")
    compare_id_order(expected, actual, "/titles/advanced-search", minimum=3)
    return f"matched ids: {ids(actual)[:3]}"


def check_trending(server, imdb, first):
    expected = imdb.fetch_trending(first=first)
    payload = server.expect_get("/titles/trending", {"first": first})
    actual = require_items(payload, "/titles/trending")
    require_summary_schema(actual, "/titles/trending items")
    compare_id_overlap(expected, actual, "/titles/trending", minimum_overlap=3)
    return f"server ids: {ids(actual)[:first]}"


def check_popular(server, imdb, kind, first):
    media_type = "movie" if kind == "movies" else "series"
    expected = imdb.advanced_title_search(
        first=first,
        title_type_ids=title_type_ids(media_type),
    )
    payload = server.expect_get(f"/titles/popular/{kind}", {"first": first})
    actual = require_items(payload, f"/titles/popular/{kind}")
    require_summary_schema(actual, f"/titles/popular/{kind} items")
    compare_id_order(expected, actual, f"/titles/popular/{kind}", minimum=3)
    return f"matched ids: {ids(actual)[:3]}"


def check_new_titles(server, imdb, first):
    from datetime import datetime

    now = datetime.utcnow()
    expected = imdb.advanced_title_search(
        first=first,
        title_type_ids=["movie", "tvSeries", "tvMiniSeries"],
        release_date_start=f"{now.year}-01-01",
        release_date_end=f"{now.year}-12-31",
    )
    payload = server.expect_get("/titles/new", {"first": first})
    actual = require_items(payload, "/titles/new")
    require_summary_schema(actual, "/titles/new items")
    compare_id_order(expected, actual, "/titles/new", minimum=3)
    return f"matched ids: {ids(actual)[:3]}"


def check_top_rated(server, imdb, first):
    expected = imdb.advanced_title_search(
        first=first,
        title_type_ids=["movie"],
        minimum_rating=8,
        minimum_votes=50000,
        top_rated_movies_only=True,
    )
    payload = server.expect_get("/titles/top-rated", {"first": first})
    actual = require_items(payload, "/titles/top-rated")
    require_summary_schema(actual, "/titles/top-rated items")
    compare_id_order(expected, actual, "/titles/top-rated", minimum=3)
    return f"matched ids: {ids(actual)[:3]}"


def check_metadata(server, imdb, title_ids):
    unique_ids = sorted({item for item in title_ids if item})
    expected = imdb.fetch_title_metadata(unique_ids)
    payload = server.expect_get("/titles/metadata", {"ids": ",".join(unique_ids)})
    actual = require_items(payload, "/titles/metadata")
    if len(actual) != len(expected):
        raise AssertionError(
            f"/titles/metadata count mismatch: expected {len(expected)}, got {len(actual)}"
        )
    by_id = {item["id"]: item for item in actual}
    for expected_item in expected:
        actual_item = by_id.get(expected_item.get("id"))
        if not actual_item:
            raise AssertionError(f"metadata missing id {expected_item.get('id')}")
        compare_fields(
            expected_item,
            actual_item,
            ["id", "title", "releaseYear", "rating", "voteCount"],
            f"metadata {expected_item.get('id')}",
        )
    return f"matched ids: {ids(actual)}"


def check_details(server, imdb, omdb, title_id, require_omdb):
    payload = server.expect_get(f"/titles/{parse.quote(title_id)}")
    if not isinstance(payload, dict):
        raise AssertionError("/titles/{title_id} must return a JSON object.")
    require_details_schema(payload)

    metadata = imdb.fetch_title_metadata([title_id])
    if metadata:
        if payload.get("imdbDetails") is None:
            raise AssertionError("Server details response has no imdbDetails.")
        compare_fields(
            metadata[0],
            payload["imdbDetails"],
            ["id", "title", "releaseYear", "rating", "voteCount"],
            "imdbDetails",
        )
        expected_summary = summary_from_imdb_details(metadata[0])
        compare_fields(
            expected_summary,
            payload["summary"],
            ["id", "title", "year", "rating", "voteCount"],
            "summary",
        )

    omdb_details = fetch_omdb_title_if_configured(omdb, title_id, require_omdb)
    if omdb_details is not None:
        if payload.get("omdbDetails") is None:
            raise AssertionError("Server details response has no omdbDetails.")
        compare_fields(
            omdb_details,
            payload["omdbDetails"],
            ["imdbId", "title", "year", "type", "imdbRating", "totalSeasons"],
            "omdbDetails",
        )

    return pretty(
        {
            "summary": payload.get("summary"),
            "has_imdbDetails": payload.get("imdbDetails") is not None,
            "has_omdbDetails": payload.get("omdbDetails") is not None,
        }
    )


def check_overview(server, imdb, series_id):
    expected = imdb.fetch_series_overview(series_id)
    payload = server.expect_get(f"/titles/{parse.quote(series_id)}/overview")
    require_keys(
        payload,
        [
            "titleId",
            "isOngoing",
            "totalEpisodes",
            "latestSeasonNumber",
            "latestEpisodeNumber",
            "latestReleaseDate",
            "nextSeasonNumber",
            "nextEpisodeNumber",
            "nextReleaseDate",
        ],
        "series overview",
    )
    compare_fields(
        expected,
        payload,
        ["titleId", "isOngoing", "totalEpisodes", "latestSeasonNumber", "latestEpisodeNumber"],
        "seriesOverview",
    )
    return pretty(payload)


def check_episodes(server, imdb, omdb, series_id, season, require_omdb):
    imdb_episodes = imdb.fetch_season_episodes(series_id, season)
    expected = imdb_episodes
    expected_source = "imdb"

    if not expected:
        omdb_season = fetch_omdb_season_if_configured(omdb, series_id, season, require_omdb)
        expected = as_dict(omdb_season).get("episodes") or []
        expected_source = "omdb" if expected else "none"

    payload = server.expect_get(
        f"/titles/{parse.quote(series_id)}/seasons/{season}/episodes"
    )
    require_keys(payload, ["items", "source"], "season episodes response")
    actual = require_items(payload, "season episodes response")
    require_episode_schema(actual, "season episodes")

    if expected:
        compare_id_order(expected, actual, "season episodes", minimum=3)
        if payload.get("source") != expected_source:
            raise AssertionError(
                f"season episode source mismatch: expected {expected_source}, got {payload.get('source')}"
            )
    elif actual:
        raise AssertionError("Server returned episodes while upstream comparison returned none.")

    return f"source={payload.get('source')} matched ids: {ids(actual)[:3]}"


def build_parser():
    parser = argparse.ArgumentParser(
        description=(
            "Compare the backend /titles API responses with the direct IMDb/OMDb "
            "clients used by the project."
        )
    )
    parser.add_argument(
        "--base-url",
        default=os.getenv("IMDB_BACKEND_URL", DEFAULT_BASE_URL),
        help=f"Backend base URL. Default: {DEFAULT_BASE_URL}",
    )
    parser.add_argument("--services-dir", help="Folder containing imdb_client.py and omdb_client.py")
    parser.add_argument("--omdb-api-key", default=os.getenv("OMDB_API_KEY", ""))
    parser.add_argument(
        "--require-omdb",
        action="store_true",
        help="Fail if OMDB_API_KEY is missing or OMDb data is not returned by the server.",
    )
    parser.add_argument("--title-id", default=DEFAULT_TITLE_ID)
    parser.add_argument("--series-id", default=DEFAULT_SERIES_ID)
    parser.add_argument("--search-query", default=DEFAULT_SEARCH_QUERY)
    parser.add_argument("--movie-query", default=DEFAULT_MOVIE_QUERY)
    parser.add_argument("--season", type=int, default=DEFAULT_SEASON)
    parser.add_argument("--first", type=int, default=DEFAULT_FIRST)
    parser.add_argument("--timeout", type=int, default=35)
    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()

    if not args.base_url.startswith(("http://", "https://")):
        print("Base URL must start with http:// or https://")
        return 2
    if args.first < 3:
        print("--first must be at least 3 for useful parity checks.")
        return 2
    if args.season < 1:
        print("--season must be at least 1.")
        return 2

    try:
        ImdbClient, _, OmdbClient, _, services_path = load_upstream_clients(args.services_dir)
    except Exception as exc:
        print(str(exc))
        return 2

    print(f"Backend: {args.base_url.rstrip('/')}")
    print(f"Services: {services_path}")
    print(f"OMDb parity: {'enabled' if args.omdb_api_key else 'skipped unless server returns data'}")

    ok = run_checks(args, ImdbClient, OmdbClient)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
