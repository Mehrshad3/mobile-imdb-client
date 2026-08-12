from django.test import TestCase
from gateway.views.details import SeriesDetailedView, MovieDetailedScraper
import time

class SeriesDetailedScraperTests(TestCase):
    def test_3_body_problem_ongoing_status(self):
        """
        تست یکپارچه برای بررسی یک سریال در حال پخش (Ongoing)
        بررسی استخراج صحیح سال، وضعیت، ژانرها و بازیگران
        """
        # آدرس سریال 3 Body Problem
        url = "https://www.imdb.com/title/tt13016388/"
        scraper = SeriesDetailedView(url)
        
        # فراخوانی متد اصلی که صفحه رو میگیره و دیتا رو استخراج میکنه
        details = scraper.get_all_details()
        
        # ۱. بررسی عنوان
        self.assertEqual(details['title'], '3 Body Problem')
        
        # ۲. بررسی خلاصه داستان (Description)
        self.assertIn("A fateful decision made in 1960s China", details['description'])
        
        # ۳. بررسی ژانرها
        self.assertIn('Adventure', details['genres'])
        self.assertIn('Drama', details['genres'])
        self.assertIn('Fantasy', details['genres'])
        
        # ۴. بررسی وضعیت پخش و سال‌ها (مهم‌ترین بخش این تست)
        self.assertEqual(details['start_year'], '2024')
        self.assertIsNone(details['end_year'], "سال پایان برای سریال در حال پخش باید None باشد")
        self.assertEqual(details['status'], 'Returning Series / Ongoing')
        
        # ۵. بررسی بازیگران (بررسی چند نمونه)
        self.assertIn('Jovan Adepo', details['actors'])
        self.assertIn('Liam Cunningham', details['actors'])
        self.assertIn('Eiza González', details['actors'])
        
        # ۶. بررسی امتیاز (اطمینان از وجود داشتن و فرمت صحیح)
        self.assertIsNotNone(details['rating'], "امتیاز نباید خالی باشد")
        rating_float = float(details['rating'])
        self.assertTrue(7.3 <= rating_float <= 7.7, "امتیاز باید در یک بازه منطقی باشد")


class MovieDetailedScraperTests(TestCase):
    def test_imitation_game_movie_details(self):
        """
        تست استخراج اطلاعات فیلم سینمایی The Imitation Game
        بررسی مدت زمان، کارگردان، ژانر و ...
        """
        url = "https://www.imdb.com/title/tt2084970/"
        scraper = MovieDetailedScraper(url)
        details = scraper.get_all_details()
        
        # بررسی عنوان
        self.assertEqual(details['title'], 'The Imitation Game')
        
        # بررسی سال انتشار
        self.assertEqual(details['year'], '2014')
        
        # بررسی مدت زمان (باید از PT1H54M به 1h 54m تبدیل شده باشد)
        self.assertEqual(details['duration'], '1h 54m')
        
        # بررسی کارگردان
        self.assertIn('Morten Tyldum', details['directors'])
        
        # بررسی خلاصه داستان
        self.assertIn('English mathematical genius Alan Turing', details['description'])
        self.assertNotIn('gay', details['description'])
        
        # بررسی ژانرها
        self.assertIn('Biography', details['genres'])
        self.assertIn('Drama', details['genres'])
        self.assertIn('Thriller', details['genres'])
        
        # بررسی بازیگران
        self.assertIn('Benedict Cumberbatch', details['actors'])
        self.assertIn('Keira Knightley', details['actors'])
        self.assertIn('Matthew Goode', details['actors'])
        
        # بررسی امتیاز
        self.assertIsNotNone(details['rating'])
        self.assertTrue(7.8 <= float(details['rating']) <= 8.2)
        
        # بررسی کشور سازنده
        self.assertIn('United States', details['country'])