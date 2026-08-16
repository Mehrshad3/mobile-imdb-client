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
    final uri = Uri.parse('$baseUrl/login/'); // یا مسیر مربوط به لاگین و توکن
    
    try {
      // ۱. دیتا را به بایت تبدیل می‌کنیم
      final payload = jsonEncode({
        'email': email,
        'password': password,
      });
      final bytes = utf8.encode(payload);

      final request = await HttpClient().postUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      
      // 🚀 ۲. ست کردن طول دیتا برای رفع خطای Syntax در بک‌اند
      request.headers.contentLength = bytes.length;
      
      // ۳. ارسال دیتا
      request.add(bytes);

      final response = await request.close();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // لاگین موفق (ذخیره توکن و غیره)
        print("لاگین با موفقیت انجام شد!");
      } else {
        throw AuthException('ایمیل یا رمز عبور اشتباه است.');
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('خطا در ارتباط با سرور هنگام لاگین.');
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
    _pendingRegistration = draft;
    final uri = Uri.parse('$baseUrl/otp/request/'); 
    
    try {
      // ۱. اول دیتا را به صورت بایت آماده می‌کنیم
      final payload = jsonEncode({'email': draft.email});
      final bytes = utf8.encode(payload);

      final request = await HttpClient().postUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      
      // 🚀 ۲. این خط کلیدی است! به جنگو می‌گوییم سایز دقیق دیتا چقدر است
      request.headers.contentLength = bytes.length;
      
      // ۳. حالا دیتا را می‌فرستیم
      request.add(bytes);

      final response = await request.close();
      if (response.statusCode >= 400) {
        final body = await utf8.decoder.bind(response).join();
        final errorMsg = jsonDecode(body)['error'] ?? 'خطا در درخواست کد';
        throw AuthException(errorMsg);
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('خطای شبکه. مطمئن شو سرور بک‌اند روشنه.');
    }
  }

  Future<void> confirmRegistrationOtp({required String email, required String otp}) async {
    if (_pendingRegistration == null || _pendingRegistration!.email != email) {
      throw const AuthException('اطلاعات ثبت‌نام پیدا نشد. دوباره تلاش کن.');
    }

    final uri = Uri.parse('$baseUrl/register/'); 
    try {
      // ۱. آماده‌سازی دیتا
      final payload = jsonEncode({
        'email': _pendingRegistration!.email,
        'username': _pendingRegistration!.username,
        'password': _pendingRegistration!.password,
        'otp': otp.trim(), 
      });
      final bytes = utf8.encode(payload);

      final request = await HttpClient().postUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      
      // 🚀 ۲. ست کردن طول دیتا برای جلوگیری از خالی رسیدن به جنگو
      request.headers.contentLength = bytes.length;
      
      request.add(bytes);

      final response = await request.close();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await signIn(email: _pendingRegistration!.email, password: _pendingRegistration!.password);
        _pendingRegistration = null;
      } else {
        final body = await utf8.decoder.bind(response).join();
        final errorMsg = jsonDecode(body)['error'] ?? 'کد اشتباه است یا منقضی شده';
        throw AuthException(errorMsg);
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('خطا در ارتباط با سرور.');
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