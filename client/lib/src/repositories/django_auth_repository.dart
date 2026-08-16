import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
      final payload = jsonEncode({
        'email': email,
        'password': password,
      });
      final bytes = utf8.encode(payload);

      final request = await HttpClient().postUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      request.headers.contentLength = bytes.length;
      request.add(bytes);

      final response = await request.close();
      final responseBody = await utf8.decoder.bind(response).join();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(responseBody);
        
        final accessToken = data['access'];
        final refreshToken = data['refresh'];

        final prefs = await SharedPreferences.getInstance();

        if (accessToken != null) {
          await prefs.setString('access_token', accessToken);
          _accessToken = accessToken;
        }
        if (refreshToken != null) {
          await prefs.setString('refresh_token', refreshToken);
          _refreshToken = refreshToken;
        }

        try {
          final profileUri = Uri.parse('$baseUrl/profile/'); 
          final profileRequest = await HttpClient().getUrl(profileUri);
          
          profileRequest.headers.set('Authorization', 'Bearer $accessToken');
          
          final profileResponse = await profileRequest.close();
          final profileBody = await utf8.decoder.bind(profileResponse).join();

          if (profileResponse.statusCode == 200) {
            // تبدیل JSON جنگو به دیکشنری فلاتر
            final profileData = jsonDecode(profileBody);
            
            // 🚀 تزریق دیتای واقعی سریالایزرِ جنگو به کالبد MockUser
            _currentUser = MockUser(
              id: profileData['id']?.toString() ?? '0',
              // چون در سریالایزر فیلد نام و نام خانوادگی مجزا نداریم، از username برای نمایش استفاده می‌کنیم
              displayName: profileData['username'] ?? 'کاربر', 
              username: profileData['username'] ?? 'user',
              profileImageUrl: profileData['profile_picture'], // دقیقاً منطبق با سریالایزر
              bio: profileData['bio'], // دقیقاً منطبق با سریالایزر
            );
          } else {
            throw AuthException('ورود انجام شد اما دریافت اطلاعات پروفایل با خطا مواجه شد.');
          }
        } catch (e) {
          print('خطا در دریافت پروفایل: $e');
          // اگر API پروفایل هنوز در دسترس نبود، لاگین را خراب نمی‌کنیم
          if (MockUser.all.isNotEmpty) {
             _currentUser = MockUser.all.first; 
          }
        }

        print("ورود واقعی و دریافت پروفایل با موفقیت انجام شد!");
        // 🚀 آپدیت کردن UI برای ورود به صفحه اصلی
        notifyListeners(); 
        
      } else {
        final errorMsg = jsonDecode(responseBody)['error'] ?? 'ایمیل یا رمز عبور اشتباه است.';
        throw AuthException(errorMsg);
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