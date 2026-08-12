import json
import logging
from django.http import JsonResponse
from .base import ImdbProxyBaseView
from curl_cffi import requests as cffi_requests 

logger = logging.getLogger(__name__)

import json
import logging
from django.http import JsonResponse
from .base import ImdbProxyBaseView
from curl_cffi import requests as cffi_requests 

logger = logging.getLogger(__name__)

class EpisodesView(ImdbProxyBaseView):
    def get(self, request):
        imdb_id = request.GET.get('id')
        season_number = request.GET.get('season', '1')
        
        if not imdb_id:
            return JsonResponse({'error': 'پارامتر id الزامی است'}, status=400)

        url = 'https://caching.graphql.imdb.com/'
        
        params = {
            'operationName': 'EpisodeRatings_SeasonDetail',
            'variables': json.dumps(
                {"id": imdb_id, "locale": "en-US", "seasons": [str(season_number)]},
                separators=(',', ':')
            ),
            'extensions': json.dumps({
                "persistedQuery": {
                    "sha256Hash": "5cd1a7aa5ba917bd6e519570375e6f3f570ad3503e6a9d202b1fa4cb5ae6a56d",
                    "version": 1
                }
            }, separators=(',', ':'))
        }

        try:
            request_headers = self.get_imdb_headers()
            
            response = cffi_requests.get(
                url, 
                headers=request_headers, 
                params=params, 
                impersonate="chrome110", 
                timeout=10
            )
            
            if response.status_code != 200:
                return JsonResponse({'error': f"IMDb API Error", 'details': response.text}, status=502)
                
            raw_edges = response.json().get('data', {}).get('title', {}).get('episodes', {}).get('episodes', {}).get('edges', [])
            
            # تمیز کردن دیتا برای کلاینت فلاتر
            formatted_episodes = []
            for edge in raw_edges:
                node = edge.get('node', {})
                episode_data = {
                    'id': node.get('id'),
                    'title': node.get('titleText', {}).get('text'),
                    'season_number': node.get('series', {}).get('displayableEpisodeNumber', {}).get('displayableSeason', {}).get('season'),
                    'episode_number': node.get('series', {}).get('displayableEpisodeNumber', {}).get('episodeNumber', {}).get('episodeNumber'),
                    'release_date': node.get('releaseDate', {}).get('displayableProperty', {}).get('value', {}).get('plainText'),
                    'plot': node.get('plot', {}).get('plotText', {}).get('plainText'),
                    'image_url': node.get('primaryImage', {}).get('url') if node.get('primaryImage') else None,
                }
                formatted_episodes.append(episode_data)
                
            return JsonResponse({'results': formatted_episodes}, status=200)
            
        except Exception as e:
            return JsonResponse({'error': str(e)}, status=502)