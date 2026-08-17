import argparse
import getpass
import json
import sys
import time
from urllib import error, request


DEFAULT_TITLE_ID = "tt2560140"
DEFAULT_EPISODE_ID = "tt0959621"


class ApiClient:
    def __init__(self, base_url):
        self.base_url = base_url.rstrip("/")
        self.token = None

    def send(self, method, path, body=None, token=True):
        url = f"{self.base_url}{path}"
        data = None
        headers = {"Accept": "application/json"}

        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"

        if token and self.token:
            headers["Authorization"] = f"Bearer {self.token}"

        req = request.Request(url, data=data, headers=headers, method=method)

        try:
            with request.urlopen(req, timeout=20) as response:
                raw = response.read().decode("utf-8", errors="replace")
                return response.status, parse_json(raw)
        except error.HTTPError as exc:
            raw = exc.read().decode("utf-8", errors="replace")
            return exc.code, parse_json(raw)
        except error.URLError as exc:
            return 0, {"error": str(exc.reason)}
        except TimeoutError:
            return 0, {"error": "request timed out"}


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


def find_token(payload):
    if not isinstance(payload, dict):
        return None

    for key in ("access_token", "token", "jwt"):
        value = payload.get(key)
        if isinstance(value, str) and value:
            return value

    nested = payload.get("data")
    if isinstance(nested, dict):
        return find_token(nested)

    return None


class TestRunner:
    def __init__(self, client):
        self.client = client
        self.results = []

    def record(self, name, ok, status, payload=None):
        self.results.append((name, ok, status))
        marker = "PASS" if ok else "FAIL"
        print(f"\n[{marker}] {name}")
        print(f"status: {status}")
        if not ok or isinstance(payload, dict):
            print(pretty(payload))

    def expect(
        self,
        name,
        method,
        path,
        body=None,
        expected=(200,),
        token=True,
        validator=None,
    ):
        status, payload = self.client.send(method, path, body=body, token=token)
        ok = status in expected
        if ok and validator is not None:
            ok = validator(payload)
        self.record(name, ok, status, payload)
        return ok, status, payload

    def summary(self):
        passed = sum(1 for _, ok, _ in self.results if ok)
        total = len(self.results)
        failed = total - passed

        print("\n==============================")
        print(f"API test summary: {passed}/{total} passed")

        if failed:
            print("\nFailed tests:")
            for name, ok, status in self.results:
                if not ok:
                    print(f"- {name} (status {status})")
            return False

        print("All tested endpoints passed.")
        return True


def login(client, runner, email, password):
    payloads = [
        ("email", {"email": email, "password": password}),
        ("email_or_username", {"email_or_username": email, "password": password}),
        ("username_or_email", {"username_or_email": email, "password": password}),
        ("identifier", {"identifier": email, "password": password}),
    ]

    last_status = None
    last_payload = None

    for label, body in payloads:
        status, payload = client.send("POST", "/auth/login", body=body, token=False)
        token = find_token(payload)
        if token:
            client.token = token
            runner.record(f"POST /auth/login using {label}", True, status, payload)
            return True

        last_status = status
        last_payload = payload

        if status not in (400, 401, 422):
            break

    runner.record("POST /auth/login", False, last_status, last_payload)
    return False


def test_health(runner):
    runner.expect("GET /health", "GET", "/health", expected=(200,), token=False)


def test_user_profile(runner):
    ok, _, payload = runner.expect("GET /users/me", "GET", "/users/me")

    if not ok or not isinstance(payload, dict):
        return

    patch_body = {}
    for key in ("username", "full_name", "avatar_url", "bio"):
        if key in payload:
            patch_body[key] = payload.get(key)

    if not patch_body:
        patch_body = {"bio": "api_server_test profile check"}

    runner.expect(
        "PATCH /users/me",
        "PATCH",
        "/users/me",
        body=patch_body,
        expected=(200,),
    )


def test_watchlist(runner, title_id):
    title_body = {
        "title_id": title_id,
        "title": "Attack on Titan",
        "year": "2013",
        "poster_url": "https://m.media-amazon.com/images/M/MV5BNjY4MDQxZTItM2JjMi00NjM5LTk0MWYtOTBlNTY2YjBiNmFjXkEyXkFqcGc@._V1_.jpg",
        "media_type": "series",
        "status": "planned",
        "favorite": False,
    }

    runner.expect("GET /watchlist", "GET", "/watchlist", expected=(200,))
    runner.expect(
        "POST /watchlist",
        "POST",
        "/watchlist",
        body=title_body,
        expected=(200, 201),
    )
    runner.expect(
        f"PATCH /watchlist/{title_id}",
        "PATCH",
        f"/watchlist/{title_id}",
        body={"status": "watching", "favorite": True},
        expected=(200,),
    )
    runner.expect("GET /watchlist after save", "GET", "/watchlist", expected=(200,))


def test_ratings_and_reviews(runner, title_id):
    metadata = {
        "title": "Attack on Titan",
        "year": "2013",
        "poster_url": "https://m.media-amazon.com/images/M/MV5BNjY4MDQxZTItM2JjMi00NjM5LTk0MWYtOTBlNTY2YjBiNmFjXkEyXkFqcGc@._V1_.jpg",
        "media_type": "series",
    }

    runner.expect(
        f"POST /titles/{title_id}/rating",
        "POST",
        f"/titles/{title_id}/rating",
        body={"rating": 9, **metadata},
        expected=(200, 201),
    )
    runner.expect(
        f"POST /titles/{title_id}/review",
        "POST",
        f"/titles/{title_id}/review",
        body={
            "text": f"api_server_test review at {int(time.time())}",
            "contains_spoiler": False,
            **metadata,
        },
        expected=(200, 201),
    )
    runner.expect(
        f"GET /titles/{title_id}/reviews",
        "GET",
        f"/titles/{title_id}/reviews",
        expected=(200,),
        validator=lambda payload: isinstance(payload, dict)
        and isinstance(payload.get("reviews"), list),
    )
    runner.expect(
        f"GET /titles/{title_id}/feedback",
        "GET",
        f"/titles/{title_id}/feedback",
        expected=(200,),
        validator=lambda payload: isinstance(payload, dict)
        and isinstance(payload.get("reviews"), list)
        and isinstance(payload.get("rating_summary"), dict),
    )
    runner.expect(
        "GET /titles/me/ratings",
        "GET",
        "/titles/me/ratings",
        expected=(200,),
        validator=lambda payload: isinstance(payload, dict)
        and isinstance(payload.get("items"), list),
    )
    runner.expect(
        "GET /titles/me/reviews",
        "GET",
        "/titles/me/reviews",
        expected=(200,),
        validator=lambda payload: isinstance(payload, dict)
        and isinstance(payload.get("items"), list),
    )


def test_watch_progress(runner, title_id, episode_id):
    metadata = {
        "title": "Attack on Titan",
        "year": "2013",
        "poster_url": "https://m.media-amazon.com/images/M/MV5BNjY4MDQxZTItM2JjMi00NjM5LTk0MWYtOTBlNTY2YjBiNmFjXkEyXkFqcGc@._V1_.jpg",
        "media_type": "series",
    }

    def has_episode(payload):
        if not isinstance(payload, dict):
            return False
        ids = payload.get("watched_episode_ids")
        return isinstance(ids, list) and episode_id in ids

    def all_progress_is_valid(payload):
        if not isinstance(payload, dict):
            return False
        items = payload.get("items")
        if not isinstance(items, list):
            return False
        return any(
            isinstance(item, dict)
            and item.get("title_id") == title_id
            and episode_id in item.get("watched_episode_ids", [])
            for item in items
        )

    def does_not_have_episode(payload):
        if not isinstance(payload, dict):
            return False
        ids = payload.get("watched_episode_ids")
        return isinstance(ids, list) and episode_id not in ids

    runner.expect(
        f"POST /progress/{title_id}/episodes/{episode_id}",
        "POST",
        f"/progress/{title_id}/episodes/{episode_id}",
        body=metadata,
        expected=(200, 201),
        validator=has_episode,
    )
    runner.expect(
        f"GET /progress/{title_id}",
        "GET",
        f"/progress/{title_id}",
        expected=(200,),
        validator=has_episode,
    )
    runner.expect(
        "GET /progress",
        "GET",
        "/progress",
        expected=(200,),
        validator=all_progress_is_valid,
    )
    runner.expect(
        f"DELETE /progress/{title_id}/episodes/{episode_id}",
        "DELETE",
        f"/progress/{title_id}/episodes/{episode_id}",
        expected=(200, 204),
    )
    runner.expect(
        f"GET /progress/{title_id} after delete",
        "GET",
        f"/progress/{title_id}",
        expected=(200,),
        validator=does_not_have_episode,
    )


def cleanup_test_data(runner, title_id):
    runner.expect(
        f"DELETE /progress/{title_id}/episodes/{DEFAULT_EPISODE_ID}",
        "DELETE",
        f"/progress/{title_id}/episodes/{DEFAULT_EPISODE_ID}",
        expected=(200, 204, 404),
    )
    runner.expect(
        f"DELETE /titles/{title_id}/review",
        "DELETE",
        f"/titles/{title_id}/review",
        expected=(200, 204, 404),
    )
    runner.expect(
        f"DELETE /titles/{title_id}/rating",
        "DELETE",
        f"/titles/{title_id}/rating",
        expected=(200, 204, 404),
    )
    runner.expect(
        f"DELETE /watchlist/{title_id}",
        "DELETE",
        f"/watchlist/{title_id}",
        expected=(200, 204, 404),
    )


def ask_if_missing(value, label, secret=False):
    if value:
        return value

    if secret:
        return getpass.getpass(f"{label}: ").strip()

    return input(f"{label}: ").strip()


def main():
    parser = argparse.ArgumentParser(description="Test the IMDb backend API.")
    parser.add_argument("--base-url", help="Example: http://1.2.3.4:8000")
    parser.add_argument("--email", help="Registered email address")
    parser.add_argument("--password", help="Registered account password")
    parser.add_argument("--title-id", default=DEFAULT_TITLE_ID)
    parser.add_argument("--episode-id", default=DEFAULT_EPISODE_ID)
    parser.add_argument(
        "--keep-test-data",
        action="store_true",
        help="Do not delete the test watchlist/rating/review data at the end.",
    )
    args = parser.parse_args()

    base_url = ask_if_missing(args.base_url, "Base URL").rstrip("/")
    email = ask_if_missing(args.email, "Registered email")
    password = ask_if_missing(args.password, "Password", secret=True)

    if not base_url.startswith(("http://", "https://")):
        print("Base URL must start with http:// or https://")
        return 2

    client = ApiClient(base_url)
    runner = TestRunner(client)

    test_health(runner)

    if not login(client, runner, email, password):
        runner.summary()
        return 1

    test_user_profile(runner)
    test_watchlist(runner, args.title_id)
    test_ratings_and_reviews(runner, args.title_id)
    test_watch_progress(runner, args.title_id, args.episode_id)

    if not args.keep_test_data:
        cleanup_test_data(runner, args.title_id)

    return 0 if runner.summary() else 1


if __name__ == "__main__":
    sys.exit(main())
