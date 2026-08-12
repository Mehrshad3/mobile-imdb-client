import json
import re
from bs4 import BeautifulSoup
import requests

from .base_scraper import BaseImdbScraper

class SeriesDetailedView(BaseImdbScraper):
    def _extract_json_ld(self):
        """متد کمکی برای استخراج دیتای ساختاریافته JSON از HTML"""
        assert self.soup is not None
        script_tag = self.soup.find('script', type='application/ld+json')
        if script_tag:
            self.json_ld_data = json.loads(script_tag.string)

    def get_basic_info(self):
        """استخراج اطلاعات پایه‌ای از JSON-LD"""
        return {
            'title': self.json_ld_data.get('name'),
            'poster': self.json_ld_data.get('image'),
            'description': self.json_ld_data.get('description'),
            'genres': self.json_ld_data.get('genre', []),
            'rating': self.json_ld_data.get('aggregateRating', {}).get('ratingValue'),
            'actors': [actor['name'] for actor in self.json_ld_data.get('actor', []) if actor.get('@type') == 'Person']
        }

    def get_years_and_status(self):
        """متد کمکی برای استخراج سال شروع، سال پایان و وضعیت پخش"""
        # پیدا کردن تگ a که شامل releaseinfo است
        assert self.soup is not None
        year_tag = self.soup.find('a', href=re.compile(r'/releaseinfo'))
        
        start_year = None
        end_year = None
        status = "Unknown"

        if year_tag:
            year_text = year_tag.text.strip() # خروجی مثلا: "2008–2013" یا "2020" یا "2020–"
            
            if '–' in year_text or '-' in year_text: # توجه: کاراکتر dash ممکنه در وبسایت متفاوت باشه (en-dash یا hyphen)
                years = re.split(r'[–-]', year_text)
                start_year = years[0]
                if len(years) > 1 and years[1].strip():
                    end_year = years[1]
                    status = "Ended"
                else:
                    status = "Returning Series / Ongoing"
            else:
                start_year = year_text
                end_year = year_text # مینی‌سریال‌ها یا سریال‌های یک ساله
                status = "Ended"

        return {
            'start_year': start_year,
            'end_year': end_year,
            'status': status
        }

    def get_country_of_origin(self):
        """متد کمکی برای استخراج کشور مبدا"""
        # با توجه به ساختار دیتایی که فرستادید (از تگ‌های اسکریپت __NEXT_DATA__ یا مشابه اون)
        # معمولا تو صفحه کلماتی مثل "Country of origin" وجود داره
        assert self.soup is not None
        country_li = self.soup.find('li', attrs={"data-testid": "title-details-origin"})
        if country_li:
            countries = [a.text for a in country_li.find_all('a')]
            return countries
        return []

    def get_all_details(self):
        """تجمیع تمام اطلاعات برای ارسال به عنوان خروجی نهایی"""
        if not self.soup:
            self.fetch_page()
            
        details = self.get_basic_info()
        details.update(self.get_years_and_status())
        details['country'] = self.get_country_of_origin()
        
        return details

import re


class MovieDetailedScraper(BaseImdbScraper):
    def get_all_details(self):
        """استخراج تمام اطلاعات فیلم"""
        if not self.soup:
            self.fetch_page()

        details = {
            'title': self.json_ld_data.get('name'),
            'poster': self.json_ld_data.get('image'),
            'description': self.json_ld_data.get('description'),
            'genres': self.json_ld_data.get('genre', []),
            'rating': self.json_ld_data.get('aggregateRating', {}).get('ratingValue'),
            'actors': [actor['name'] for actor in self.json_ld_data.get('actor', []) if actor.get('@type') == 'Person']
        }

        # ۱. استخراج کارگردان (Director)
        directors = self.json_ld_data.get('director', [])
        # گاهی یک کارگردان است (آبجکت) و گاهی چند تا (لیست)
        if isinstance(directors, dict):
            directors = [directors]
        details['directors'] = [d['name'] for d in directors if d.get('@type') == 'Person']

        # ۲. استخراج سال انتشار
        date_published = self.json_ld_data.get('datePublished', '')
        details['year'] = date_published.split('-')[0] if date_published else None

        # ۳. استخراج و تبدیل فرمت مدت زمان (مثلاً PT1H54M به 1h 54m)
        raw_duration = self.json_ld_data.get('duration', '')
        duration_str = ""
        if raw_duration.startswith('PT'):
            raw_duration = raw_duration[2:] # حذف 'PT'
            if 'H' in raw_duration:
                h_part, raw_duration = raw_duration.split('H')
                duration_str += f"{h_part}h "
            if 'M' in raw_duration:
                m_part = raw_duration.replace('M', '')
                duration_str += f"{m_part}m"
        details['duration'] = duration_str.strip()

        # ۴. استخراج کشور (از HTML)
        country_li = self.soup.find('li', attrs={"data-testid": "title-details-origin"})
        details['country'] = [a.text for a in country_li.find_all('a')] if country_li else []

        return details