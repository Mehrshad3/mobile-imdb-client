import 'dart:math';

class PasswordTools {
  PasswordTools._();

  static String? validate({
    required String password,
    required String username,
    required String email,
  }) {
    final normalized = password.trim();
    if (normalized.length < 8) {
      return 'رمز عبور باید حداقل ۸ کاراکتر باشد.';
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(normalized) ||
        !RegExp(r'\d').hasMatch(normalized)) {
      return 'رمز عبور باید ترکیبی از حرف و عدد باشد.';
    }
    final lower = normalized.toLowerCase();
    if (lower == 'password' ||
        lower == '12345678' ||
        lower.contains('123456') ||
        lower.contains('qwerty')) {
      return 'رمز عبور بیش از حد ساده است.';
    }
    if (username.trim().isNotEmpty &&
        lower.contains(username.trim().toLowerCase())) {
      return 'رمز عبور نباید شامل نام کاربری باشد.';
    }
    final emailName = email.split('@').first.trim().toLowerCase();
    if (emailName.isNotEmpty && lower.contains(emailName)) {
      return 'رمز عبور نباید شامل بخش اصلی ایمیل باشد.';
    }
    return null;
  }

  static String randomToken({int bytes = 24}) {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < bytes; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static String hashPassword(String password, String salt) {
    var hash = _fnv64('$salt:$password');
    for (var i = 0; i < 4096; i++) {
      hash = _fnv64('$hash:$salt:$password');
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  static int _fnv64(String input) {
    const mask = 0xffffffffffffffff;
    var hash = 0xcbf29ce484222325;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & mask;
    }
    return hash;
  }
}
