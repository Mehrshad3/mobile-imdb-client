from django.test import TestCase, Client
from django.urls import reverse

class TestTrending(TestCase):
    def setUp(self):
        self.client = Client()

    def test_trending_api_returns_success(self):
        """تست اطمینان از کارکرد API ترندها بدون خطای شبکه"""
        response = self.client.get(reverse('api-trending'))
        self.assertEqual(response.status_code, 200)
        
        data = response.json()
        self.assertIn('results', data)
        self.assertTrue(len(data['results']) > 0)
        
        # بررسی اینکه ساختار مورد انتظار (titleText) وجود دارد
        first_item = data['results'][0]
        self.assertIn('node', first_item)

    def test_trending_movies_only(self):
        """تست فیلتر شدن دقیق برای فیلم‌های سینمایی (type=movie)"""
        response = self.client.get(reverse('api-trending'), {'type': 'movie'})
        self.assertEqual(response.status_code, 200)
        
        data = response.json()
        results = data.get('results', [])
        
        self.assertTrue(len(results) > 0, "لیست فیلم‌های ترند نباید خالی باشد")
        
        # بررسی خلوص نتایج: تک‌تک آیتم‌ها باید حتماً movie باشند
        for item in results:
            title_type = item.get('node', {}).get('titleType', {}).get('id')
            self.assertEqual(
                title_type, 
                'movie', 
                f"خطا در فیلترینگ: نوع '{title_type}' در لیست فیلم‌ها پیدا شد!"
            )

    def test_trending_tv_only(self):
        """تست فیلتر شدن دقیق برای سریال‌ها (type=tv)"""
        response = self.client.get(reverse('api-trending'), {'type': 'tv'})
        self.assertEqual(response.status_code, 200)
        
        data = response.json()
        results = data.get('results', [])
        
        self.assertTrue(len(results) > 0, "لیست سریال‌های ترند نباید خالی باشد")
        
        # بررسی خلوص نتایج: تک‌تک آیتم‌ها باید tvSeries یا tvMiniSeries باشند
        valid_tv_types = ['tvSeries', 'tvMiniSeries']
        for item in results:
            title_type = item.get('node', {}).get('titleType', {}).get('id')
            self.assertIn(
                title_type, 
                valid_tv_types, 
                f"خطا در فیلترینگ: نوع '{title_type}' در لیست سریال‌ها پیدا شد!"
            )