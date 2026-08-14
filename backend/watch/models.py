from django.db import models
from django.contrib.auth import get_user_model

User = get_user_model()

class UserTitle(models.Model):
    """مدل وضعیت تماشا و پیشرفت هر اثر برای کاربر"""
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


class UserReview(models.Model):
    """مدل واحد برای امتیازدهی (۱۳.۵)، ثبت نظر (۱۴.۵) و وضعیت اسپویل (۱۵.۵)"""
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='reviews')
    imdb_id = models.CharField(max_length=20, verbose_name='شناسه IMDb')
    
    # امتیاز کیفی از ۱ تا ۵ ستاره (اختیاری)
    score = models.PositiveIntegerField(
        choices=[(i, str(i)) for i in range(1, 6)], 
        blank=True, 
        null=True, 
        verbose_name='امتیاز'
    )
    
    # متن نظر (اختیاری - کاربر ممکن است فقط ستاره بدهد یا فقط متن بنویسد)
    text = models.TextField(blank=True, null=True, verbose_name='متن نظر')
    
    # مشخص کردن اسپویل بودن نظر
    is_spoiler = models.BooleanField(default=False, verbose_name='دارای اسپویل')
    
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        # هر کاربر برای هر اثر فقط می‌تواند یک رکوردِ نظر/امتیاز داشته باشد که قابل ویرایش است
        unique_together = ('user', 'imdb_id')

    def __str__(self):
        return f"{self.user.username} - {self.imdb_id} [Score: {self.score}]"

class UserFavorite(models.Model):
    """بخش ۱۶.۵: فهرست جداگانه برای علاقه‌مندی‌ها"""
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='favorites')
    imdb_id = models.CharField(max_length=20)
    title_type = models.CharField(max_length=10, choices=(('movie', 'فیلم'), ('tv', 'سریال')))
    title_name = models.CharField(max_length=255, blank=True)
    poster_url = models.URLField(blank=True, null=True)
    added_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('user', 'imdb_id')


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