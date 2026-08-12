import logging
import time
from django.views import View
from playwright.sync_api import sync_playwright

logger = logging.getLogger(__name__)

class ImdbProxyBaseView(View):
    # Class-level cache so we don't open a new browser for every single request
    _cached_headers = None
    _last_fetch_time = 0
    _cache_duration = 3600  # Re-fetch session ID every 1 hour

    @classmethod
    def get_imdb_headers(cls):
        # 1. Check if cached headers are still valid (less than 1 hour old)
        current_time = time.time()
        if (ImdbProxyBaseView._cached_headers and 
            (current_time - ImdbProxyBaseView._last_fetch_time) < ImdbProxyBaseView._cache_duration):
            logger.info("Returning cached headers.")
            return ImdbProxyBaseView._cached_headers

        logger.info("Generating new headers and fetching Session ID using a hidden Playwright browser...")
        
        # Base headers
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36',
            'Accept': 'application/graphql+json, application/json',
            'Accept-Language': 'en-US,en;q=0.9',
            'Referer': 'https://www.imdb.com/',
            'Content-Type': 'application/json',
            'x-imdb-client-name': 'imdb-web-next-localized',
            'x-imdb-user-language': 'en-US',
            'x-imdb-user-country': 'US',
        }

        browser = None
        try:
            # 2. Launch Playwright context (uses the Chromium you just installed)
            logger.info("Launching Playwright Chromium in headless mode...")
            playwright_instance = sync_playwright().start()
            
            browser = playwright_instance.chromium.launch(
                headless=True,
                args=['--disable-blink-features=AutomationControlled']
            )
            
            # Create an isolated context (like an incognito tab)
            context = browser.new_context(
                user_agent=headers['User-Agent'],
                viewport={'width': 1920, 'height': 1080}
            )
            
            page = context.new_page()

            # 3. Visit the main IMDb page
            logger.info("Loading IMDb homepage to trigger challenge.js...")
            page.goto('https://www.imdb.com/', wait_until='domcontentloaded', timeout=20000)

            # 4. Wait for the Cloudflare/Amazon WAF challenge to finish and cookies to be set
            logger.info("Waiting 5.1 seconds for JavaScript to execute...")
            page.wait_for_timeout(5100)  # Playwright's version of time.sleep()

            # 5. Extract the cookies from the browser's internal memory
            cookies = context.cookies()
            session_id = None
            
            for cookie in cookies:
                if cookie['name'] == 'session-id':
                    session_id = cookie['value']
                    logger.info(f"Successfully grabbed fresh session-id from hidden browser: {session_id[:15]}...")
                    break

            if session_id:
                headers['x-amzn-sessionid'] = session_id
            else:
                # If the browser somehow didn't get it, we log a critical error.
                logger.critical("Hidden browser loaded the page but could not find the session-id cookie!")
                raise ValueError("Failed to retrieve session-id")

        except Exception as e:
            logger.error(f"Error fetching session-id via Playwright headless browser: {e}")
            # Re-raise the exception to stop the API call
            raise ConnectionError("Could not authenticate with IMDb automatically. Please check Playwright installation.") from e
            
        finally:
            # 6. Always close the browser to free up RAM
            if browser:
                try:
                    browser.close()
                except:
                    pass
            try:
                playwright_instance.stop()
            except:
                pass

        # 7. Cache the new headers and timestamp
        ImdbProxyBaseView._cached_headers = headers
        ImdbProxyBaseView._last_fetch_time = time.time()
        
        return ImdbProxyBaseView._cached_headers
