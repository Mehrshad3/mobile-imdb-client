from django.core.mail import send_mail
from .models import OTPRequest

class OTPService:
    @staticmethod
    def send_registration_otp(email):
        # ۱. تولید کد
        otp_code = OTPRequest.generate_otp()
        
        # ۲. ذخیره در دیتابیس
        OTPRequest.objects.update_or_create(
            email=email,
            defaults={'otp_code': otp_code}
        )
        
        # ۳. ارسال ایمیل
        send_mail(
            subject='کد تایید ثبت‌نام',
            message=f'کد تایید شما: {otp_code}',
            from_email='noreply@imdbtracker.com',
            recipient_list=[email],
        )