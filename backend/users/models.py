import random
from datetime import timedelta

from django.contrib.auth.models import AbstractUser
from django.db import models
from django.utils import timezone

class CustomUser(AbstractUser):
    # لاگین با ایمیل (جلوگیری از ایمیل تکراری)
    email = models.EmailField(unique=True, verbose_name='آدرس ایمیل')
    
    # فیلدهای اختیاری پروفایل
    profile_picture = models.ImageField(upload_to='profiles/', blank=True, null=True)
    bio = models.TextField(blank=True, null=True, verbose_name='توضیحات کوتاه')

    # تنظیم ایمیل به عنوان فیلد اصلی ورود
    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = ['username', 'first_name', 'last_name']

    def __str__(self):
        return self.email


class OTPRequest(models.Model):
    email = models.EmailField(unique=True)
    otp_code = models.CharField(max_length=6)
    created_at = models.DateTimeField(auto_now=True)

    def is_valid(self):
        # کد فقط تا ۵ دقیقه معتبر است
        return self.created_at >= timezone.now() - timedelta(minutes=5)

    @classmethod
    def generate_otp(cls):
        # تولید یک عدد تصادفی ۶ رقمی
        return str(random.randint(100000, 999999))

    def __str__(self):
        return f"{self.email} - {self.otp_code}"