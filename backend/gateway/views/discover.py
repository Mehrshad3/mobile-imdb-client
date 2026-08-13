import random
from datetime import datetime, timedelta

from .suggestions import AdvancedSearchView 

class PopularMoviesView(AdvancedSearchView):
    """۱. نمایش فیلم‌های محبوب"""
    def get(self, request, *args, **kwargs):
        # کپی کردن ریکوئست برای امکان ویرایش پارامترها
        request.GET = request.GET.copy()
        
        # تزریق پارامترهای فیلتر فیلم
        request.GET['type'] = 'movie'
        request.GET.setdefault('sort_by', 'POPULARITY')
        
        # پاس دادن ریکوئستِ تغییریافته به کلاس پدر
        return super().get(request, *args, **kwargs)


class PopularTVShowsView(AdvancedSearchView):
    """۲. نمایش سریال‌های محبوب"""
    def get(self, request, *args, **kwargs):
        request.GET = request.GET.copy()
        
        request.GET['type'] = 'tvSeries,tvMiniSeries'
        request.GET.setdefault('sort_by', 'POPULARITY')
        
        return super().get(request, *args, **kwargs)


class NewReleasesView(AdvancedSearchView):
    """۳. نمایش آثار جدید (منتشر شده در ۳۰ روز اخیر)"""
    def get(self, request, *args, **kwargs):
        request.GET = request.GET.copy()
        
        # محاسبه تاریخ امروز و ۳۰ روز پیش
        today = datetime.now()
        last_month = today - timedelta(days=30)
        
        request.GET['start_date'] = last_month.strftime('%Y-%m-%d')
        request.GET['end_date'] = today.strftime('%Y-%m-%d')
        request.GET.setdefault('sort_by', 'POPULARITY')
        
        return super().get(request, *args, **kwargs)


class TopRatedView(AdvancedSearchView):
    """۴. نمایش آثار دارای امتیاز بالا (برترین‌های تاریخ)"""
    def get(self, request, *args, **kwargs):
        request.GET = request.GET.copy()
        
        # تزریق پارامترهای امتیازدهی
        request.GET['min_rating'] = '8.0'
        request.GET['sort_by'] = 'USER_RATING'
        request.GET['sort_order'] = 'DESC'
        
        return super().get(request, *args, **kwargs)


class RecommendedView(AdvancedSearchView):
    """۵. فیلم‌ها و سریال‌های پیشنهادی"""
    def get(self, request, *args, **kwargs):
        request.GET = request.GET.copy()
        
        # از آنجایی که اپلیکیشن کاربرِ لاگین‌شده ندارد که سلیقه‌اش را بدانیم،
        # بهترین ترفند مهندسی این است که یک ژانر محبوب را به صورت تصادفی انتخاب کنیم
        # تا کاربر هر بار صفحه را باز می‌کند با پیشنهادهای جدیدی روبه‌رو شود.
        popular_genres = ['Action', 'Sci-Fi', 'Mystery', 'Thriller', 'Comedy', 'Crime']
        selected_genre = random.choice(popular_genres)
        
        request.GET['genre'] = selected_genre
        request.GET.setdefault('sort_by', 'POPULARITY')
        
        return super().get(request, *args, **kwargs)