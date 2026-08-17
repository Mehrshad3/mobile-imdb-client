import argparse
import getpass
import json
import os
import re
import sys
import time
from pathlib import Path
from urllib import error, request


DEFAULT_TITLE_ID = "tt2560140"


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


def masked_token(token):
    token = (token or "").strip()
    if len(token) <= 16:
        return "***"
    return f"{token[:8]}...{token[-8:]}"


class TestRunner:
    def __init__(self):
        self.results = []

    def record(self, name, ok, status, payload=None):
        self.results.append((name, ok, status))
        marker = "PASS" if ok else "FAIL"
        print(f"\n[{marker}] {name}")
        print(f"status: {status}")
        if not ok or isinstance(payload, dict):
            print(pretty(payload))

    def expect(self, client, name, method, path, body=None, expected=(200,), validator=None):
        status, payload = client.send(method, path, body=body)
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
        print(f"Admin API test summary: {passed}/{total} passed")

        if failed:
            print("\nFailed tests:")
            for name, ok, status in self.results:
                if not ok:
                    print(f"- {name} (status {status})")
            return False

        print("All tested admin endpoints passed.")
        return True


def login(base_url, runner, label, email, password):
    client = ApiClient(base_url)
    payloads = [
        ("email", {"email": email, "password": password}),
        ("email_or_username", {"email_or_username": email, "password": password}),
        ("username_or_email", {"username_or_email": email, "password": password}),
        ("identifier", {"identifier": email, "password": password}),
    ]

    last_status = None
    last_payload = None

    for payload_label, body in payloads:
        status, payload = client.send("POST", "/auth/login", body=body, token=False)
        token = find_token(payload)
        if token:
            client.token = token
            runner.record(f"{label}: POST /auth/login using {payload_label}", True, status, payload)
            return client
        last_status = status
        last_payload = payload

    runner.record(f"{label}: POST /auth/login", False, last_status, last_payload)
    return None


def authenticated_client_from_token(base_url, runner, label, token):
    client = ApiClient(base_url)
    client.token = token.strip()
    runner.record(
        f"{label}: using provided token",
        bool(client.token),
        "local",
        {"token": masked_token(client.token)},
    )
    return client if client.token else None


def authenticated_client(base_url, runner, label, email=None, password=None, token=None):
    if token:
        return authenticated_client_from_token(base_url, runner, label, token)
    if email and password:
        return login(base_url, runner, label, email, password)
    return None


def ask_if_missing(value, label, secret=False):
    if value:
        return value
    if secret:
        return getpass.getpass(f"{label}: ").strip()
    return input(f"{label}: ").strip()


def default_base_url():
    for key in ("IMDB_ADMIN_TEST_BASE_URL", "IMDB_BACKEND_URL"):
        value = os.environ.get(key)
        if value:
            return value.strip()

    main_dart = Path("lib") / "main.dart"
    if main_dart.exists():
        match = re.search(
            r"imdbBackendBaseUrl\s*=\s*['\"]([^'\"]+)['\"]",
            main_dart.read_text(encoding="utf-8", errors="ignore"),
        )
        if match:
            return match.group(1).strip()

    return ""


def user_id_from_payload(payload):
    if not isinstance(payload, dict):
        return None
    user = payload.get("user") if isinstance(payload.get("user"), dict) else payload
    value = user.get("id") or user.get("user_id")
    return str(value) if value is not None else None


def user_role_from_payload(payload):
    if not isinstance(payload, dict):
        return None
    user = payload.get("user") if isinstance(payload.get("user"), dict) else payload
    return str(user.get("role") or "").lower()


def payload_has_user_with_email(payload, email):
    if not isinstance(payload, dict) or not email:
        return False
    items = payload.get("items") or payload.get("users") or []
    if not isinstance(items, list):
        return False
    return any(
        isinstance(item, dict) and str(item.get("email", "")).lower() == email.lower()
        for item in items
    )


def payload_has_review_text(payload, text):
    if not isinstance(payload, dict):
        return False
    items = payload.get("items") or payload.get("reviews") or []
    if not isinstance(items, list):
        return False
    return any(isinstance(item, dict) and item.get("text") == text for item in items)


def find_user_by_email(users_payload, email):
    if not isinstance(users_payload, dict):
        return None
    items = users_payload.get("items") or users_payload.get("users") or []
    if not isinstance(items, list):
        return None
    for item in items:
        if isinstance(item, dict) and str(item.get("email", "")).lower() == email.lower():
            return item
    return None


def print_connection_diagnostics(base_url):
    print("\nConnection diagnostics")
    print(f"- The test could not connect to: {base_url}")
    print("- On the server, run:")
    print("  sudo systemctl status imdb-backend --no-pager")
    print("  sudo journalctl -u imdb-backend -n 120 --no-pager")
    print("  cd ~/imdb_backend")
    print("  source .venv/bin/activate")
    print("  python -m py_compile app/routers/admin.py")
    print("  python -c \"from app.main import app; print('import ok')\"")


def test_server_preflight(base_url, runner):
    client = ApiClient(base_url)
    ok, status, _ = runner.expect(
        client,
        "GET /health",
        "GET",
        "/health",
        expected=(200,),
    )
    if not ok:
        if status == 0:
            print_connection_diagnostics(base_url)
        return False

    runner.expect(
        client,
        "GET /admin/users without token is protected",
        "GET",
        "/admin/users",
        expected=(401, 403),
    )
    return True


def test_admin_access(
    base_url,
    runner,
    admin_email=None,
    admin_password=None,
    admin_token=None,
    user_email=None,
    user_password=None,
    user_token=None,
    title_id=DEFAULT_TITLE_ID,
):
    admin_client = authenticated_client(
        base_url,
        runner,
        "admin",
        email=admin_email,
        password=admin_password,
        token=admin_token,
    )
    if admin_client is None:
        runner.record(
            "admin credentials or token are required",
            False,
            0,
            {
                "hint": (
                    "Pass --admin-token or pass both --admin-email and "
                    "--admin-password."
                )
            },
        )
        return

    if (user_email and user_password) or user_token:
        normal_client = authenticated_client(
            base_url,
            runner,
            "normal user",
            email=user_email,
            password=user_password,
            token=user_token,
        )
        if normal_client is not None:
            runner.expect(
                normal_client,
                "normal user cannot access GET /admin/users",
                "GET",
                "/admin/users",
                expected=(403,),
            )

    _, _, me_payload = runner.expect(
        admin_client,
        "GET /users/me as admin",
        "GET",
        "/users/me",
        validator=lambda payload: user_role_from_payload(payload) == "admin",
    )
    admin_id = user_id_from_payload(me_payload)

    ok, _, users_payload = runner.expect(
        admin_client,
        "admin can access GET /admin/users",
        "GET",
        "/admin/users",
        expected=(200,),
        validator=lambda payload: isinstance(payload, dict)
        and isinstance(payload.get("items"), list),
    )
    if ok and admin_email:
        runner.record(
            "admin user is present in /admin/users",
            payload_has_user_with_email(users_payload, admin_email),
            200,
            {"email": admin_email},
        )

    runner.expect(
        admin_client,
        "admin can access GET /admin/stats",
        "GET",
        "/admin/stats",
        expected=(200,),
        validator=lambda payload: isinstance(payload, dict)
        and "users" in payload
        and "reviews" in payload,
    )

    if admin_id:
        runner.expect(
            admin_client,
            "admin cannot set an invalid role",
            "PATCH",
            f"/admin/users/{admin_id}/role",
            body={"role": "owner"},
            expected=(400,),
        )

    runner.expect(
        admin_client,
        "admin gets 404 for missing user role update",
        "PATCH",
        "/admin/users/999999999/role",
        body={"role": "user"},
        expected=(404,),
    )

    if ok and user_email:
        target = find_user_by_email(users_payload, user_email)
        if target is not None:
            target_id = str(target.get("id"))
            original_role = str(target.get("role") or "user")
            runner.expect(
                admin_client,
                "admin can promote target user",
                "PATCH",
                f"/admin/users/{target_id}/role",
                body={"role": "admin"},
                expected=(200,),
                validator=lambda payload: isinstance(payload, dict)
                and isinstance(payload.get("user"), dict)
                and payload["user"].get("role") == "admin",
            )
            runner.expect(
                admin_client,
                "admin can restore target user role",
                "PATCH",
                f"/admin/users/{target_id}/role",
                body={"role": original_role},
                expected=(200,),
                validator=lambda payload: isinstance(payload, dict)
                and isinstance(payload.get("user"), dict)
                and payload["user"].get("role") == original_role,
            )
        else:
            runner.record(
                "target user was not found in /admin/users",
                False,
                0,
                {"email": user_email},
            )

    if admin_id:
        runner.expect(
            admin_client,
            "admin cannot delete own account",
            "DELETE",
            f"/admin/users/{admin_id}",
            expected=(400,),
        )

    review_text = f"api_admin_test removable review {int(time.time())}"
    metadata = {
        "title": "Attack on Titan",
        "year": "2013",
        "poster_url": "https://m.media-amazon.com/images/M/MV5BNjY4MDQxZTItM2JjMi00NjM5LTk0MWYtOTBlNTY2YjBiNmFjXkEyXkFqcGc@._V1_.jpg",
        "media_type": "series",
    }
    runner.expect(
        admin_client,
        "admin creates temporary review",
        "POST",
        f"/titles/{title_id}/review",
        body={"text": review_text, "contains_spoiler": False, **metadata},
        expected=(200, 201),
    )
    ok, _, reviews_payload = runner.expect(
        admin_client,
        "admin can list reviews",
        "GET",
        f"/admin/reviews?title_id={title_id}",
        expected=(200,),
        validator=lambda payload: isinstance(payload, dict)
        and isinstance(payload.get("items"), list),
    )
    if ok:
        review_id = None
        for item in reviews_payload.get("items", []):
            if isinstance(item, dict) and item.get("text") == review_text:
                review_id = item.get("id")
                break
        if review_id is None:
            runner.record("temporary review is visible to admin", False, 0, reviews_payload)
        else:
            runner.expect(
                admin_client,
                "admin can delete temporary review",
                "DELETE",
                f"/admin/reviews/{review_id}",
                expected=(200, 204),
            )
            runner.expect(
                admin_client,
                "temporary review is gone after admin delete",
                "GET",
                f"/admin/reviews?title_id={title_id}",
                expected=(200,),
                validator=lambda payload: not payload_has_review_text(payload, review_text),
            )

    runner.expect(
        admin_client,
        "admin gets 404 for missing review delete",
        "DELETE",
        "/admin/reviews/999999999",
        expected=(404,),
    )


def main():
    parser = argparse.ArgumentParser(description="Test admin endpoints of the IMDb backend.")
    parser.add_argument("--base-url", help="Example: http://1.2.3.4:8000")
    parser.add_argument("--admin-email", help="Admin email address")
    parser.add_argument("--admin-password", help="Admin password")
    parser.add_argument("--admin-token", help="Existing admin access token")
    parser.add_argument("--user-email", help="Normal user email address for permission/role tests")
    parser.add_argument("--user-password", help="Normal user password")
    parser.add_argument("--user-token", help="Existing normal-user access token")
    parser.add_argument("--title-id", default=DEFAULT_TITLE_ID)
    parser.add_argument(
        "--preflight-only",
        action="store_true",
        help="Only test /health and protected admin routes. No login required.",
    )
    args = parser.parse_args()

    base_url = (
        args.base_url
        or default_base_url()
        or ask_if_missing(None, "Base URL")
    ).rstrip("/")

    admin_token = args.admin_token or os.environ.get("IMDB_ADMIN_TOKEN")
    admin_email = args.admin_email or os.environ.get("IMDB_ADMIN_EMAIL")
    admin_password = args.admin_password or os.environ.get("IMDB_ADMIN_PASSWORD")
    user_token = args.user_token or os.environ.get("IMDB_NORMAL_USER_TOKEN")
    user_email = args.user_email or os.environ.get("IMDB_NORMAL_USER_EMAIL")
    user_password = args.user_password or os.environ.get("IMDB_NORMAL_USER_PASSWORD")

    if not args.preflight_only and not admin_token:
        admin_email = ask_if_missing(admin_email, "Admin email")
        admin_password = ask_if_missing(admin_password, "Admin password", secret=True)

    if not base_url.startswith(("http://", "https://")):
        print("Base URL must start with http:// or https://")
        return 2

    runner = TestRunner()
    if not test_server_preflight(base_url, runner):
        runner.summary()
        return 1

    if args.preflight_only:
        return 0 if runner.summary() else 1

    test_admin_access(
        base_url,
        runner,
        admin_email=admin_email,
        admin_password=admin_password,
        admin_token=admin_token,
        user_email=user_email,
        user_password=user_password,
        user_token=user_token,
        title_id=args.title_id,
    )
    return 0 if runner.summary() else 1


if __name__ == "__main__":
    sys.exit(main())
