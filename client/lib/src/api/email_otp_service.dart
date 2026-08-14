import 'dart:convert';
import 'dart:io';
import 'dart:math';

class OtpTicket {
  const OtpTicket({
    required this.code,
    required this.generatedAt,
    required this.expiresAt,
  });

  final String code;
  final DateTime generatedAt;
  final DateTime expiresAt;
}

class EmailOtpService {
  static const _serviceId = 'service_id3g13k';
  static const _templateId = 'template_xx7mvu5';
  static const _publicKey = 'L0mNOLrRQymIph10n';
  static final Uri _endpoint = Uri.parse(
    'https://api.emailjs.com/api/v1.0/email/send',
  );

  const EmailOtpService();

  Future<OtpTicket> sendOtp(String receiverEmail) async {
    final code = (100000 + Random.secure().nextInt(900000)).toString();
    final generatedAt = DateTime.now();
    final expiresAt = generatedAt.add(const Duration(minutes: 15));
    final body = jsonEncode({
      'service_id': _serviceId,
      'template_id': _templateId,
      'user_id': _publicKey,
      'template_params': {
        'email': receiverEmail.trim(),
        'passcode': code,
        'time': '15 minutes',
      },
    });

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(_endpoint);
      request.headers.contentType = ContentType.json;
      request.write(body);
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final responseText = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        throw OtpSendException(
          'ارسال ایمیل ناموفق بود. کد ${response.statusCode}: $responseText',
        );
      }
      return OtpTicket(
        code: code,
        generatedAt: generatedAt,
        expiresAt: expiresAt,
      );
    } on OtpSendException {
      rethrow;
    } catch (error) {
      throw OtpSendException('خطای شبکه هنگام ارسال ایمیل: $error');
    } finally {
      client.close(force: true);
    }
  }
}

class OtpSendException implements Exception {
  const OtpSendException(this.message);

  final String message;

  @override
  String toString() => message;
}
