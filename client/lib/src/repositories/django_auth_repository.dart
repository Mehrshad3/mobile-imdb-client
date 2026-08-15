import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/mock_user.dart';
import '../models/user_account.dart';
import '../../app_config.dart';

// --- کلاس‌های کمکی که UI به آن‌ها وابستگی دارد ---

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

// --- کلاس اصلی Repository ---

class DjangoAuthRepository extends ChangeNotifier {
  // آدرس پایه جنگو (برای تست روی گوشی، IP لپ‌تاپ خودت را جایگزین کن)
  final String baseUrl = AppConfig.usersBaseUrl;
  
  MockUser? _currentUser;
  String? _accessToken;
  String? _refreshToken;
  bool _loaded = true;

  // متغیری برای ذخیره موقت اطلاعات ثبت‌نام تا زمانی که کاربر کد OTP را وارد کند
  RegistrationDraft? _pendingRegistration;

  MockUser? get currentUser => _currentUser;
  bool get isGuest => _currentUser == null;
  bool get loaded => _loaded;

  // متدهای سازگاری با UI قبلی
  Future<void> load() async {}
  Future<List<MockUser>> localUsers() async => MockUser.all;

  // ۱. ورود واقعی با بک‌اند جنگو
  Future<void> signIn({required String email, required String password}) async {
    final uri = Uri.parse('$baseUrl/login/');
    try {
      final request = await HttpClient().postUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      request.add(utf8.encode(jsonEncode({'email': email, 'password': password})));
      
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(body);
        _accessToken = data['access'];
        _refreshToken = data['refresh'];
        
        // ساخت یوزر موقت برای نمایش در UI
        _currentUser = MockUser(
          id: 'django_user',
          displayName: email.split('@').first,
          username: email.split('@').first,
          email: email,
          createdAt: DateTime.now(),
        );
        notifyListeners();
      } else {
        throw const AuthException('ایمیل یا رمز عبور اشتباه است.');
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('خطا در ارتباط با سرور: $e');
    }
  }

  // ۲. ماک کردن لاگین با اکانت‌های آماده در UI
  Future<void> login(MockUser user) async {
    _currentUser = user;
    _accessToken = 'mock_token';
    notifyListeners();
  }

  // ۳. مرحله اول ثبت‌نام: ماک کردن ارسال OTP
  Future<void> requestRegistrationOtp(RegistrationDraft draft) async {
    // اطلاعات فرم را موقتاً در رم نگه می‌داریم
    _pendingRegistration = draft;
    // فرض می‌کنیم ایمیل با موفقیت ارسال شده است
    debugPrint('MOCK REGISTRATION OTP SENT: 123456');
  }

  // ۴. مرحله دوم ثبت‌نام: تایید OTP ماک شده و ارسال ریکوئست واقعی به جنگو
  Future<void> confirmRegistrationOtp({required String email, required String otp}) async {
    if (otp.trim() != '123456') {
      throw const AuthException('کد تایید نادرست است. (کد تست: 123456)');
    }
    if (_pendingRegistration == null || _pendingRegistration!.email != email) {
      throw const AuthException('اطلاعات ثبت‌نام پیدا نشد. دوباره تلاش کن.');
    }

    final uri = Uri.parse('$baseUrl/register/');
    try {
      final request = await HttpClient().postUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      // ارسال دیتای اصلی به بک‌اند
      request.add(utf8.encode(jsonEncode({
        'email': _pendingRegistration!.email,
        'username': _pendingRegistration!.username,
        'password': _pendingRegistration!.password,
      })));

      final response = await request.close();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // بعد از ثبت‌نام موفق در بک‌اند، خودکار لاگین می‌کنیم
        await signIn(email: _pendingRegistration!.email, password: _pendingRegistration!.password);
        _pendingRegistration = null; // پاکسازی
      } else {
        final body = await utf8.decoder.bind(response).join();
        throw AuthException('خطای بک‌اند در ثبت‌نام: $body');
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('خطا در ارتباط با سرور: $e');
    }
  }

  // ۵. درخواست بازیابی رمز: ارسال به پایانه‌های جنگو (حتی اگر ارور بدهد)
  Future<void> requestPasswordResetOtp(String email) async {
    final uri = Uri.parse('$baseUrl/password-reset/');
    try {
      final request = await HttpClient().postUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      request.add(utf8.encode(jsonEncode({'email': email})));
      await request.close(); // اهمیتی به پاسخ نمی‌دهیم
    } catch (e) {
      debugPrint('Reset Network Error (Ignored): $e');
    }
    debugPrint('MOCK RESET OTP SENT: 123456');
  }

  // ۶. تایید و تغییر رمز جدید: ارسال به پایانه‌های جنگو
  Future<void> resetPassword({required String email, required String otp, required String newPassword}) async {
    if (otp.trim() != '123456') {
      throw const AuthException('کد بازیابی نادرست است. (کد تست: 123456)');
    }
    
    final uri = Uri.parse('$baseUrl/password-reset/confirm/');
    try {
      final request = await HttpClient().postUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      request.add(utf8.encode(jsonEncode({
        'email': email,
        'new_password': newPassword,
      })));
      
      final response = await request.close();
      if (response.statusCode >= 400) {
        final body = await utf8.decoder.bind(response).join();
        throw AuthException('بک‌اند هنوز کامل نیست: $body');
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('خطا در ارتباط با سرور: $e');
    }
  }

  // ۷. خروج
  Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    _currentUser = null;
    notifyListeners();
  }
}