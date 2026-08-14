from django.contrib.auth.models import AbstractUser
from django.db import models

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