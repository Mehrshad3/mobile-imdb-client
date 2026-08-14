from rest_framework import serializers
from .models import UserTitle, WatchedEpisode, CustomPlaylist, PlaylistItem, UserReview, UserFavorite

class WatchedEpisodeSerializer(serializers.ModelSerializer):
    class Meta:
        model = WatchedEpisode
        fields = ('season_number', 'episode_number', 'watched_at')

class UserTitleSerializer(serializers.ModelSerializer):
    watched_episodes = WatchedEpisodeSerializer(many=True, read_only=True)
    watched_count = serializers.SerializerMethodField()
    remaining_count = serializers.SerializerMethodField()
    progress_percentage = serializers.SerializerMethodField()
    is_favorite = serializers.SerializerMethodField()

    class Meta:
        model = UserTitle
        fields = (
            'id', 'imdb_id', 'title_type', 'title_name', 'poster_url', 
            'total_episodes', 'status', 'is_favorite', 
            'watched_count', 'remaining_count', 'progress_percentage',
            'watched_episodes', 'updated_at'
        )
        read_only_fields = ('id', 'updated_at')

    def get_is_favorite(self, obj):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            return UserFavorite.objects.filter(user=request.user, imdb_id=obj.imdb_id).exists()
        return False

    def get_watched_count(self, obj):
        if obj.title_type == 'movie':
            return 1 if obj.status == 'completed' else 0
        return obj.watched_episodes.count()

    def get_remaining_count(self, obj):
        if obj.title_type == 'movie':
            return 0 if obj.status == 'completed' else 1
        return max(0, obj.total_episodes - self.get_watched_count(obj))

    def get_progress_percentage(self, obj):
        if obj.title_type == 'movie':
            return 100.0 if obj.status == 'completed' else 0.0
        if obj.total_episodes == 0:
            return 0.0
        return round((self.get_watched_count(obj) / obj.total_episodes) * 100, 1)


class UserFavoriteSerializer(serializers.ModelSerializer):
    """سریالایزر برای لیست جداگانه علاقه‌مندی‌ها (بخش ۱۶.۵)"""
    class Meta:
        model = UserFavorite
        fields = ('id', 'imdb_id', 'title_type', 'title_name', 'poster_url', 'added_at')
        read_only_fields = ('id', 'added_at')


class PlaylistItemSerializer(serializers.ModelSerializer):
    user_title_details = UserTitleSerializer(source='user_title', read_only=True)

    class Meta:
        model = PlaylistItem
        fields = ('id', 'user_title', 'user_title_details', 'added_at')
        read_only_fields = ('id', 'added_at')


class CustomPlaylistSerializer(serializers.ModelSerializer):
    items = PlaylistItemSerializer(many=True, read_only=True)
    items_count = serializers.SerializerMethodField()

    class Meta:
        model = CustomPlaylist
        fields = ('id', 'name', 'description', 'items_count', 'items', 'created_at')
        read_only_fields = ('id', 'created_at')

    def get_items_count(self, obj):
        return obj.items.count()


class UserReviewSerializer(serializers.ModelSerializer):
    """سریالایزر واحد برای امتیازدهی و نظرات (بخش‌های ۱۳.۵، ۱۴.۵ و ۱۵.۵)"""
    username = serializers.ReadOnlyField(source='user.username')
    profile_picture = serializers.ImageField(source='user.profile_picture', read_only=True)

    class Meta:
        model = UserReview
        fields = (
            'id', 'imdb_id', 'username', 'profile_picture', 
            'score', 'text', 'is_spoiler', 'created_at', 'updated_at'
        )
        read_only_fields = ('id', 'created_at', 'updated_at')