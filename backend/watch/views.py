from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.permissions import IsAuthenticated
from .models import UserTitle, WatchedEpisode, CustomPlaylist, PlaylistItem
from .serializers import UserTitleSerializer, CustomPlaylistSerializer, PlaylistItemSerializer

# --- بخش مدیریت وضعیت تماشا (UserTitle) ---

class WatchlistView(generics.ListCreateAPIView):
    """مدیریت آثار کاربر (فیلتر بر اساس status یا is_favorite)"""
    serializer_class = UserTitleSerializer
    permission_classes = (IsAuthenticated,)

    def get_queryset(self):
        queryset = UserTitle.objects.filter(user=self.request.user)
        status_filter = self.request.query_params.get('status')
        favorite_filter = self.request.query_params.get('is_favorite')
        
        if status_filter:
            queryset = queryset.filter(status=status_filter)
        if favorite_filter and favorite_filter.lower() == 'true':
            queryset = queryset.filter(is_favorite=True)
            
        return queryset.order_by('-updated_at')

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)


class WatchItemDetailView(generics.RetrieveUpdateDestroyAPIView):
    """بروزرسانی یا حذف یک اثر از وضعیت تماشا بر اساس imdb_id"""
    serializer_class = UserTitleSerializer
    permission_classes = (IsAuthenticated,)
    lookup_field = 'imdb_id'
    lookup_url_kwarg = 'imdb_id'

    def get_queryset(self):
        return UserTitle.objects.filter(user=self.request.user)


class ToggleEpisodeView(APIView):
    """تیک زدن یا برداشتن تیک قسمت‌های سریال"""
    permission_classes = (IsAuthenticated,)

    def post(self, request, imdb_id):
        season = request.data.get('season_number')
        episode = request.data.get('episode_number')

        if season is None or episode is None:
            return Response({'error': 'شماره فصل و قسمت الزامی است.'}, status=status.HTTP_400_BAD_REQUEST)

        try:
            user_title = UserTitle.objects.get(user=request.user, imdb_id=imdb_id, title_type='tv')
        except UserTitle.DoesNotExist:
            return Response({'error': 'سریال در فهرست تماشای شما نیست.'}, status=status.HTTP_404_NOT_FOUND)

        watched_ep, created = WatchedEpisode.objects.get_or_create(
            user_title=user_title,
            season_number=season,
            episode_number=episode
        )

        if not created:
            watched_ep.delete()
            message = 'علامت مشاهده برداشته شد.'
        else:
            message = 'قسمت به عنوان مشاهده‌شده ثبت شد.'

        user_title.save()
        return Response({'message': message})


# --- بخش مدیریت فهرست‌های سفارشی (Playlists) ---

class PlaylistListCreateView(generics.ListCreateAPIView):
    """مشاهده یا ساخت فهرست‌های سفارشی (مثل علمی، خانوادگی)"""
    serializer_class = CustomPlaylistSerializer
    permission_classes = (IsAuthenticated,)

    def get_queryset(self):
        return CustomPlaylist.objects.filter(user=self.request.user).order_by('-created_at')

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)


class PlaylistDetailView(generics.RetrieveDestroyAPIView):
    """مشاهده یا حذف کامل یک فهرست سفارشی"""
    serializer_class = CustomPlaylistSerializer
    permission_classes = (IsAuthenticated,)

    def get_queryset(self):
        return CustomPlaylist.objects.filter(user=self.request.user)


class PlaylistItemAddView(generics.CreateAPIView):
    """اضافه کردن یک اثر (UserTitle) به فهرست سفارشی"""
    serializer_class = PlaylistItemSerializer
    permission_classes = (IsAuthenticated,)

    def perform_create(self, serializer):
        playlist_id = self.kwargs.get('playlist_id')
        playlist = CustomPlaylist.objects.get(id=playlist_id, user=self.request.user)
        serializer.save(playlist=playlist)