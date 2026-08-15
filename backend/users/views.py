from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework.views import APIView
from django.contrib.auth import get_user_model
from django.contrib.auth.tokens import default_token_generator
from django.utils.http import urlsafe_base64_encode, urlsafe_base64_decode
from django.utils.encoding import force_bytes, force_str
from django.core.mail import send_mail

from .serializers import UserRegistrationSerializer, UserProfileSerializer
from .services import OTPRequest, OTPService

from watch.models import UserTitle, UserFavorite
from watch.serializers import UserFavoriteSerializer

User = get_user_model()


class RequestOTPView(APIView):
    """
    یک پایانه‌ی عمومی برای درخواست ارسال کد یک‌بار مصرف
    """
    def post(self, request):
        email = request.data.get('email')
        
        if not email:
            return Response({'error': 'ایمیل الزامی است.'}, status=status.HTTP_400_BAD_REQUEST)

        # اگر بخواهی این پایانه کاملاً عمومی باشد (مثلاً برای بازیابی رمز هم کار کند)،
        # می‌توانی چک کردنِ "تکراری بودن ایمیل" را به فرانت‌اند یا لایه‌های دیگر بسپاری، 
        # اما فعلاً برای سادگیِ ثبت‌نام، همین‌جا چک می‌کنیم:
        if User.objects.filter(email=email).exists():
            return Response({'error': 'این ایمیل قبلاً در سیستم ثبت شده است.'}, status=status.HTTP_400_BAD_REQUEST)

        # ارسال کد
        OTPService.send_registration_otp(email)

        return Response({'message': 'کد تایید با موفقیت ارسال شد.'}, status=status.HTTP_200_OK)


class RegisterView(APIView):
    """
    پایانه‌ی اصلی ثبت‌نام (که حالا در دل خودش OTP را هم چک می‌کند)
    """
    def post(self, request):
        email = request.data.get('email')
        otp = request.data.get('otp')
        username = request.data.get('username')
        password = request.data.get('password')

        if not all([email, otp, username, password]):
            return Response({'error': 'تمام فیلدها (ایمیل، کد، نام کاربری، رمز عبور) الزامی هستند.'}, status=status.HTTP_400_BAD_REQUEST)

        try:
            otp_req = OTPRequest.objects.get(email=email)
        except OTPRequest.DoesNotExist:
            return Response({'error': 'کد تاییدی یافت نشد.'}, status=status.HTTP_404_NOT_FOUND)

        if not otp_req.is_valid():
            return Response({'error': 'کد تایید منقضی شده است.'}, status=status.HTTP_400_BAD_REQUEST)

        if otp_req.otp_code != str(otp).strip():
            return Response({'error': 'کد تایید اشتباه است.'}, status=status.HTTP_400_BAD_REQUEST)

        if User.objects.filter(username=username).exists():
            return Response({'error': 'این نام کاربری قبلاً گرفته شده است.'}, status=status.HTTP_400_BAD_REQUEST)

        # ساخت کاربر
        user = User.objects.create_user(username=username, email=email, password=password)
        otp_req.delete()

        return Response({'message': 'ثبت‌نام با موفقیت انجام شد.'}, status=status.HTTP_201_CREATED)


class ProfileView(generics.RetrieveUpdateAPIView):
    """
    پایانه‌ی پروفایل کاربر:
    - نمایش اطلاعات کاربر به همراه تعداد فیلم/سریال‌های دیده‌شده و لیست علاقه‌مندی‌ها
    - امکان ویرایش پروفایل (مثل بیو و عکس پروفایل) با متد PATCH
    """
    permission_classes = (IsAuthenticated,)
    serializer_class = UserProfileSerializer

    def get_object(self):
        return self.request.user

    def retrieve(self, request, *args, **kwargs):
        # دریافت اطلاعات پیش‌فرض کاربر (از طریق سریالایزر اصلی پروفایل)
        instance = self.get_object()
        serializer = self.get_serializer(instance)
        data = serializer.data
        
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

        return Response(data, status=status.HTTP_200_OK)

class PasswordResetRequestView(APIView):
    """درخواست بازیابی رمز عبور - ارسال ایمیل (بخش ۳.۵)"""
    permission_classes = (AllowAny,)

    def post(self, request):
        email = request.data.get('email')
        try:
            user = User.objects.get(email=email)
            token = default_token_generator.make_token(user)
            uid = urlsafe_base64_encode(force_bytes(user.pk))
            
            # در حالت واقعی، این لینک به صفحه‌ای در اپلیکیشن فلاتر شما اشاره می‌کند
            reset_link = f"http://your-app-domain.com/reset-password/{uid}/{token}/"
            
            send_mail(
                subject='بازیابی رمز عبور',
                message=f'برای تغییر رمز عبور روی لینک زیر کلیک کنید:\n{reset_link}',
                from_email='noreply@yourdomain.com',
                recipient_list=[user.email],
            )
            return Response({'message': 'ایمیل بازیابی ارسال شد.'}, status=status.HTTP_200_OK)
        except User.DoesNotExist:
            return Response({'error': 'کاربری با این ایمیل یافت نشد.'}, status=status.HTTP_404_NOT_FOUND)

class PasswordResetConfirmView(APIView):
    """تایید و تنظیم رمز عبور جدید"""
    permission_classes = (AllowAny,)

    def post(self, request):
        uidb64 = request.data.get('uid')
        token = request.data.get('token')
        new_password = request.data.get('new_password')

        try:
            uid = force_str(urlsafe_base64_decode(uidb64))
            user = User.objects.get(pk=uid)
            
            if default_token_generator.check_token(user, token):
                user.set_password(new_password)
                user.save()
                return Response({'message': 'رمز عبور با موفقیت تغییر کرد.'})
            return Response({'error': 'توکن نامعتبر یا منقضی شده است.'}, status=status.HTTP_400_BAD_REQUEST)
        except Exception:
            return Response({'error': 'خطایی در پردازش اطلاعات رخ داد.'}, status=status.HTTP_400_BAD_REQUEST)