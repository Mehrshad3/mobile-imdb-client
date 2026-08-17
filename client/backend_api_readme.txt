برای مطالعه بیشتر و تست مستقیم APIها از Swagger/FastAPI Docs:
http://52.16.58.211:8000/docs

# مستند فارسی APIهای بک‌اند پروژه IMDb Tracker

آدرس پایه سرور:
http://52.16.58.211:8000

این فایل، APIهای بک‌اند فعلی پروژه را به زبان ساده توضیح می‌دهد؛ یعنی همان APIهایی که اپلیکیشن Flutter با آن‌ها به سرور وصل می‌شود و همچنین APIهایی که روی سرور برای مدیریت، کاربران، لیست شخصی، امتیاز، نظر، پیشرفت تماشا و دریافت اطلاعات فیلم و سریال ساخته شده‌اند.


============================================================
1. توضیح ساده معماری کلاینت - سرور
============================================================

در نسخه پیشرفته پروژه، اپلیکیشن Flutter مستقیما با IMDb، OMDb یا EmailJS کار نمی‌کند. مسیر کلی این است:

Flutter App  --->  FastAPI Backend  --->  SQLite / IMDb / OMDb / EmailJS

یعنی:

- اپلیکیشن فقط به سرور خودمان درخواست می‌زند.
- آدرس سرور در فایل lib/main.dart با متغیر imdbBackendBaseUrl تنظیم شده است.
- در وضعیت فعلی مقدار آن این است:

  http://52.16.58.211:8000

- سرور با FastAPI نوشته شده است.
- اطلاعات کاربران، رمزها، نقش‌ها، لیست تماشا، امتیازها، نظرها و پیشرفت قسمت‌ها در SQLite ذخیره می‌شود.
- اطلاعات فیلم و سریال از APIهای IMDb و در بعضی جاها OMDb گرفته می‌شود.
- برای OTP ثبت‌نام و بازیابی رمز عبور، سرور از EmailJS استفاده می‌کند.
- اپلیکیشن بعد از ورود موفق، access_token را می‌گیرد و برای درخواست‌های خصوصی در Header می‌فرستد.

Header عمومی درخواست‌ها:

Accept: application/json

اگر درخواست Body داشته باشد:

Content-Type: application/json

برای درخواست‌هایی که نیاز به ورود دارند:

Authorization: Bearer ACCESS_TOKEN

نوع خطای رایج در FastAPI معمولا این شکل است:

{
  "detail": "متن خطا"
}

کدهای وضعیت مهم:

- 200: درخواست موفق
- 201: ساخته شدن داده جدید
- 204: حذف موفق بدون بدنه پاسخ
- 400: ورودی اشتباه
- 401: کاربر وارد نشده یا Token نامعتبر است
- 403: کاربر اجازه دسترسی ندارد
- 404: داده پیدا نشد
- 422: فیلدهای لازم ارسال نشده یا نوع داده اشتباه است
- 500: خطای داخلی سرور


============================================================
2. مدل‌های مهم پاسخ
============================================================

مدل کاربر:

{
  "id": 1,
  "full_name": "Test User",
  "username": "test_user",
  "email": "test@example.com",
  "avatar_url": "",
  "bio": "",
  "role": "user",
  "created_at": "2026-08-16T20:32:59.209251"
}

role می‌تواند یکی از این دو مقدار باشد:

- user
- admin

مدل پاسخ ورود:

{
  "access_token": "...",
  "token_type": "bearer",
  "user": {
    "id": 1,
    "full_name": "Test User",
    "username": "test_user",
    "email": "test@example.com",
    "role": "admin"
  }
}

مدل خلاصه فیلم یا سریال:

{
  "id": "tt2560140",
  "title": "Attack on Titan",
  "type": "series",
  "year": 2013,
  "endYear": 2023,
  "imageUrl": "https://...",
  "rank": 1,
  "subtitle": "...",
  "rating": 9.1,
  "voteCount": 600000,
  "canHaveEpisodes": true
}

مدل آیتم لیست تماشا:

{
  "title_id": "tt2560140",
  "title": "Attack on Titan",
  "year": "2013",
  "poster_url": "https://...",
  "media_type": "series",
  "status": "watching",
  "favorite": true,
  "watched_episode_ids": ["tt0959621"]
}

مقدارهای مجاز status:

- planned: قصد دیدن
- watching: در حال تماشا
- watched: دیده شده
- stopped: متوقف شده
- dropped: رها شده

مدل خلاصه امتیاز محلی/سروری کاربران خودمان:

{
  "title_id": "tt2560140",
  "rating_count": 3,
  "average_rating": 8.7
}

مدل نظر:

{
  "id": 6,
  "user_id": 1,
  "username": "test_user",
  "full_name": "Test User",
  "title_id": "tt2560140",
  "title": "Attack on Titan",
  "text": "متن نظر",
  "contains_spoiler": false,
  "created_at": "2026-08-17T00:09:08Z",
  "updated_at": "2026-08-17T00:27:29Z"
}


============================================================
3. API سلامت سرور
============================================================

------------------------------------------------------------
GET /health
------------------------------------------------------------

آدرس کامل:
http://52.16.58.211:8000/health

نوع درخواست:
GET

احراز هویت:
لازم ندارد.

کاربرد:
برای بررسی اینکه سرور روشن است و FastAPI درست اجرا می‌شود.

نوع پاسخ:
JSON Object

نمونه پاسخ:

{
  "status": "ok",
  "message": "IMDb Tracker backend is running"
}


============================================================
4. APIهای ثبت‌نام، ورود و بازیابی رمز عبور
============================================================

------------------------------------------------------------
POST /auth/register/request-otp
------------------------------------------------------------

آدرس کامل:
http://52.16.58.211:8000/auth/register/request-otp

نوع درخواست:
POST

احراز هویت:
لازم ندارد.

کاربرد:
شروع ثبت‌نام کاربر و ارسال کد OTP به ایمیل.

Body نمونه:

{
  "full_name": "Test User",
  "display_name": "Test User",
  "username": "test_user",
  "email": "test@example.com",
  "password": "StrongPass1",
  "avatar_url": "",
  "profile_image_url": "",
  "bio": ""
}

نکات مهم:

- username نباید تکراری باشد.
- email نباید تکراری باشد.
- password نباید ساده باشد.
- OTP به ایمیل کاربر ارسال می‌شود.
- در نسخه پیشرفته، EmailJS باید فقط سمت سرور استفاده شود، نه داخل Flutter.

نوع پاسخ:
JSON Object

پاسخ موفق می‌تواند شامل message یا status باشد. مهم این است که HTTP Status در بازه 200 باشد.

نمونه پاسخ احتمالی:

{
  "message": "OTP sent successfully"
}


------------------------------------------------------------
POST /auth/register/confirm
------------------------------------------------------------

آدرس کامل:
http://52.16.58.211:8000/auth/register/confirm

نوع درخواست:
POST

احراز هویت:
لازم ندارد.

کاربرد:
تایید OTP و تکمیل ثبت‌نام.

Body ساده:

{
  "email": "test@example.com",
  "otp": "123456"
}

Body کامل‌تر که اپلیکیشن هم پشتیبانی می‌کند:

{
  "email": "test@example.com",
  "otp": "123456",
  "code": "123456",
  "passcode": "123456",
  "otp_code": "123456",
  "verification_code": "123456",
  "full_name": "Test User",
  "display_name": "Test User",
  "name": "Test User",
  "username": "test_user",
  "password": "StrongPass1",
  "avatar_url": "",
  "profile_image_url": "",
  "bio": ""
}

نوع پاسخ:
JSON Object شامل token و user

نمونه پاسخ:

{
  "access_token": "...",
  "token_type": "bearer",
  "user": {
    "id": 1,
    "full_name": "Test User",
    "username": "test_user",
    "email": "test@example.com",
    "role": "user",
    "created_at": "2026-08-16T20:32:59.209251"
  }
}


------------------------------------------------------------
POST /auth/login
------------------------------------------------------------

آدرس کامل:
http://52.16.58.211:8000/auth/login

نوع درخواست:
POST

احراز هویت:
لازم ندارد.

کاربرد:
ورود کاربر با ایمیل و رمز عبور.

Body اصلی اپ:

{
  "email": "test@example.com",
  "password": "StrongPass1"
}

بعضی نسخه‌های تستی بک‌اند این کلیدها را هم پشتیبانی می‌کنند:

{
  "email_or_username": "test@example.com",
  "password": "StrongPass1"
}

{
  "username_or_email": "test@example.com",
  "password": "StrongPass1"
}

{
  "identifier": "test@example.com",
  "password": "StrongPass1"
}

نوع پاسخ:
JSON Object شامل access_token و user

نمونه پاسخ:

{
  "access_token": "...",
  "token_type": "bearer",
  "user": {
    "id": 1,
    "full_name": "Test User",
    "username": "test_user",
    "email": "test@example.com",
    "role": "admin",
    "created_at": "2026-08-16T20:32:59.209251"
  }
}

نکته:
اپلیکیشن این token را ذخیره می‌کند و برای درخواست‌های خصوصی با Header زیر می‌فرستد:

Authorization: Bearer ACCESS_TOKEN


------------------------------------------------------------
POST /auth/password-reset/request
------------------------------------------------------------

آدرس کامل:
http://52.16.58.211:8000/auth/password-reset/request

نوع درخواست:
POST

احراز هویت:
لازم ندارد.

کاربرد:
ارسال OTP برای بازیابی رمز عبور.

Body:

{
  "email": "test@example.com"
}

نوع پاسخ:
JSON Object

نمونه پاسخ احتمالی:

{
  "message": "OTP sent successfully"
}


------------------------------------------------------------
POST /auth/password-reset/confirm
------------------------------------------------------------

آدرس کامل:
http://52.16.58.211:8000/auth/password-reset/confirm

نوع درخواست:
POST

احراز هویت:
لازم ندارد.

کاربرد:
تایید OTP بازیابی رمز و ذخیره رمز جدید.

Body:

{
  "email": "test@example.com",
  "otp": "123456",
  "new_password": "NewStrong2",
  "newPassword": "NewStrong2"
}

نوع پاسخ:
JSON Object

نمونه پاسخ احتمالی:

{
  "message": "password reset successfully"
}


============================================================
5. APIهای پروفایل کاربر
============================================================

------------------------------------------------------------
GET /users/me
------------------------------------------------------------

آدرس کامل:
http://52.16.58.211:8000/users/me

نوع درخواست:
GET

احراز هویت:
لازم دارد.

Header:

Authorization: Bearer ACCESS_TOKEN

کاربرد:
دریافت اطلاعات کاربر فعلی.

نوع پاسخ:
JSON Object

نمونه پاسخ:

{
  "user": {
    "id": 1,
    "full_name": "Test User",
    "username": "test_user",
    "email": "test@example.com",
    "avatar_url": "",
    "bio": "profile check",
    "role": "admin",
    "created_at": "2026-08-16T20:32:59.209251"
  }
}


------------------------------------------------------------
PATCH /users/me
------------------------------------------------------------

آدرس کامل:
http://52.16.58.211:8000/users/me

نوع درخواست:
PATCH

احراز هویت:
لازم دارد.

کاربرد:
ویرایش اطلاعات پروفایل کاربر فعلی.

Body نمونه:

{
  "full_name": "New Name",
  "username": "new_username",
  "avatar_url": "https://...",
  "bio": "متن درباره من"
}

نوع پاسخ:
JSON Object

نمونه پاسخ:

{
  "user": {
    "id": 1,
    "full_name": "New Name",
    "username": "new_username",
    "email": "test@example.com",
    "role": "user"
  }
}


============================================================
6. APIهای جست‌وجو و اطلاعات فیلم/سریال
============================================================

این APIها معمولا عمومی هستند و برای سرچ، صفحه اصلی، جزئیات فیلم و قسمت‌های سریال استفاده می‌شوند. سرور در پشت صحنه از IMDb و گاهی OMDb استفاده می‌کند و نتیجه را به شکل ساده‌شده به اپ می‌دهد.


------------------------------------------------------------
GET /titles/search
------------------------------------------------------------

آدرس کامل:
http://52.16.58.211:8000/titles/search

نوع درخواست:
GET

احراز هویت:
لازم ندارد.

کاربرد:
جست‌وجوی عادی با اسم فیلم/سریال یا IMDb ID.

Query Parameters:

- q: متن جست‌وجو یا IMDb ID
- type: یکی از all، movie، series
- first: تعداد نتیجه، بین 1 تا 50

نمونه:

GET /titles/search?q=Attack%20on%20Titan&type=all&first=20

نوع پاسخ:
JSON Object شامل items

نمونه پاسخ:

{
  "items": [
    {
      "id": "tt2560140",
      "title": "Attack on Titan",
      "type": "series",
      "year": 2013,
      "endYear": 2023,
      "imageUrl": "https://...",
      "rank": null,
      "subtitle": "...",
      "rating": 9.1,
      "voteCount": 600000,
      "canHaveEpisodes": true
    }
  ]
}

نکته:
اگر q شامل IMDb ID مثل tt2560140 باشد، سرور آن را تشخیص می‌دهد و مستقیم سراغ اطلاعات همان عنوان می‌رود.


------------------------------------------------------------
GET /titles/search-by-id/{title_id}
------------------------------------------------------------

آدرس کامل نمونه:
http://52.16.58.211:8000/titles/search-by-id/tt2560140

نوع درخواست:
GET

احراز هویت:
لازم ندارد.

کاربرد:
جست‌وجوی مستقیم با IMDb ID.

Path Parameter:

- title_id: شناسه IMDb مثل tt2560140

نوع پاسخ:
JSON Object شامل items

نمونه پاسخ:

{
  "items": [
    {
      "id": "tt2560140",
      "title": "Attack on Titan",
      "type": "series",
      "year": 2013,
      "imageUrl": "https://...",
      "rating": 9.1,
      "canHaveEpisodes": true
    }
  ]
}


------------------------------------------------------------
GET /titles/advanced-search
------------------------------------------------------------

آدرس کامل:
http://52.16.58.211:8000/titles/advanced-search

نوع درخواست:
GET

احراز هویت:
لازم ندارد.

کاربرد:
جست‌وجوی پیشرفته و همچنین گرفتن کالکشن‌هایی مثل محبوب‌ها و برترین‌ها.

Query Parameters:

- q: متن جست‌وجو، اختیاری
- type: all، movie، series
- first: تعداد نتیجه، بین 1 تا 50
- sort_by: مقدار پیش‌فرض POPULARITY
- sort_order: مقدار پیش‌فرض ASC
- release_date_start: تاریخ شروع، مثل 2026-01-01
- release_date_end: تاریخ پایان، مثل 2026-12-31
- minimum_rating: حداقل امتیاز، بین 0 تا 10
- minimum_votes: حداقل تعداد رای
- top_rated_movies_only: true یا false

نمونه:

GET /titles/advanced-search?q=Inception&type=movie&first=10&sort_by=POPULARITY&sort_order=ASC

نوع پاسخ:
JSON Object شامل items

نمونه پاسخ:

{
  "items": [
    {
      "id": "tt1375666",
      "title": "Inception",
      "type": "movie",
      "year": 2010,
      "imageUrl": "https://...",
      "rating": 8.8,
      "voteCount": 2600000,
      "canHaveEpisodes": false
    }
  ]
}


------------------------------------------------------------
GET /titles/trending
------------------------------------------------------------

آدرس کامل:
http://52.16.58.211:8000/titles/trending

نوع درخواست:
GET

احراز هویت:
لازم ندارد.

کاربرد:
نمایش بخش ترندها در صفحه اصلی.

Query Parameters:

- first: تعداد نتیجه، پیش‌فرض 12، بین 1 تا 50

نمونه:

GET /titles/trending?first=12

نوع پاسخ:
JSON Object شامل items

نکته:
سرور اگر تصویر بعضی ترندها ناقص باشد، تلاش می‌کند با metadata از IMDb تصویر را کامل کند.


------------------------------------------------------------
GET /titles/popular/movies
------------------------------------------------------------

آدرس کامل:
http://52.16.58.211:8000/titles/popular/movies

نوع درخواست:
GET

احراز هویت:
لازم ندارد.

کاربرد:
دریافت فیلم‌های محبوب برای صفحه اصلی و پیشنهاد ساده.

Query Parameters:

- first: تعداد نتیجه، پیش‌فرض 12

نوع پاسخ:
JSON Object شامل items از نوع TitleSummary


------------------------------------------------------------
GET /titles/popular/series
------------------------------------------------------------

آدرس کامل:
http://52.16.58.211:8000/titles/popular/series

نوع درخواست:
GET

احراز هویت:
لازم ندارد.

کاربرد:
دریافت سریال‌های محبوب برای صفحه اصلی و پیشنهاد ساده.

Query Parameters:

- first: تعداد نتیجه، پیش‌فرض 12

نوع پاسخ:
JSON Object شامل items از نوع TitleSummary


------------------------------------------------------------
GET /titles/new
------------------------------------------------------------

آدرس کامل:
http://52.16.58.211:8000/titles/new

نوع درخواست:
GET

احراز هویت:
لازم ندارد.

کاربرد:
دریافت آثار جدید سال جاری.

Query Parameters:

- first: تعداد نتیجه، پیش‌فرض 12

نوع پاسخ:
JSON Object شامل items از نوع TitleSummary


------------------------------------------------------------
GET /titles/top-rated
------------------------------------------------------------

آدرس کامل:
http://52.16.58.211:8000/titles/top-rated

نوع درخواست:
GET

احراز هویت:
لازم ندارد.

کاربرد:
دریافت فیلم‌های امتیازبالا.

Query Parameters:

- first: تعداد نتیجه، پیش‌فرض 12

نوع پاسخ:
JSON Object شامل items از نوع TitleSummary


------------------------------------------------------------
GET /titles/metadata
------------------------------------------------------------

آدرس کامل:
http://52.16.58.211:8000/titles/metadata

نوع درخواست:
GET

احراز هویت:
لازم ندارد.

کاربرد:
گرفتن metadata چند عنوان با IMDb ID.

Query Parameters:

- ids: شناسه‌ها با کاما جدا می‌شوند

نمونه:

GET /titles/metadata?ids=tt2560140,tt1375666

نوع پاسخ:
JSON Object شامل items از نوع TitleDetails

نمونه پاسخ:

{
  "items": [
    {
      "id": "tt2560140",
      "title": "Attack on Titan",
      "originalTitle": "...",
      "type": "series",
      "canHaveEpisodes": true,
      "imageUrl": "https://...",
      "releaseYear": 2013,
      "endYear": 2023,
      "rating": 9.1,
      "voteCount": 600000,
      "runtimeSeconds": 1440,
      "runtimeMinutes": 24,
      "certificate": "TV-MA",
      "genres": ["Animation", "Action"],
      "plot": "...",
      "releaseDate": "...",
      "productionStatus": "...",
      "latestTrailerId": null
    }
  ]
}


------------------------------------------------------------
GET /titles/{title_id}
------------------------------------------------------------

آدرس کامل نمونه:
http://52.16.58.211:8000/titles/tt2560140

نوع درخواست:
GET

احراز هویت:
لازم ندارد.

کاربرد:
دریافت اطلاعات کامل صفحه جزئیات فیلم یا سریال.

Path Parameter:

- title_id: شناسه IMDb مثل tt2560140

نوع پاسخ:
JSON Object شامل summary، imdbDetails، omdbDetails، seriesOverview و errors

نمونه پاسخ:

{
  "summary": {
    "id": "tt2560140",
    "title": "Attack on Titan",
    "type": "series",
    "year": 2013,
    "imageUrl": "https://...",
    "rating": 9.1,
    "canHaveEpisodes": true
  },
  "imdbDetails": {
    "id": "tt2560140",
    "title": "Attack on Titan",
    "genres": ["Animation", "Action"],
    "plot": "..."
  },
  "omdbDetails": {
    "imdbId": "tt2560140",
    "title": "Attack on Titan",
    "year": "2013-2023",
    "type": "series",
    "poster": "https://...",
    "imdbRating": 9.1,
    "totalSeasons": 4
  },
  "seriesOverview": {
    "titleId": "tt2560140",
    "isOngoing": false,
    "totalEpisodes": 89
  },
  "errors": []
}


------------------------------------------------------------
GET /titles/{title_id}/overview
------------------------------------------------------------

آدرس کامل نمونه:
http://52.16.58.211:8000/titles/tt2560140/overview

نوع درخواست:
GET

احراز هویت:
لازم ندارد.

کاربرد:
دریافت خلاصه وضعیت سریال، تعداد قسمت‌ها، قسمت آخر و قسمت بعدی.

نوع پاسخ:
JSON Object

نمونه پاسخ:

{
  "titleId": "tt2560140",
  "isOngoing": false,
  "totalEpisodes": 89,
  "latestSeasonNumber": 4,
  "latestEpisodeNumber": 30,
  "latestReleaseDate": "2023-11-05",
  "nextSeasonNumber": null,
  "nextEpisodeNumber": null,
  "nextReleaseDate": null
}


------------------------------------------------------------
GET /titles/{title_id}/seasons/{season_number}/episodes
------------------------------------------------------------

آدرس کامل نمونه:
http://52.16.58.211:8000/titles/tt2560140/seasons/1/episodes

نوع درخواست:
GET

احراز هویت:
لازم ندارد.

کاربرد:
دریافت قسمت‌های یک فصل سریال.

Path Parameters:

- title_id: شناسه IMDb سریال
- season_number: شماره فصل، از 1 به بالا

نوع پاسخ:
JSON Object شامل items و source

source می‌تواند این مقدارها را داشته باشد:

- imdb
- omdb
- none

نمونه پاسخ:

{
  "items": [
    {
      "id": "tt0959621",
      "title": "To You, in 2000 Years",
      "seasonNumber": 1,
      "episodeNumber": 1,
      "releaseDate": "2013-04-07",
      "plot": "...",
      "imageUrl": "https://...",
      "rating": 8.8,
      "voteCount": 20000
    }
  ],
  "source": "imdb"
}


============================================================
7. APIهای لیست تماشا
============================================================

همه APIهای این بخش نیاز به ورود دارند.

Header لازم:

Authorization: Bearer ACCESS_TOKEN


------------------------------------------------------------
GET /watchlist
------------------------------------------------------------

آدرس کامل:
http://52.16.58.211:8000/watchlist

نوع درخواست:
GET

احراز هویت:
لازم دارد.

کاربرد:
دریافت لیست ذخیره‌شده کاربر.

نوع پاسخ:
JSON Object شامل items

نمونه پاسخ:

{
  "items": [
    {
      "title_id": "tt2560140",
      "title": "Attack on Titan",
      "year": "2013",
      "poster_url": "https://...",
      "media_type": "series",
      "status": "watching",
      "favorite": true,
      "watched_episode_ids": ["tt0959621"],
      "created_at": "2026-08-17T00:00:00Z",
      "updated_at": "2026-08-17T00:10:00Z"
    }
  ]
}


------------------------------------------------------------
POST /watchlist
------------------------------------------------------------

آدرس کامل:
http://52.16.58.211:8000/watchlist

نوع درخواست:
POST

احراز هویت:
لازم دارد.

کاربرد:
افزودن یا ذخیره یک فیلم/سریال در لیست کاربر.

Body:

{
  "title_id": "tt2560140",
  "title": "Attack on Titan",
  "year": "2013",
  "poster_url": "https://...",
  "media_type": "series",
  "type": "series",
  "status": "planned",
  "favorite": false,
  "subtitle": "...",
  "rating": 9.1,
  "vote_count": 600000,
  "can_have_episodes": true
}

نوع پاسخ:
JSON Object

نمونه پاسخ احتمالی:

{
  "message": "watchlist item saved",
  "item": {
    "title_id": "tt2560140",
    "status": "planned",
    "favorite": false
  }
}


------------------------------------------------------------
PATCH /watchlist/{title_id}
------------------------------------------------------------

آدرس کامل نمونه:
http://52.16.58.211:8000/watchlist/tt2560140

نوع درخواست:
PATCH

احراز هویت:
لازم دارد.

کاربرد:
تغییر وضعیت تماشا یا favorite یک عنوان.

Body:

{
  "status": "watching",
  "favorite": true
}

نوع پاسخ:
JSON Object

نمونه پاسخ احتمالی:

{
  "message": "watchlist item updated",
  "item": {
    "title_id": "tt2560140",
    "status": "watching",
    "favorite": true
  }
}


------------------------------------------------------------
DELETE /watchlist/{title_id}
------------------------------------------------------------

آدرس کامل نمونه:
http://52.16.58.211:8000/watchlist/tt2560140

نوع درخواست:
DELETE

احراز هویت:
لازم دارد.

کاربرد:
حذف یک عنوان از لیست تماشای کاربر.

نوع پاسخ:
JSON Object یا بدون بدنه

نمونه پاسخ احتمالی:

{
  "deleted_title_id": "tt2560140"
}


============================================================
8. APIهای پیشرفت تماشای قسمت‌ها
============================================================

همه APIهای این بخش نیاز به ورود دارند.


------------------------------------------------------------
GET /progress
------------------------------------------------------------

آدرس کامل:
http://52.16.58.211:8000/progress

نوع درخواست:
GET

احراز هویت:
لازم دارد.

کاربرد:
دریافت پیشرفت تماشای همه سریال‌های کاربر.

نوع پاسخ:
JSON Object شامل items

نمونه پاسخ:

{
  "items": [
    {
      "title_id": "tt2560140",
      "watched_episode_ids": ["tt0959621", "tt0959622"]
    }
  ]
}


------------------------------------------------------------
GET /progress/{title_id}
------------------------------------------------------------

آدرس کامل نمونه:
http://52.16.58.211:8000/progress/tt2560140

نوع درخواست:
GET

احراز هویت:
لازم دارد.

کاربرد:
دریافت قسمت‌های دیده‌شده برای یک سریال خاص.

نوع پاسخ:
JSON Object

نمونه پاسخ:

{
  "title_id": "tt2560140",
  "watched_episode_ids": ["tt0959621"]
}


------------------------------------------------------------
POST /progress/{title_id}/episodes/{episode_id}
------------------------------------------------------------

آدرس کامل نمونه:
http://52.16.58.211:8000/progress/tt2560140/episodes/tt0959621

نوع درخواست:
POST

احراز هویت:
لازم دارد.

کاربرد:
ثبت اینکه یک قسمت دیده شده است.

Body نمونه:

{
  "title": "Attack on Titan",
  "year": "2013",
  "poster_url": "https://...",
  "media_type": "series"
}

نوع پاسخ:
JSON Object

نمونه پاسخ:

{
  "title_id": "tt2560140",
  "watched_episode_ids": ["tt0959621"]
}


------------------------------------------------------------
DELETE /progress/{title_id}/episodes/{episode_id}
------------------------------------------------------------

آدرس کامل نمونه:
http://52.16.58.211:8000/progress/tt2560140/episodes/tt0959621

نوع درخواست:
DELETE

احراز هویت:
لازم دارد.

کاربرد:
حذف وضعیت دیده‌شده یک قسمت.

نوع پاسخ:
JSON Object یا بدون بدنه

نمونه پاسخ احتمالی:

{
  "title_id": "tt2560140",
  "watched_episode_ids": []
}


============================================================
9. APIهای امتیاز و نظر کاربران
============================================================

در این بخش، امتیاز و نظر کاربران خودمان ذخیره می‌شود. این‌ها با امتیاز رسمی IMDb فرق دارند. اپلیکیشن می‌تواند در کنار امتیاز رسمی IMDb، میانگین امتیاز کاربران محلی/سروری خودمان را هم نشان بدهد.


------------------------------------------------------------
POST /titles/{title_id}/rating
------------------------------------------------------------

آدرس کامل نمونه:
http://52.16.58.211:8000/titles/tt2560140/rating

نوع درخواست:
POST

احراز هویت:
لازم دارد.

کاربرد:
ثبت یا ویرایش امتیاز کاربر برای یک عنوان.

Body:

{
  "rating": 9,
  "title": "Attack on Titan",
  "year": "2013",
  "poster_url": "https://...",
  "media_type": "series"
}

نوع پاسخ:
JSON Object

نمونه پاسخ احتمالی:

{
  "message": "rating saved",
  "my_rating": {
    "title_id": "tt2560140",
    "rating": 9
  },
  "rating_summary": {
    "title_id": "tt2560140",
    "rating_count": 1,
    "average_rating": 9.0
  }
}


------------------------------------------------------------
DELETE /titles/{title_id}/rating
------------------------------------------------------------

آدرس کامل نمونه:
http://52.16.58.211:8000/titles/tt2560140/rating

نوع درخواست:
DELETE

احراز هویت:
لازم دارد.

کاربرد:
حذف امتیاز کاربر فعلی برای یک عنوان.

نوع پاسخ:
JSON Object یا بدون بدنه

نمونه پاسخ احتمالی:

{
  "deleted_title_id": "tt2560140",
  "rating_summary": {
    "title_id": "tt2560140",
    "rating_count": 0,
    "average_rating": null
  }
}


------------------------------------------------------------
POST /titles/{title_id}/review
------------------------------------------------------------

آدرس کامل نمونه:
http://52.16.58.211:8000/titles/tt2560140/review

نوع درخواست:
POST

احراز هویت:
لازم دارد.

کاربرد:
ثبت یا ویرایش نظر کاربر برای یک عنوان.

Body:

{
  "text": "متن نظر",
  "contains_spoiler": false,
  "title": "Attack on Titan",
  "year": "2013",
  "poster_url": "https://...",
  "media_type": "series"
}

نوع پاسخ:
JSON Object

نمونه پاسخ واقعی:

{
  "message": "review saved",
  "my_review": {
    "id": 6,
    "title_id": "tt2560140",
    "text": "متن نظر",
    "contains_spoiler": false,
    "created_at": "2026-08-17T00:09:08Z",
    "updated_at": "2026-08-17T00:27:29Z"
  },
  "reviews": [
    {
      "id": 6,
      "user_id": 1,
      "username": "test_user",
      "full_name": "Test User",
      "title_id": "tt2560140",
      "title": "Attack on Titan",
      "year": "2013",
      "poster_url": "https://...",
      "media_type": "series",
      "text": "متن نظر",
      "contains_spoiler": false,
      "created_at": "2026-08-17T00:09:08Z",
      "updated_at": "2026-08-17T00:27:29Z",
      "is_mine": true
    }
  ],
  "rating_summary": {
    "title_id": "tt2560140",
    "rating_count": 0,
    "average_rating": null
  }
}


------------------------------------------------------------
DELETE /titles/{title_id}/review
------------------------------------------------------------

آدرس کامل نمونه:
http://52.16.58.211:8000/titles/tt2560140/review

نوع درخواست:
DELETE

احراز هویت:
لازم دارد.

کاربرد:
حذف نظر کاربر فعلی برای یک عنوان.

نوع پاسخ:
JSON Object یا بدون بدنه

نمونه پاسخ احتمالی:

{
  "deleted_title_id": "tt2560140"
}


------------------------------------------------------------
GET /titles/{title_id}/reviews
------------------------------------------------------------

آدرس کامل نمونه:
http://52.16.58.211:8000/titles/tt2560140/reviews

نوع درخواست:
GET

احراز هویت:
در تست فعلی با token استفاده شده است.

کاربرد:
دریافت نظرهای یک عنوان.

نوع پاسخ:
JSON Object

نمونه پاسخ:

{
  "title_id": "tt2560140",
  "reviews": [
    {
      "id": 6,
      "user_id": 1,
      "username": "test_user",
      "full_name": "Test User",
      "text": "متن نظر",
      "contains_spoiler": false,
      "created_at": "2026-08-17T00:09:08Z"
    }
  ],
  "rating_summary": {
    "title_id": "tt2560140",
    "rating_count": 1,
    "average_rating": 9.0
  }
}


------------------------------------------------------------
GET /titles/{title_id}/feedback
------------------------------------------------------------

آدرس کامل نمونه:
http://52.16.58.211:8000/titles/tt2560140/feedback

نوع درخواست:
GET

احراز هویت:
در اپلیکیشن با token استفاده می‌شود.

کاربرد:
دریافت همزمان نظرهای کاربران و میانگین امتیاز کاربران خودمان برای یک عنوان.

نوع پاسخ:
JSON Object

نمونه پاسخ:

{
  "reviews": [
    {
      "id": 6,
      "user_id": 1,
      "username": "test_user",
      "full_name": "Test User",
      "title_id": "tt2560140",
      "title": "Attack on Titan",
      "text": "متن نظر",
      "contains_spoiler": false,
      "created_at": "2026-08-17T00:09:08Z"
    }
  ],
  "rating_summary": {
    "title_id": "tt2560140",
    "rating_count": 3,
    "average_rating": 8.7
  }
}


------------------------------------------------------------
GET /titles/me/ratings
------------------------------------------------------------

آدرس کامل:
http://52.16.58.211:8000/titles/me/ratings

نوع درخواست:
GET

احراز هویت:
لازم دارد.

کاربرد:
دریافت تمام امتیازهای کاربر فعلی.

نوع پاسخ:
JSON Object شامل items

نمونه پاسخ:

{
  "items": [
    {
      "title_id": "tt2560140",
      "rating": 9,
      "title": "Attack on Titan",
      "year": "2013",
      "poster_url": "https://...",
      "media_type": "series"
    }
  ]
}


------------------------------------------------------------
GET /titles/me/reviews
------------------------------------------------------------

آدرس کامل:
http://52.16.58.211:8000/titles/me/reviews

نوع درخواست:
GET

احراز هویت:
لازم دارد.

کاربرد:
دریافت تمام نظرهای کاربر فعلی.

نوع پاسخ:
JSON Object شامل items

نمونه پاسخ:

{
  "items": [
    {
      "title_id": "tt2560140",
      "text": "متن نظر",
      "contains_spoiler": false,
      "created_at": "2026-08-17T00:09:08Z"
    }
  ]
}


============================================================
10. APIهای ادمین
============================================================

همه APIهای این بخش نیاز به token کاربر admin دارند.

Header لازم:

Authorization: Bearer ADMIN_ACCESS_TOKEN

اگر کاربر عادی به این APIها درخواست بزند، باید 403 بگیرد.
اگر token ارسال نشود، باید 401 بگیرد.


------------------------------------------------------------
GET /admin/users
------------------------------------------------------------

آدرس کامل:
http://52.16.58.211:8000/admin/users

نوع درخواست:
GET

احراز هویت:
فقط مدیر.

کاربرد:
نمایش لیست همه کاربران برای مدیر.

Query Parameters:

- q: فیلتر اختیاری بر اساس نام، نام کاربری یا ایمیل
- limit: تعداد نتیجه، پیش‌فرض 50
- offset: شروع صفحه‌بندی، پیش‌فرض 0

نمونه:

GET /admin/users?limit=50&offset=0

نوع پاسخ:
JSON Object شامل items، total، limit و offset

نمونه پاسخ واقعی:

{
  "items": [
    {
      "id": 1,
      "username": "test_user",
      "email": "test@example.com",
      "full_name": "Test User",
      "display_name": "Test User",
      "avatar_url": null,
      "profile_image_url": "",
      "bio": "profile check",
      "role": "admin",
      "created_at": "2026-08-16T20:32:59.209251",
      "updated_at": null
    }
  ],
  "total": 1,
  "limit": 50,
  "offset": 0
}


------------------------------------------------------------
PATCH /admin/users/{user_id}/role
------------------------------------------------------------

آدرس کامل نمونه:
http://52.16.58.211:8000/admin/users/2/role

نوع درخواست:
PATCH

احراز هویت:
فقط مدیر.

کاربرد:
تغییر نقش یک کاربر به user یا admin.

Body:

{
  "role": "admin"
}

یا:

{
  "role": "user"
}

نوع پاسخ:
JSON Object

نمونه پاسخ:

{
  "user": {
    "id": 2,
    "username": "normal_user",
    "email": "user@example.com",
    "role": "admin"
  }
}

خطاهای مهم:

- role نامعتبر مثل owner باید 400 بدهد.
- user_id ناموجود باید 404 بدهد.


------------------------------------------------------------
DELETE /admin/users/{user_id}
------------------------------------------------------------

آدرس کامل نمونه:
http://52.16.58.211:8000/admin/users/2

نوع درخواست:
DELETE

احراز هویت:
فقط مدیر.

کاربرد:
حذف یک کاربر توسط مدیر.

نوع پاسخ:
JSON Object یا بدون بدنه

نمونه پاسخ احتمالی:

{
  "deleted_user_id": "2"
}

نکته:
مدیر نباید بتواند اکانت خودش را حذف کند. در این حالت سرور 400 می‌دهد.


------------------------------------------------------------
GET /admin/reviews
------------------------------------------------------------

آدرس کامل:
http://52.16.58.211:8000/admin/reviews

نوع درخواست:
GET

احراز هویت:
فقط مدیر.

کاربرد:
نمایش همه نظرهای کاربران برای بررسی محتوای نامناسب.

Query Parameters:

- title_id: فیلتر اختیاری بر اساس IMDb ID
- q: فیلتر اختیاری متنی
- limit: تعداد نتیجه، پیش‌فرض 50
- offset: شروع صفحه‌بندی، پیش‌فرض 0

نمونه:

GET /admin/reviews?title_id=tt2560140&limit=50&offset=0

نوع پاسخ:
JSON Object شامل items، total، limit و offset

نمونه پاسخ واقعی:

{
  "items": [
    {
      "id": 6,
      "title_id": "tt2560140",
      "title": "Attack on Titan",
      "user_id": 1,
      "username": "test_user",
      "full_name": "Test User",
      "email": "test@example.com",
      "text": "متن نظر",
      "contains_spoiler": false,
      "created_at": "2026-08-17T00:09:08Z",
      "updated_at": "2026-08-17T00:27:29Z"
    }
  ],
  "total": 1,
  "limit": 50,
  "offset": 0
}


------------------------------------------------------------
DELETE /admin/reviews/{review_id}
------------------------------------------------------------

آدرس کامل نمونه:
http://52.16.58.211:8000/admin/reviews/6

نوع درخواست:
DELETE

احراز هویت:
فقط مدیر.

کاربرد:
حذف نظر نامناسب توسط مدیر.

نوع پاسخ:
JSON Object یا بدون بدنه

نمونه پاسخ واقعی:

{
  "deleted_review_id": "6"
}

خطاهای مهم:

- review_id ناموجود باید 404 بدهد.


------------------------------------------------------------
GET /admin/stats
------------------------------------------------------------

آدرس کامل:
http://52.16.58.211:8000/admin/stats

نوع درخواست:
GET

احراز هویت:
فقط مدیر.

کاربرد:
دریافت آمار کلی سرور برای مدیر.

نوع پاسخ:
JSON Object

نمونه پاسخ واقعی:

{
  "users": 1,
  "admins": 1,
  "watchlist_items": 0,
  "ratings": 1,
  "reviews": 2,
  "progress_items": 0,
  "generated_at": "2026-08-17T00:27:29.864266Z"
}


============================================================
11. وضعیت استفاده در اپلیکیشن Flutter
============================================================

فایل اصلی اتصال به بک‌اند:

lib/src/api/backend_api_client.dart

در این فایل، درخواست‌ها با کلاس BackendApiClient ساخته می‌شوند.

درخواست‌های عمومی:

- GET /health
- GET /titles/search
- GET /titles/search-by-id/{title_id}
- GET /titles/advanced-search
- GET /titles/trending
- GET /titles/popular/movies
- GET /titles/popular/series
- GET /titles/new
- GET /titles/top-rated
- GET /titles/metadata
- GET /titles/{title_id}
- GET /titles/{title_id}/overview
- GET /titles/{title_id}/seasons/{season_number}/episodes

درخواست‌های کاربر واردشده:

- GET /users/me
- GET /watchlist
- POST /watchlist
- PATCH /watchlist/{title_id}
- DELETE /watchlist/{title_id}
- GET /progress
- POST /progress/{title_id}/episodes/{episode_id}
- DELETE /progress/{title_id}/episodes/{episode_id}
- POST /titles/{title_id}/rating
- DELETE /titles/{title_id}/rating
- POST /titles/{title_id}/review
- DELETE /titles/{title_id}/review
- GET /titles/me/ratings
- GET /titles/me/reviews
- GET /titles/{title_id}/feedback

درخواست‌های مدیر:

- GET /admin/users
- GET /admin/reviews
- DELETE /admin/reviews/{review_id}

درخواست‌های ادمین که روی سرور وجود دارد ولی UI فعلی اپ هنوز کامل برایشان ساخته نشده:

- PATCH /admin/users/{user_id}/role
- DELETE /admin/users/{user_id}
- GET /admin/stats


============================================================
12. کش سمت سرور
============================================================

در سرور یک جدول یا فایل کش برای APIهای خارجی وجود دارد.

هدف:

- کمتر شدن درخواست مستقیم به IMDb و OMDb
- سریع‌تر شدن پاسخ‌ها
- کم شدن احتمال محدود شدن درخواست‌ها

رفتار فعلی:

- پاسخ‌های بیرونی حدود 10 دقیقه کش می‌شوند.
- کلید کش معمولا از method، url و query ساخته می‌شود.
- اگر کش معتبر باشد، سرور از همان پاسخ ذخیره‌شده استفاده می‌کند.
- اگر کش منقضی شده باشد، سرور دوباره به API خارجی درخواست می‌زند و کش را تازه می‌کند.

این کش برای کلاینت شفاف است؛ یعنی Flutter لازم نیست کاری اضافه انجام بدهد.


============================================================
13. فایل‌ها و ابزارهای تست API
============================================================

برای تست APIهای عمومی کاربر:

api_server_test.py

این تست مواردی مثل health، login، users/me، watchlist، rating، review و progress را بررسی می‌کند.

برای تست APIهای ادمین:

api_admin_test.py

این تست مواردی مثل protected بودن مسیرهای admin، ورود ادمین، دیدن کاربران، دیدن آمار، لیست نظرات و حذف نظر را بررسی می‌کند.

برای تست APIهای عنوان‌ها و مقایسه با IMDb/OMDb:

api_title_parity_test.py

این تست بررسی می‌کند که پاسخ‌های سرور در مسیرهای /titles با داده‌های IMDb/OMDb هماهنگ باشند.

مستندات زنده خود سرور:

http://52.16.58.211:8000/docs


============================================================
14. جمع‌بندی خیلی کوتاه
============================================================

اگر بخواهیم خیلی ساده بگوییم:

- /auth برای ثبت‌نام، ورود و بازیابی رمز است.
- /users برای پروفایل کاربر فعلی است.
- /titles برای جست‌وجو، جزئیات، ترندها، محبوب‌ها، قسمت‌های سریال و اطلاعات فیلم/سریال است.
- /watchlist برای لیست ذخیره‌شده کاربر است.
- /progress برای قسمت‌های دیده‌شده سریال است.
- /titles/{id}/rating و /titles/{id}/review برای امتیاز و نظر کاربران خودمان است.
- /admin برای مدیریت کاربران، مدیریت نظرات و آمار سرور است.
- /health برای تست روشن بودن سرور است.

مسیر کلی پروژه پیشرفته:

Flutter فقط با http://52.16.58.211:8000 حرف می‌زند.
سرور خودش با SQLite، IMDb، OMDb و EmailJS کار می‌کند.
