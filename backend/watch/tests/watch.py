from rest_framework.test import APITestCase
from rest_framework import status
from django.urls import reverse
from django.contrib.auth import get_user_model

User = get_user_model()

class IndependentWatchSystemTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username='independent_user',
            email='ind@example.com',
            password='password123'
        )
        self.client.force_authenticate(user=self.user)
        
        self.watchlist_url = reverse('watchlist-list-create')
        self.playlists_url = reverse('playlist-list-create')

    def test_independent_status_and_playlist_workflow(self):
        """تست استقلال وضعیت تماشا از پلی‌لیست و ساخت فهرست‌های سفارشی"""
        
        # ۱. اضافه کردن اثر به بخش وضعیت تماشا (مثلاً فیلم Interstellar با وضعیت 'completed')
        movie_data = {
            'imdb_id': 'tt0816692',
            'title_type': 'movie',
            'title_name': 'Interstellar',
            'status': 'completed'
        }
        res_movie = self.client.post(self.watchlist_url, movie_data)
        self.assertEqual(res_movie.status_code, status.HTTP_201_CREATED)
        user_title_id = res_movie.data['id']

        # ۲. ساخت یک فهرست سفارشی با نام دلخواه (مثلاً "علمی")
        playlist_data = {
            'name': 'علمی',
            'description': 'فیلم‌های فضایی و علمی'
        }
        res_playlist = self.client.post(self.playlists_url, playlist_data)
        self.assertEqual(res_playlist.status_code, status.HTTP_201_CREATED)
        playlist_id = res_playlist.data['id']

        # ۳. اضافه کردن این اثر به فهرست سفارشیِ "علمی"
        item_url = reverse('playlist-item-add', kwargs={'playlist_id': playlist_id})
        item_data = {'user_title': user_title_id}
        res_item = self.client.post(item_url, item_data)
        self.assertEqual(res_item.status_code, status.HTTP_201_CREATED)

        # ۴. بررسی اینکه اثر در لیست پلی‌لیست با وضعیت تماشای خودش ('completed') دیده می‌شود
        res_get_playlist = self.client.get(reverse('playlist-detail', kwargs={'pk': playlist_id}))
        self.assertEqual(res_get_playlist.status_code, status.HTTP_200_OK)
        self.assertEqual(res_get_playlist.data['name'], 'علمی')
        self.assertEqual(res_get_playlist.data['items'][0]['user_title_details']['status'], 'completed')


class DetailedWatchProgressAndStatusTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username='breaking_bad_fan',
            email='bb_fan@example.com',
            password='password123'
        )
        self.client.force_authenticate(user=self.user)
        
        self.watchlist_url = reverse('watchlist-list-create')
        self.detail_url = reverse('watchlist-detail', kwargs={'imdb_id': 'tt0903747'})
        self.toggle_url = reverse('toggle-episode', kwargs={'imdb_id': 'tt0903747'})

    def test_breaking_bad_workflow_and_percentage(self):
        """
        تست جامع: افزودن سریال، تست وضعیت‌های مختلف (قصد دارم تماشا کنم -> رهاشده/حذف)،
        تیک زدن قسمت‌ها (فصل ۱ و ۲ و بخش‌هایی از فصل ۳) و محاسبه دقیق درصد پیشرفت بین ۳۷ و ۳۸ درصد.
        """
        # ۱. تقلب و افزودن سریال Breaking Bad با مجموع ۶۲ قسمت (فرض بر کل قسمت‌ها)
        initial_data = {
            'imdb_id': 'tt0903747',
            'title_type': 'tv',
            'title_name': 'Breaking Bad',
            'total_episodes': 62,
            'status': 'plan_to_watch'
        }
        res_post = self.client.post(self.watchlist_url, initial_data)
        self.assertEqual(res_post.status_code, status.HTTP_201_CREATED)
        self.assertEqual(res_post.data['status'], 'plan_to_watch')

        # ۲. تغییر وضعیت به "رهاشده" (Dropped) یا بررسی قابلیت تغییر وضعیت
        res_patch_dropped = self.client.patch(self.detail_url, {'status': 'dropped'})
        self.assertEqual(res_patch_dropped.status_code, status.HTTP_200_OK)
        self.assertEqual(res_patch_dropped.data['status'], 'dropped')

        # برگرداندن وضعیت به "در حال تماشا" برای ادامه سناریوی تماشا
        self.client.patch(self.detail_url, {'status': 'watching'})

        # ۳. تماشای کامل فصل اول (۷ قسمت)
        for ep in range(1, 8):
            self.client.post(self.toggle_url, {'season_number': 1, 'episode_number': ep})

        # ۴. تماشای کامل فصل دوم (۱۳ قسمت)
        for ep in range(1, 14):
            self.client.post(self.toggle_url, {'season_number': 2, 'episode_number': ep})

        # ۵. تماشای قسمت‌های ۵، ۷ و ۱۰ از فصل سوم (مجموعاً ۳ قسمت دیگر)
        for ep in [5, 7, 10]:
            self.client.post(self.toggle_url, {'season_number': 3, 'episode_number': ep})

        # ۶. دریافت اطلاعات نهایی و بررسی درصد پیشرفت (باید ۲۳ قسمت از ۶۲ قسمت تیک خورده باشد)
        res_final = self.client.get(self.detail_url)
        self.assertEqual(res_final.status_code, status.HTTP_200_OK)
        
        watched_count = res_final.data['watched_count']
        progress = res_final.data['progress_percentage']
        
        # تعداد کل تیک‌ها باید ۲۳ باشد
        self.assertEqual(watched_count, 23)
        
        # درصد پیشرفت (۲۳ تقسیم بر ۶۲ معادل حدود ۳۷.۱ درصد است) باید بین ۳۷ و ۳۸ باشد
        self.assertTrue(
            37.0 <= progress <= 38.0, 
            f"Expected progress between 37% and 38%, but got {progress}%"
        )