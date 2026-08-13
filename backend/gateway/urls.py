from django.urls import path
from .views import (
    SearchView,
    AdvancedSearchView,
    EpisodesView,
    VideoStreamInfoView,
    NameSuggestionView
)
from .views import discover

urlpatterns = [
    path('api/search/', SearchView.as_view(), name='api-search'),
    path('api/episodes/', EpisodesView.as_view(), name='api-episodes'),
    path(
        'api/video/<str:video_id>/',
        VideoStreamInfoView.as_view(),
        name='video_info',
    ),
    path('api/suggest/name/', NameSuggestionView.as_view(), name='name_suggestion'),
    path('api/search/advanced/', AdvancedSearchView.as_view(), name='advanced-search'),
    path('api/discover/movies/popular/', discover.PopularMoviesView.as_view(), name='popular_movies'),
    path('api/discover/tv/popular/', discover.PopularTVShowsView.as_view(), name='popular_tv'),
    path('api/discover/new/', discover.NewReleasesView.as_view(), name='new_releases'),
    path('api/discover/top-rated/', discover.TopRatedView.as_view(), name='top_rated'),
    path('api/discover/recommended/', discover.RecommendedView.as_view(), name='recommended'),
]