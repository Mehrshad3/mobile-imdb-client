from django.test import TestCase

class SuggestionAndSearchTests(TestCase):
    def test_name_suggestion_api_success(self):
        """
        تست API پیشنهادات نام (Name Autocomplete)
        بررسی اینکه آیا با ارسال بخشی از نام، اطلاعات صحیح و تصاویر برمی‌گردد یا خیر.
        """
        # فرض می‌کنیم مسیر را در urls.py تنظیم کرده‌ای
        response = self.client.get('/api/suggest/name/', {'q': 'r revord'})
        
        # بررسی وضعیت HTTP
        if response.status_code != 200:
            print("\n!!! ERROR DETAILS !!! :", response.json())
        self.assertEqual(response.status_code, 200)
        
        json_response = response.json()
        self.assertEqual(json_response['status'], 'success')
        
        data = json_response['data']
        self.assertTrue(len(data) > 0, "لیست پیشنهادات نباید خالی باشد")
        
        # بررسی استخراج صحیح فیلدها و وجود نام مدنظر
        names = [item['name'] for item in data]
        self.assertIn('Raegan Revord', names)
        
        # بررسی ساختار اولین آیتم لیست
        first_item = data[0]
        self.assertIn('id', first_item)
        self.assertIn('name', first_item)
        self.assertIn('description', first_item)
        self.assertIn('image', first_item)
        
        # اطمینان از اینکه خروجی فقط شامل اشخاص (شروع شده با nm) است
        self.assertTrue(first_item['id'].startswith('nm'))

    def test_name_suggestion_api_empty_query(self):
        """
        تست هندل کردن درخواست‌های بدون پارامتر
        """
        response = self.client.get('/api/suggest/name/')
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()['status'], 'error')

    def test_global_search_view_api(self):
        """
        تست جستجوی سراسری (SearchView)
        بررسی عملکرد موتور GraphQL آمازون برای پیدا کردن یک اثر مشخص
        """
        # فرض می‌کنیم مسیر این API روی /api/search/ تنظیم شده است
        response = self.client.get('/api/search/', {'q': 'Inception'})
        
        self.assertEqual(response.status_code, 200)
        
        # از آنجایی که ساختار دقیق خروجی SearchView شما را ندارم، وجود کلمه کلیدی را در خامِ پاسخ بررسی می‌کنیم
        response_text = str(response.content)
        self.assertIn('Inception', response_text, "کلمه Inception باید در نتایج جستجوی سراسری وجود داشته باشد")


class AdvancedSearchTests(TestCase):
    def test_advanced_search_with_filters(self):
        """
        تست جستجوی پیشرفته: 
        بررسی عملکرد جستجو بر اساس کلمه کلیدی، ژانر، و حداقل امتیاز.
        """
        response = self.client.get('/api/search/advanced/', {
            'q': 'Godfather',
            'genre': 'Drama,Crime',
            'min_rating': '8.5',
            'cast': 'nm0000008,',
        })
        
        # چاپ خطاهای پنهان در صورت بروز مشکل
        if response.status_code != 200:
            print("\n!!! ERROR DETAILS !!! :", response.json())
 
        self.assertEqual(response.status_code, 200)
        
        # دریافت خروجی آپدیت‌شده
        data = response.json()
        
        # بررسی وجود کلید results به جای status
        self.assertIn('results', data)
        self.assertTrue(len(data['results']) > 0, "لیست نتایج جستجوی پیشرفته نباید خالی باشد")


    def test_advanced_search_date_range(self):
        """
        تست جستجوی پیشرفته با استفاده از بازه زمانی (سال انتشار)
        """
        response = self.client.get('/api/search/advanced/', {
            'type': 'movie',
            'start_date': '2020-01-01',
            'end_date': '2023-12-31'
        })
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        
        self.assertIn('results', data)
        self.assertTrue(len(data['results']) > 0)