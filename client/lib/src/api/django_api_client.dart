import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../app_config.dart';

class DjangoApiClient {
  DjangoApiClient({HttpClient? httpClient, Duration? timeout})
      : _httpClient = httpClient ?? HttpClient(),
        timeout = timeout ?? const Duration(seconds: 10);

  // آدرس پایه جنگو (برای شبیه‌ساز اندروید 10.0.2.2 و برای iOS معمولاً localhost یا 127.0.0.1 است)
  static final Uri _baseUrl = Uri.parse('${AppConfig.watchBaseUrl}/');
  
  final HttpClient _httpClient;
  final Duration timeout;
  
  // توکن احراز هویت که بعد از لاگین کاربر اینجا ذخیره می‌شود
  String? _authToken;

  void setAuthToken(String token) {
    _authToken = token;
  }

  void clearAuthToken() {
    _authToken = null;
  }

  // --- متدهای مربوط به علاقه‌مندی‌ها (Favorites) ---

  Future<List<dynamic>> getFavorites() async {
    final uri = _baseUrl.resolve('watch/favorites/');
    return await _sendRequest('GET', uri);
  }

  Future<void> addFavorite(String imdbId, String titleType, String titleName) async {
    final uri = _baseUrl.resolve('watch/favorites/');
    await _sendRequest('POST', uri, body: {
      'imdb_id': imdbId,
      'title_type': titleType,
      'title_name': titleName,
    });
  }

  Future<void> removeFavorite(String imdbId) async {
    final uri = _baseUrl.resolve('watch/favorites/$imdbId/');
    await _sendRequest('DELETE', uri);
  }

  // --- متد سازنده درخواست‌های HTTP ---

  Future<dynamic> _sendRequest(String method, Uri uri, {Map<String, dynamic>? body}) async {
    try {
      final request = await _httpClient.openUrl(method, uri).timeout(timeout);
      
      // تنظیم هدرهای استاندارد و توکن احراز هویت
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'application/json');
      if (_authToken != null) {
        request.headers.set('Authorization', 'Bearer $_authToken');
      }

      // اضافه کردن بادی (برای متدهای POST و PATCH)
      if (body != null) {
        request.add(utf8.encode(jsonEncode(body)));
      }

      final response = await request.close().timeout(timeout);
      final responseText = await utf8.decoder.bind(response).join().timeout(timeout);

      // در صورت موفقیت (مثل 200 یا 201)
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (responseText.isEmpty) return null;
        return jsonDecode(responseText);
      } else {
        throw Exception('Django API Error: ${response.statusCode} - $responseText');
      }
    } on SocketException catch (e) {
      throw Exception('Network error while connecting to Django: ${e.message}');
    }
  }
}