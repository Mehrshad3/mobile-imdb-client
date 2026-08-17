import argparse
import getpass
import json
import sys
import time
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


def ask_if_missing(value, label, secret=False):
    if value:
        return value
    if secret:
        return getpass.getpass(f"{label}: ").strip()
    return input(f"{label}: ").strip()


def user_id_from_payload(payload):
    if not isinstance(payload, dict):
        return None
    user = payload.get("user") if isinstance(payload.get("user"), dict) else payload
    value = user.get("id") or user.get("user_id")
    return str(value) if value is not None else None


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


def test_admin_access(base_url, runner, admin_email, admin_password, user_email=None, user_password=None):
    admin_client = login(base_url, runner, "admin", admin_email, admin_password)
    if admin_client is None:
        return

    if user_email and user_password:
        normal_client = login(base_url, runner, "normal user", user_email, user_password)
        if normal_client is not None:
            runner.expect(
                normal_client,
                "normal user cannot access GET /admin/users",
                "GET",
                "/admin/users",
                expected=(403,),
            )

    runner.expect(admin_client, "GET /users/me as admin", "GET", "/users/me")
    ok, _, users_payload = runner.expect(
        admin_client,
        "admin can access GET /admin/users",
        "GET",
        "/admin/users",
        expected=(200,),
        validator=lambda payload: isinstance(payload, dict)
        and isinstance(payload.get("items"), list),
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

    _, me_payload = admin_client.send("GET", "/users/me")
    admin_id = user_id_from_payload(me_payload)
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
        f"/titles/{DEFAULT_TITLE_ID}/review",
        body={"text": review_text, "contains_spoiler": False, **metadata},
        expected=(200, 201),
    )
    ok, _, reviews_payload = runner.expect(
        admin_client,
        "admin can list reviews",
        "GET",
        f"/admin/reviews?title_id={DEFAULT_TITLE_ID}",
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


def main():
    parser = argparse.ArgumentParser(description="Test admin endpoints of the IMDb backend.")
    parser.add_argument("--base-url", help="Example: http://1.2.3.4:8000")
    parser.add_argument("--admin-email", help="Admin email address")
    parser.add_argument("--admin-password", help="Admin password")
    parser.add_argument("--user-email", help="Normal user email address for permission/role tests")
    parser.add_argument("--user-password", help="Normal user password")
    args = parser.parse_args()

    base_url = ask_if_missing(args.base_url, "Base URL").rstrip("/")
    admin_email = ask_if_missing(args.admin_email, "Admin email")
    admin_password = ask_if_missing(args.admin_password, "Admin password", secret=True)

    if not base_url.startswith(("http://", "https://")):
        print("Base URL must start with http:// or https://")
        return 2

    runner = TestRunner()
    if not test_server_preflight(base_url, runner):
        runner.summary()
        return 1

    test_admin_access(
        base_url,
        runner,
        admin_email,
        admin_password,
        user_email=args.user_email,
        user_password=args.user_password,
    )
    return 0 if runner.summary() else 1


if __name__ == "__main__":
    sys.exit(main())
