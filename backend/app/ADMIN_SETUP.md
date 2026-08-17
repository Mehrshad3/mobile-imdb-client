# Admin server files

Copy these files into the Ubuntu backend project:

```text
new_server_api/routers/admin.py   -> ~/imdb_backend/app/routers/admin.py
new_server_api/migrate_admin.py   -> ~/imdb_backend/migrate_admin.py
new_server_api/make_admin.py      -> ~/imdb_backend/make_admin.py
api_admin_test.py                 -> ~/imdb_backend/api_admin_test.py
```

Then edit `~/imdb_backend/app/main.py` and add `admin` to the router imports:

```python
from .routers import auth, progress, ratings, users, watchlist, titles, admin
```

Also include the admin router after the other routers:

```python
app.include_router(admin.router)
```

Run the migration:

```bash
cd ~/imdb_backend
source .venv/bin/activate
python migrate_admin.py
```

If the migration cannot find the database file automatically, pass it manually:

```bash
python migrate_admin.py --db /home/ubuntu/imdb_backend/YOUR_DATABASE.sqlite3
```

Promote one registered user to admin:

```bash
python make_admin.py your-email@example.com
```

Restart the service:

```bash
sudo systemctl restart imdb-backend
sudo systemctl status imdb-backend --no-pager
```

Run the admin API test:

```bash
python api_admin_test.py --base-url http://127.0.0.1:8000 --admin-email your-email@example.com --admin-password YOUR_PASSWORD
```

For the full permission and role-change test, pass a normal user too:

```bash
python api_admin_test.py --base-url http://127.0.0.1:8000 --admin-email your-email@example.com --admin-password YOUR_PASSWORD --user-email normal@example.com --user-password NORMAL_PASSWORD
```
