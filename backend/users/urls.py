from django.urls import path
from rest_framework_simplejwt.views import TokenObtainPairView, TokenBlacklistView
from . import views

urlpatterns = [
    # ثبت‌نام
    path('register/', views.RegisterView.as_view(), name='register'),
    
    # ورود و خروج (بخش ۲.۵)
    path('login/', TokenObtainPairView.as_view(), name='token_obtain_pair'), # دریافت توکن
    path('logout/', TokenBlacklistView.as_view(), name='token_blacklist'), # ابطال توکن
    
    # پروفایل (بخش ۴.۵)
    path('profile/', views.ProfileView.as_view(), name='profile'),
    
    # بازیابی رمز عبور (بخش ۳.۵)
    path('password-reset/', views.PasswordResetRequestView.as_view(), name='password_reset_request'),
    path('password-reset/confirm/', views.PasswordResetConfirmView.as_view(), name='password_reset_confirm'),
]