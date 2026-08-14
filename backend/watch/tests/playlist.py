from rest_framework.test import APITestCase
from rest_framework import status
from django.urls import reverse
from django.contrib.auth import get_user_model

User = get_user_model()

class PlaylistFeatureTests(APITestCase):
    def setUp(self):
        # ۱. ساخت کاربر و احراز هویت
        self.user = User.objects.create_user(
            username='playlist_tester',
            email='pl_test@example.com',
            password='password123'
        )
        self.client.force_authenticate(user=self.user)
        
        # مسیرها
        self.watchlist_url = reverse('watchlist-list-create')
        self.playlists_url = reverse('playlist-list-create')

    def test_custom_playlist_lifecycle_and_items(self):
        """
        تست چرخه کامل فهرست سفارشی: 
        ساخت فهرست -> اضافه کردن فیلم و سریال -> بررسی لیستِ فهرست‌ها -> بررسی آیتم‌ها -> پاک کردن فهرست
        """
        # پیش‌نیاز: اول باید آثار را در سیستمِ UserTitle بسازیم تا بتوانیم ارجاعشان دهیم
        # الف) اضافه کردن فیلم The Shawshank Redemption
        movie_res = self.client.post(self.watchlist_url, {
            'imdb_id': 'tt0111161',
            'title_type': 'movie',
            'title_name': 'The Shawshank Redemption',
            'status': 'completed'
        })
        movie_title_id = movie_res.data['id']

        # ب) اضافه کردن سریال Breaking Bad
        tv_res = self.client.post(self.watchlist_url, {
            'imdb_id': 'tt0903747',
            'title_type': 'tv',
            'title_name': 'Breaking Bad',
            'total_episodes': 62,
            'status': 'watching'
        })
        tv_title_id = tv_res.data['id']

        # ۲. ساخت یک فهرست سفارشی جدید (مثلاً "اوقات فراغت")
        playlist_data = {
            'name': 'اوقات فراغت',
            'description': 'فیلم و سریال‌های مخصوص آخر هفته'
        }
        res_create = self.client.post(self.playlists_url, playlist_data)
        self.assertEqual(res_create.status_code, status.HTTP_201_CREATED)
        playlist_id = res_create.data['id']

        # ۳. اضافه کردن هر دو اثر به این فهرست سفارشی
        item_add_url = reverse('playlist-item-add', kwargs={'playlist_id': playlist_id})
        
        # اضافه کردن فیلم
        self.client.post(item_add_url, {'user_title': movie_title_id})
        # اضافه کردن سریال
        self.client.post(item_add_url, {'user_title': tv_title_id})

        # ۴. گرفتن لیستِ همه فهرست‌ها و مطمئن شدن از اینکه این فهرست در آن ظاهر شده است
        res_all_playlists = self.client.get(self.playlists_url)
        self.assertEqual(res_all_playlists.status_code, status.HTTP_200_OK)
        
        playlists = res_all_playlists.data
        self.assertEqual(len(playlists), 1)
        self.assertEqual(playlists[0]['id'], playlist_id)
        self.assertEqual(playlists[0]['name'], 'اوقات فراغت')

        # ۵. بررسی دقیقِ آیتم‌های درون این فهرست و اطمینان از اینکه دقیقاً همین دو تا هستند
        items = playlists[0]['items']
        self.assertEqual(len(items), 2)
        
        # استخراج شناسه‌های IMDb از درون آیتم‌ها برای مقایسه دقیق
        item_imdb_ids = [item['user_title_details']['imdb_id'] for item in items]
        self.assertIn('tt0111161', item_imdb_ids)
        self.assertIn('tt0903747', item_imdb_ids)

        # ۶. پاک کردن این فهرست سفارشی
        playlist_detail_url = reverse('playlist-detail', kwargs={'pk': playlist_id})
        res_delete = self.client.delete(playlist_detail_url)
        self.assertEqual(res_delete.status_code, status.HTTP_204_NO_CONTENT)

        # ۷. مطمئن شدن از اینکه فهرست کاملاً پاک شده و لیستِ فهرست‌ها خالی است
        res_verify_delete = self.client.get(self.playlists_url)
        self.assertEqual(res_verify_delete.status_code, status.HTTP_200_OK)
        self.assertEqual(len(res_verify_delete.data), 0)
