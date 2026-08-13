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

User = get_user_model()

class RegisterView(generics.CreateAPIView):
    """ثبت‌نام کاربر جدید (بخش ۱.۵)"""
    queryset = User.objects.all()
    permission_classes = (AllowAny,)
    serializer_class = UserRegistrationSerializer

class ProfileView(generics.RetrieveUpdateAPIView):
    """مشاهده و ویرایش پروفایل کاربر لاگین شده (بخش ۴.۵)"""
    permission_classes = (IsAuthenticated,)
    serializer_class = UserProfileSerializer

    def get_object(self):
        # برگرداندن کاربری که توکن به او تعلق دارد
        return self.request.user


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