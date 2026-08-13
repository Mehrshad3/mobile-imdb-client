from django.db import models
from django.contrib.auth import get_user_model

User = get_user_model()

class UserTitle(models.Model):
    """مدل مستقل برای نگهداری وضعیت تماشا، پیشرفت و اطلاعات هر فیلم/سریال برای کاربر"""
    STATUS_CHOICES = (
        ('plan_to_watch', 'قصد دارم تماشا کنم'),
        ('watching', 'در حال تماشا'),
        ('completed', 'مشاهده‌شده'),
        ('paused', 'متوقف‌شده'),
        ('dropped', 'رهاشده'),
    )

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='user_titles')
    imdb_id = models.CharField(max_length=20, verbose_name='شناسه IMDb')
    title_type = models.CharField(max_length=10, choices=(('movie', 'فیلم'), ('tv', 'سریال')))
    
    # اطلاعات کَش شده اثر
    title_name = models.CharField(max_length=255, blank=True)
    poster_url = models.URLField(blank=True, null=True)
    total_episodes = models.PositiveIntegerField(default=1, verbose_name='کل قسمت‌ها')
    
    # وضعیت تماشا و علاقه‌مندی (کاملاً مستقل)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='plan_to_watch')
    is_favorite = models.BooleanField(default=False, verbose_name='مورد علاقه')
    
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('user', 'imdb_id')

    def __str__(self):
        return f"{self.user.username} - {self.imdb_id} [{self.status}]"


class WatchedEpisode(models.Model):
    """مدل ذخیره قسمت‌های تیک‌خورده برای سریال‌ها"""
    user_title = models.ForeignKey(UserTitle, on_delete=models.CASCADE, related_name='watched_episodes')
    season_number = models.PositiveIntegerField()
    episode_number = models.PositiveIntegerField()
    watched_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('user_title', 'season_number', 'episode_number')


class CustomPlaylist(models.Model):
    """فهرست‌های سفارشی و سلیقه‌ای کاربر (مثل: علمی، خانوادگی، بعداً تماشا میکنم)"""
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='playlists')
    name = models.CharField(max_length=100, verbose_name='نام فهرست')
    description = models.TextField(blank=True, null=True, verbose_name='توضیحات')
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.user.username} - Playlist: {self.name}"


class PlaylistItem(models.Model):
    """آیتم‌های داخل فهرست سفارشی (فقط شامل ارجاع به اثر است و وضعیت تماشا ندارد)"""
    playlist = models.ForeignKey(CustomPlaylist, on_delete=models.CASCADE, related_name='items')
    # هر آیتم در پلی‌لیست به یک UserTitle وصل می‌شود
    user_title = models.ForeignKey(UserTitle, on_delete=models.CASCADE, related_name='playlist_items')
    added_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('playlist', 'user_title')