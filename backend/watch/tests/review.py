from rest_framework import generics, status
from rest_framework.response import Response
from django.contrib.auth import get_user_model

from users.serializers import UserProfileSerializer

# ایمپورت مدل‌ها و سریالایزرهای اپلیکیشن watch
from watch.models import UserTitle, UserFavorite
from watch.serializers import UserFavoriteSerializer

User = get_user_model()

class ProfileView(generics.RetrieveUpdateAPIView):
    """
    پایانه‌ی پروفایل کاربر:
    - نمایش اطلاعات کاربر به همراه تعداد فیلم/سریال‌های دیده‌شده و لیست علاقه‌مندی‌ها
    - امکان ویرایش پروفایل (بیو و عکس) با متد PATCH
    """
    permission_classes = (IsAuthenticated,)
    serializer_class = UserProfileSerializer

    def get_object(self):
        return self.request.user

    def retrieve(self, request, *args, **kwargs):
        instance = self.get_object()
        
        # ۱. محاسبه پویای تعداد فیلم‌ها و سریال‌های مشاهده شده از UserTitle
        instance._watched_movies_count = UserTitle.objects.filter(
            user=instance, title_type='movie', status='completed'
        ).count()

        instance._watched_shows_count = UserTitle.objects.filter(
            user=instance, title_type='tv', status='completed'
        ).count()

        # ۲. استخراج آثار مورد علاقه از جدول مستقلِ UserFavorite (بخش ۱۶.۵)
        favorite_titles = UserFavorite.objects.filter(user=instance)
        instance._favorite_items = UserFavoriteSerializer(favorite_titles, many=True).data

        serializer = self.get_serializer(instance)
        return Response(serializer.data, status=status.HTTP_200_OK)