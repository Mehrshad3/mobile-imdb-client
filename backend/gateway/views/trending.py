import json
import logging
from django.http import JsonResponse
from curl_cffi import requests as cffi_requests

from .base import ImdbProxyBaseView

logger = logging.getLogger(__name__)

class TrendingView(ImdbProxyBaseView):
    def get(self, request):
        url = 'https://caching.graphql.imdb.com/'
        
        params = {
            'operationName': 'Trending',
            'variables': json.dumps(
                {"first": 8, "input": {"dataWindow": "HOURS", "trafficSource": "XWW"}},
                separators=(',', ':')
            ),
            'extensions': json.dumps({
                "persistedQuery": {
                    "sha256Hash": "419b4fc66817a78c3046e0cedef747033d5ac2711080338a59a366630f9742c1",
                    "version": 1
                }
            }, separators=(',', ':'))
        }

        try:
            # فراخوانی متد برای دریافت هدرهای داینامیک
            request_headers = self.get_imdb_headers()
            
            response = cffi_requests.get(
                url, 
                headers=request_headers, 
                params=params, 
                impersonate="chrome110", 
                timeout=10
            )
            
            if response.status_code != 200:
                logger.error(f"IMDB responded with status: {response.status_code}")
                logger.error(f"IMDB error details: {response.text}") 
                return JsonResponse({
                    'error': f"IMDb API Error: {response.status_code}",
                    'details': response.text 
                }, status=502)
                
            data = response.json().get('data', {}).get('topTrendingTitles', {}).get('edges', [])
            return JsonResponse({'results': data}, status=200)
            
        except Exception as e:
            logger.error(f"IMDB API exception: {e}")
            return JsonResponse({'error': str(e)}, status=502)
