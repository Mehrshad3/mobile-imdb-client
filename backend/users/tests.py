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
        
        # یک عکس فیک (گیف ۱ پیکسلی) در حافظه موقت (بدون اشغال هارد) برای تست آپلود
        self.dummy_image = SimpleUploadedFile(
            name='test_avatar.gif',
            content=b'\x47\x49\x46\x38\x39\x61\x01\x00\x01\x00\x00\xff\x00\x2c\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x00\x3b',
            content_type='image/gif'
        )

    def test_user_login_and_get_token(self):
        """تست ورود کاربر با ایمیل و رمز عبور (بخش ۲.۵)"""
        response = self.client.post(self.login_url, {
            'email': 'test@example.com',
            'password': 'StrongPassword123!'
        })
        
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('access', response.data) # باید توکن دسترسی بدهد
        self.assertIn('refresh', response.data) # باید توکن رفرش (۱ ماهه) بدهد
        
        # ذخیره توکن برای تست‌های بعدی
        self.token = response.data['access']

    def test_view_and_update_profile(self):
        """تست مشاهده و ویرایش پروفایل (بخش ۴.۵)"""
        # ۱. ابتدا باید توکن را به هدر درخواست اضافه کنیم (احراز هویت)
        # برای این کار مستقیماً یوزر را در کلاینت فورس می‌کنیم
        self.client.force_authenticate(user=self.user)
        
        # ۲. مشاهده پروفایل (باید دیتای خالی بیو و آمار صفر را نشان دهد)
        get_response = self.client.get(self.profile_url)
        self.assertEqual(get_response.status_code, status.HTTP_200_OK)
        self.assertEqual(get_response.data['email'], 'test@example.com')
        self.assertEqual(get_response.data['watched_movies_count'], 0) # مقدار پیش‌فرض خودکار
        
        # ۳. ویرایش پروفایل (آپلود عکس و افزودن بیو)
        # نکته: وقتی فایل آپلود می‌کنیم، فرمت درخواست باید multipart باشد
        update_data = {
            'bio': 'این یک توضیح کوتاه درباره من است.',
            'profile_picture': self.dummy_image
        }
        patch_response = self.client.patch(self.profile_url, update_data, format='multipart')
        
        self.assertEqual(patch_response.status_code, status.HTTP_200_OK)
        self.assertEqual(patch_response.data['bio'], update_data['bio'])
        self.assertIsNotNone(patch_response.data['profile_picture'])
        
        # بررسی اینکه لینک دانلود عکس به درستی تولید شده باشد
        self.assertTrue(patch_response.data['profile_picture'].startswith('http'))