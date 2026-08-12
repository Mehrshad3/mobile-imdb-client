import logging
from django.http import JsonResponse
from django.views import View
from curl_cffi import requests as cffi_requests
import requests
import urllib.parse

from .base import ImdbProxyBaseView

logger = logging.getLogger(__name__)


class SearchView(ImdbProxyBaseView):
    def get(self, request):
        query = request.GET.get('q', '')
        if not query:
            return JsonResponse({'error': 'پارامتر q الزامی است'}, status=400)

        safe_query = urllib.parse.quote(query)
        url = f'https://v3.sg.media-imdb.com/suggestion/x/{safe_query}.json'
        
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

class NameSuggestionView(View):
    def get(self, request):
        query = request.GET.get('q', '').strip().lower()
        if not query:
            return JsonResponse({"status": "error", "message": "پارامتر 'q' الزامی است"}, status=400)
        
        # استخراج حرف اول برای ساختاردهی درست URL کلاینت IMDb
        first_char = query[0]
        
        # جایگزینی فاصله‌ها با آندرلاین برای فرمت استاندارد این API
        safe_query = urllib.parse.quote(query.replace(' ', '_'))
        
        url = f"https://v3.sg.media-imdb.com/suggestion/names/{first_char}/{safe_query}.json"
        
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36',
            'Accept': 'application/json',
            'Referer': 'https://www.imdb.com/',
        }
        
        try:
            response = requests.get(url, headers=headers, timeout=5)
            
            if response.status_code != 200:
                return JsonResponse({"status": "error", "message": "خطا در ارتباط با سرور پیشنهادهای IMDb"}, status=response.status_code)
                
            data = response.json()
            suggestions = []
            
            for item in data.get('d', []):
                # فقط افرادی را برمی‌گردانیم که ID آن‌ها با 'nm' (شناسه Name در IMDb) شروع می‌شود
                if item.get('id', '').startswith('nm'):
                    suggestions.append({
                        'id': item.get('id'),
                        'name': item.get('l'),
                        'description': item.get('s'), # مثلاً Actor, The Natural (1984)
                        'image': item.get('i', {}).get('imageUrl')
                    })
                    
            return JsonResponse({"status": "success", "data": suggestions}, status=200)
            
        except Exception as e:
            return JsonResponse({"status": "error", "message": str(e)}, status=500)