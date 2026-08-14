from rest_framework.test import APITestCase
from rest_framework import status
from django.urls import reverse
from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile

User = get_user_model()

class UserRegistrationTests(APITestCase):
    def setUp(self):
        # آدرس API ثبت‌نام
        self.register_url = reverse('register')
        
        # اطلاعات کلاینت اول
        self.client1_data = {
            'username': 'client1',
            'email': 'client1@example.com',
            'password': 'StrongPassword123!',
            'first_name': 'Ali',
            'last_name': 'Rezaei'
        }
        
        # اطلاعات کلاینت دوم (به صورت عمدی ایمیل را تکراری گذاشتیم)
        self.client2_data = {
            'username': 'client2',
            'email': 'client1@example.com',  # <--- ایمیل تکراری کلاینت اول
            'password': 'AnotherPassword456!',
            'first_name': 'Sara',
            'last_name': 'Ahmadi'
        }

    def test_multiple_clients_registration(self):
        """
        تست ثبت‌نام دو کلاینت مختلف و بررسی جلوگیری از ثبت‌نام با ایمیل تکراری
        """
        # ۱. کلاینت اول ثبت‌نام می‌کند (باید موفقیت‌آمیز باشد)
        response1 = self.client.post(self.register_url, self.client1_data)
        self.assertEqual(response1.status_code, status.HTTP_201_CREATED)
        self.assertEqual(User.objects.count(), 1) # الان ۱ کاربر در دیتابیس داریم
        
        # ۲. کلاینت دوم با همان ایمیل کلاینت اول سعی در ثبت‌نام دارد
        response2 = self.client.post(self.register_url, self.client2_data)
        # باید ارور 400 بدهد چون در داکیومنت نوشته "جلوگیری از ثبت ایمیل تکراری"
        self.assertEqual(response2.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('email', response2.data) # متن ارور باید مربوط به فیلد ایمیل باشد
        self.assertEqual(User.objects.count(), 1) # کاربر دوم نباید ساخته شده باشد
        
        # ۳. کلاینت دوم ایمیلش را عوض می‌کند و دوباره درخواست می‌دهد
        self.client2_data['email'] = 'client2@example.com'
        self.client2_data['username'] = 'client2_new' # یوزرنیم هم باید یونیک باشد
        
        response3 = self.client.post(self.register_url, self.client2_data)
        self.assertEqual(response3.status_code, status.HTTP_201_CREATED)
        self.assertEqual(User.objects.count(), 2) # حالا ۲ کاربر مجزا داریم!


class UserProfileAndAuthTests(APITestCase):
    def setUp(self):
        # ساخت یک کاربر تستی
        self.user = User.objects.create_user(
            username='testuser',
            email='test@example.com',
            password='StrongPassword123!'
        )
        self.login_url = reverse('token_obtain_pair') # آدرس لاگین
        self.profile_url = reverse('profile') # آدرس پروفایل
        
        # یک عکس فیک (گیف ۱ پیکسلی) در حافظه موقت برای تست آپلود
        self.dummy_image = SimpleUploadedFile(
            name='test_avatar.gif',
            content=b'\x47\x49\x46\x38\x39\x61\x01\x00\x01\x00\x00\xff\x00\x2c\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x00\x3b',
            content_type='image/gif'
        )

    def test_user_login_and_get_token(self):
        """تست ورود کاربر با ایمیل و رمز عبور"""
        response = self.client.post(self.login_url, {
            'email': 'test@example.com',
            'password': 'StrongPassword123!'
        })
        
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('access', response.data)
        self.assertIn('refresh', response.data)

    def test_view_and_update_profile(self):
        """تست مشاهده و ویرایش پروفایل به همراه فیلدهای پویای جدید"""
        self.client.force_authenticate(user=self.user)
        
        # ۱. مشاهده پروفایل و بررسی فیلدهای پویای جدید (آمار صفر و لیست خالی علاقه‌مندی‌ها)
        get_response = self.client.get(self.profile_url)
        self.assertEqual(get_response.status_code, status.HTTP_200_OK)
        self.assertEqual(get_response.data['email'], 'test@example.com')
        self.assertEqual(get_response.data['watched_movies_count'], 0)
        self.assertEqual(get_response.data['watched_shows_count'], 0)
        self.assertEqual(get_response.data['favorite_items'], [])
        
        # ۲. ویرایش پروفایل (آپلود عکس و افزودن بیو)
        update_data = {
            'bio': 'این یک توضیح کوتاه درباره من است.',
            'profile_picture': self.dummy_image
        }
        patch_response = self.client.patch(self.profile_url, update_data, format='multipart')
        
        self.assertEqual(patch_response.status_code, status.HTTP_200_OK)
        self.assertEqual(patch_response.data['bio'], update_data['bio'])
        self.assertIsNotNone(patch_response.data['profile_picture'])
        self.assertTrue(patch_response.data['profile_picture'].startswith('http'))


class UserProfileStatsAndFavoritesTests(APITestCase):
    def setUp(self):
        # ساخت کاربر و احراز هویت
        self.user = User.objects.create_user(
            username='stats_tester',
            email='stats@example.com',
            password='password123'
        )
        self.client.force_authenticate(user=self.user)
        
        self.profile_url = reverse('profile')
        self.watchlist_url = reverse('watchlist-list-create')

    def test_profile_stats_and_favorites_workflow(self):
        """تست پویای آمار پروفایل هنگام تغییر وضعیت فیلم‌ها، سریال‌ها و علاقه‌مندی‌ها"""
        
        # ۱. بررسی وضعیت اولیه (باید همه چیز صفر و خالی باشد)
        res_initial = self.client.get(self.profile_url)
        self.assertEqual(res_initial.status_code, status.HTTP_200_OK)
        self.assertEqual(res_initial.data['watched_movies_count'], 0)
        self.assertEqual(res_initial.data['watched_shows_count'], 0)
        self.assertEqual(len(res_initial.data['favorite_items']), 0)

        # ۲. اضافه کردن دو فیلم و علامت‌زدن آن‌ها به عنوان تکمیل‌شده (completed)
        self.client.post(self.watchlist_url, {
            'imdb_id': 'tt0111161', 'title_type': 'movie', 'title_name': 'Shawshank', 'status': 'completed'
        })
        self.client.post(self.watchlist_url, {
            'imdb_id': 'tt0068646', 'title_type': 'movie', 'title_name': 'The Godfather', 'status': 'completed'
        })

        # ۳. چک کردن پروفایل: تعداد فیلم‌ها باید ۲ شود، اما سریال‌ها و علاقه‌مندی‌ها تغییری نکنند (همچنان صفر)
        res_movies_checked = self.client.get(self.profile_url)
        self.assertEqual(res_movies_checked.data['watched_movies_count'], 2)
        self.assertEqual(res_movies_checked.data['watched_shows_count'], 0) # بدون تغییر
        self.assertEqual(len(res_movies_checked.data['favorite_items']), 0) # بدون تغییر

        # ۴. اضافه کردن سریال Breaking Bad و تکمیل آن
        res_bb = self.client.post(self.watchlist_url, {
            'imdb_id': 'tt0903747', 'title_type': 'tv', 'title_name': 'Breaking Bad', 'total_episodes': 62, 'status': 'completed'
        })
        bb_detail_url = reverse('watchlist-detail', kwargs={'imdb_id': 'tt0903747'})

        # ۵. چک کردن پروفایل بعد از دیدن سریال: تعداد سریال‌ها باید ۱ شود
        res_shows_checked = self.client.get(self.profile_url)
        self.assertEqual(res_shows_checked.data['watched_movies_count'], 2) # فیلم‌ها دست‌نخورده
        self.assertEqual(res_shows_checked.data['watched_shows_count'], 1)  # سریال تکمیل شد
        self.assertEqual(len(res_shows_checked.data['favorite_items']), 0) # هنوز علاقه‌مندی اضافه نشده

        # ۶. علامت‌زدن دو تا از آثار به عنوان مورد علاقه (is_favorite=True)
        # علاقه‌مندی اول: فیلم اول
        self.client.patch(reverse('watchlist-detail', kwargs={'imdb_id': 'tt0111161'}), {'is_favorite': True})
        # علاقه‌مندی دوم: سریال Breaking Bad
        self.client.patch(bb_detail_url, {'is_favorite': True})

        # ۷. بررسی نهایی پروفایل: تعداد علاقه‌مندی‌ها باید دقیقاً ۲ تا باشد و آمار قبلی حفظ شده باشد
        res_final = self.client.get(self.profile_url)
        self.assertEqual(res_final.data['watched_movies_count'], 2)
        self.assertEqual(res_final.data['watched_shows_count'], 1)
        
        favorites = res_final.data['favorite_items']
        self.assertEqual(len(favorites), 2)
        
        favorite_imdb_ids = [item['imdb_id'] for item in favorites]
        self.assertIn('tt0111161', favorite_imdb_ids)
        self.assertIn('tt0903747', favorite_imdb_ids)