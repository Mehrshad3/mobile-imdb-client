from playwright.sync_api import sync_playwright
from bs4 import BeautifulSoup
import json
import logging

logger = logging.getLogger(__name__)

class BaseImdbScraper:
    def __init__(self, url):
        self.url = url
        self.soup = None
        self.json_ld_data = {}

    def fetch_page(self):
        """دریافت HTML کامل صفحه با استفاده از مرورگر واقعی برای عبور قطعی از فایروال"""
        try:
            with sync_playwright() as p:
                browser = p.chromium.launch(
                    headless=True, 
                    args=['--disable-blink-features=AutomationControlled']
                )
                context = browser.new_context(
                    user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36',
                    viewport={'width': 1920, 'height': 1080}
                )
                page = context.new_page()
                
                logger.info(f"Navigating to {self.url} with Playwright...")
                # لود کردن صفحه (منتظر می‌مانیم تا ساختار اصلی DOM شکل بگیرد)
                page.goto(self.url, wait_until='domcontentloaded', timeout=60000)
                page.wait_for_timeout(6000) # مرورگر را دقیقاً ۱۰ ثانیه باز نگه می‌دارد
                
                # استخراج HTML خالص و رندر شده
                html_content = page.content()
                
                self.soup = BeautifulSoup(html_content, 'html.parser')
                self._extract_json_ld()
                
                browser.close()
                
        except Exception as e:
            logger.error(f"Playwright scraping error: {str(e)}")
            raise Exception(f"Failed to scrape the page: {str(e)}")

    def _extract_json_ld(self):
        """متد عمومی برای استخراج دیتای ساختاریافته JSON-LD"""
        if self.soup:
            script_tag = self.soup.find('script', type='application/ld+json')
            if script_tag:
                self.json_ld_data = json.loads(script_tag.string)