import logging
from django.http import JsonResponse
from curl_cffi import requests as cffi_requests
from .base import ImdbProxyBaseView

logger = logging.getLogger(__name__)


class SearchView(ImdbProxyBaseView):
    def get(self, request):
        query = request.GET.get('q', '')
        if not query:
            return JsonResponse({'error': 'پارامتر q الزامی است'}, status=400)

        first_char = query[0].lower() if query else 'a'
        url = f'https://v3.sg.media-imdb.com/suggestion/{first_char}/{query}.json'
        
        try:
            # فراخوانی متد برای دریافت هدرهای داینامیک
            request_headers = self.get_imdb_headers()
            
            response = cffi_requests.get(
                url, 
                headers=request_headers, 
                params={'includeVideos': '1'}, 
                impersonate="chrome110",
                timeout=10
            )
            
            if response.status_code != 200:
                return JsonResponse({'error': f"IMDb API Error: {response.status_code}"}, status=502)
                
            data = response.json().get('d', [])
            return JsonResponse({'results': data}, status=200)
            
        except Exception as e:
            return JsonResponse({'error': str(e)}, status=502)