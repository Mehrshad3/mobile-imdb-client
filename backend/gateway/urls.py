from django.urls import path
from .views import (
    TrendingView,
    SearchView,
    AdvancedSearchView,
    EpisodesView,
    VideoStreamInfoView,
    NameSuggestionView
)

urlpatterns = [
    path('api/trending/', TrendingView.as_view(), name='api-trending'),
    path('api/search/', SearchView.as_view(), name='api-search'),
    path('api/episodes/', EpisodesView.as_view(), name='api-episodes'),
    path(
        'api/video/<str:video_id>/',
        VideoStreamInfoView.as_view(),
        name='video_info',
    ),
    path('api/suggest/name/', NameSuggestionView.as_view(), name='name_suggestion'),
    path('api/search/advanced/', AdvancedSearchView.as_view(), name='advanced-search')
]