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


class AdvancedSearchView(ImdbProxyBaseView):
    def get(self, request):
        url = 'https://caching.graphql.imdb.com/'
        
        # ۱. دریافت پارامترهای فیلتر از فلاتر
        query = request.GET.get('q')
        title_type = request.GET.get('type') 
        genre = request.GET.get('genre')
        min_rating = request.GET.get('min_rating')
        start_date = request.GET.get('start_date')
        end_date = request.GET.get('end_date')
        cast_ids = request.GET.get('cast')
        
        # ۲. دریافت پارامترهای مرتب‌سازی (پیش‌فرض روی محبوب‌ترین آثار)
        # مقادیر معتبر برای sort_by می‌تواند POPULARITY یا USER_RATING باشد
        sort_by = request.GET.get('sort_by', 'POPULARITY').upper()
        # مقادیر معتبر برای sort_order می‌تواند ASC (صعودی) یا DESC (نزولی) باشد
        sort_order = request.GET.get('sort_order', 'ASC').upper()
        
        # ۳. ساختاردهی متغیرهای GraphQL
        variables = {
            "locale": "en-US",
            "first": 30, # تعداد نتایجی که می‌خواهی در هر ریکوئست برگردد
            "sortBy": sort_by,
            "sortOrder": sort_order,
        }
        
        if query:
            variables["titleTextConstraint"] = {"searchTerm": query}
            
        if title_type:
            variables["titleTypeConstraint"] = {"anyTitleTypeIds": title_type.split(',')}
            
        if genre:
            formatted_genres = [g.strip().capitalize() for g in genre.split(',')]
            variables["genreConstraint"] = {"allGenreIds": formatted_genres}
            
        if min_rating:
            variables["userRatingsConstraint"] = {
                "aggregateRatingRange": {"min": float(min_rating), "max": 10}
            }
            
        if start_date or end_date:
            date_range = {}
            if start_date: date_range["start"] = start_date
            if end_date: date_range["end"] = end_date
            variables["releaseDateConstraint"] = {"releaseDateRange": date_range}

        if cast_ids:
            credits_list = [{"nameId": n_id.strip()} for n_id in cast_ids.split(',')]
            variables["titleCreditsConstraint"] = {"allCredits": credits_list}

        # ۴. ساخت Payload نهایی
        payload = {
            "operationName": "AdvancedTitleSearch",
            "variables": variables,
            "extensions": {
                "persistedQuery": {
                    "version": 1,
                    "sha256Hash": "78932519bc74ceb6be628fe452c0e59a48bcf8ca91fc550dd5de43ab200acd52"
                }
            }
        }

        try:
            request_headers = self.get_imdb_headers()
            request_headers['content-type'] = 'application/json'
            
            # در اینجا از cffi_requests استفاده می‌کنیم (یا هر کتابخانه‌ای که در پروژه داری)
            response = cffi_requests.post(
                url, 
                headers=request_headers, 
                json=payload, 
                impersonate="chrome110", 
                timeout=15
            )
            
            if response.status_code != 200:
                return JsonResponse({'error': f"IMDb API Error: {response.status_code}"}, status=502)
                
            data = response.json().get('data', {}).get('advancedTitleSearch', {})
            return JsonResponse({'results': data.get('edges', [])}, status=200)
            
        except Exception as e:
            return JsonResponse({'error': str(e)}, status=500)

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
            response = requests.get(url, headers=headers, timeout=10)
            
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