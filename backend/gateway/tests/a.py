from django.test import TestCase, Client
from django.urls import reverse

class ImdbProxyTests(TestCase):
    def setUp(self):
        self.client = Client()

    def test_search_api_missing_query(self):
        """تست هندل کردن خطای نبود پارامتر جستجو"""
        response = self.client.get(reverse('api-search'))
        self.assertEqual(response.status_code, 400)
        self.assertIn('error', response.json())

    # --- ۲. تست جریان یکپارچه (Integration/Use-case Test) ---
    def test_young_sheldon_use_case(self):
        """
        تست سناریوی یکپارچه: 
        سرچ کردن Young Sheldon و اطمینان از پیدا شدن سریال و بازیگر سوم آن
        """
        # قدم اول: زدن API جستجو
        response = self.client.get(reverse('api-search'), {'q': 'young sheldon'})
        self.assertEqual(response.status_code, 200)
        
        results = response.json().get('results', [])
        self.assertTrue(len(results) > 0, "لیست نتایج جستجو نباید خالی باشد")

        # قدم دوم: پیدا کردن خود سریال در بین نتایج
        series_item = next((item for item in results if item.get('id') == 'tt6226232'), None)
        self.assertIsNotNone(series_item, "سریال Young Sheldon در نتایج یافت نشد")
        self.assertEqual(series_item.get('l'), 'Young Sheldon')

        # قدم سوم: بررسی وجود نام بازیگر (Iain Armitage) در اطلاعات سریال
        actors_string = series_item.get('s', '')
        self.assertIn('Iain Armitage', actors_string, "بازیگر مورد نظر در لیست بازیگران سریال وجود ندارد")
        
        # قدم چهارم: اطمینان از وجود پوستر سریال
        self.assertIn('i', series_item)
        self.assertIn('imageUrl', series_item['i'], "لینک پوستر سریال یافت نشد")

    def test_breaking_bad_integration_and_graphql_hash(self):
        """
        تست سناریوی یکپارچه و اثبات کارکرد هش GraphQL: 
        جستجوی Breaking Bad و دریافت لیست قسمت‌های فصل اول آن
        """
        # قدم اول: زدن API جستجو
        search_response = self.client.get(reverse('api-search'), {'q': 'breaking bad'})
        self.assertEqual(search_response.status_code, 200)
        
        results = search_response.json().get('results', [])
        self.assertTrue(len(results) > 0, "لیست نتایج جستجو نباید خالی باشد")

        # قدم دوم: پیدا کردن شناسه اختصاصی سریال (tt0903747) در بین نتایج
        series_item = next((item for item in results if item.get('id') == 'tt0903747'), None)
        self.assertIsNotNone(series_item, "سریال Breaking Bad در نتایج یافت نشد")
        self.assertEqual(series_item.get('l'), 'Breaking Bad')

        # قدم سوم: بررسی وجود نام بازیگر اصلی (Bryan Cranston)
        actors_string = series_item.get('s', '')
        self.assertIn('Bryan Cranston', actors_string, "بازیگر مورد نظر در لیست یافت نشد")
        
        # قدم چهارم: تست API قسمت‌ها برای اطمینان از کارکرد عمومی هش GraphQL
        episodes_response = self.client.get(reverse('api-episodes'), {'id': 'tt0903747', 'season': '1'})
        self.assertEqual(episodes_response.status_code, 200, "دریافت اطلاعات از GraphQL با خطا مواجه شد")
        
        episodes_data = episodes_response.json().get('results', [])
        self.assertTrue(len(episodes_data) > 0, "لیست قسمت‌های فصل اول نباید خالی باشد")
        
        # بررسی صحت دیتای دریافتی بر اساس ساختار تمیز و جدید ویو
        first_episode = episodes_data[0]
        self.assertIn('title', first_episode, "ساختار دیتای قسمت‌ها نامعتبر است")
        self.assertIsNotNone(first_episode['title'], "نام قسمت نباید خالی باشد")

    def test_stranger_things_season3_episode4(self):
        """
        تست یکپارچه: جستجوی Stranger Things، دریافت فصل 3 و اعتبارسنجی قسمت 4
        """
        # مرحله ۱: جستجوی سریال
        search_res = self.client.get(reverse('api-search'), {'q': 'stranger things'})
        self.assertEqual(search_res.status_code, 200)
        search_results = search_res.json().get('results', [])
        self.assertTrue(len(search_results) > 0, "جستجو نباید خالی باشد")
        
        # پیدا کردن ID سریال از نتایج جستجو (شناسه Stranger Things برابر tt4574334 است)
        # برای اطمینان، با اسم سرچ می‌کنیم تا دقیقاً همان رفتار کاربر شبیه‌سازی شود
        series_id = None
        for item in search_results:
            if 'Stranger Things' in item.get('l', ''):
                series_id = item.get('id')
                break
                
        self.assertIsNotNone(series_id, "سریال Stranger Things در نتایج یافت نشد")

        # مرحله ۲: دریافت اطلاعات فصل 3
        episodes_res = self.client.get(reverse('api-episodes'), {'id': series_id, 'season': '3'})
        self.assertEqual(episodes_res.status_code, 200)
        
        episodes_list = episodes_res.json().get('results', [])
        self.assertTrue(len(episodes_list) > 0, "لیست قسمت‌های فصل 3 خالی است")

        # مرحله ۳: پیدا کردن قسمت 4
        episode_4 = next((ep for ep in episodes_list if str(ep.get('episode_number')) == '4'), None)
        self.assertIsNotNone(episode_4, "قسمت چهارم یافت نشد")

        # مرحله ۴: بررسی دقیق نیازمندی‌ها (نام و تاریخ)
        self.assertEqual(episode_4.get('title'), "Chapter Four: The Sauna Test", "نام قسمت اشتباه است")
        self.assertIn("July 4, 2019", episode_4.get('release_date', ""), "تاریخ انتشار اشتباه است")