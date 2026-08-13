from django.urls import path
from . import views

urlpatterns = [
    # وضعیت‌های تماشا و تیک قسمت‌ها
    path('watchlist/', views.WatchlistView.as_view(), name='watchlist-list-create'),
    path('watchlist/<str:imdb_id>/', views.WatchItemDetailView.as_view(), name='watchlist-detail'),
    path('watchlist/<str:imdb_id>/episodes/toggle/', views.ToggleEpisodeView.as_view(), name='toggle-episode'),
    
    # فهرست‌های سفارشی (Playlists)
    path('playlists/', views.PlaylistListCreateView.as_view(), name='playlist-list-create'),
    path('playlists/<int:pk>/', views.PlaylistDetailView.as_view(), name='playlist-detail'),
    path('playlists/<int:playlist_id>/items/', views.PlaylistItemAddView.as_view(), name='playlist-item-add'),
]