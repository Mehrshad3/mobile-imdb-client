import 'dart:convert';
import 'dart:io';

import 'app_storage_directory.dart';

class AuthSession {
  const AuthSession({
    required this.userId,
    required this.token,
    required this.expiresAt,
  });

  final String userId;
  final String token;
  final DateTime expiresAt;

  bool isValid(DateTime now) => now.isBefore(expiresAt);

  Map<String, Object?> toJson() {
    return {
      'activeUserId': userId,
      'token': token,
      'expiresAt': expiresAt.toIso8601String(),
    };
  }

  static AuthSession? fromJson(Map<String, Object?> json) {
    final userId = json['activeUserId'] as String?;
    final token = json['token'] as String?;
    final expiresAt = DateTime.tryParse(json['expiresAt'] as String? ?? '');
    if (userId == null || token == null || expiresAt == null) {
      return null;
    }
    return AuthSession(userId: userId, token: token, expiresAt: expiresAt);
  }
}

class SessionStore {
  SessionStore({this.filePath, this.fileName = 'session.json'});

  final String? filePath;
  final String fileName;

  Future<String?> readActiveUserId() async {
    final session = await readSession();
    if (session != null) {
      return session.userId;
    }
    final file = await _file();
    if (!await file.exists()) {
      return null;
    }

    final text = await file.readAsString();
    if (text.trim().isEmpty) {
      return null;
    }

    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      return null;
    }
    return decoded['activeUserId'] as String?;
  }

  Future<AuthSession?> readSession() async {
    final file = await _file();
    if (!await file.exists()) {
      return null;
    }

    final text = await file.readAsString();
    if (text.trim().isEmpty) {
      return null;
    }

    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      return null;
    }
    return AuthSession.fromJson(decoded.cast<String, Object?>());
  }

  Future<void> writeActiveUserId(String? userId) async {
    if (userId == null) {
      await writeSession(null);
      return;
    }
    await writeSession(
      AuthSession(
        userId: userId,
        token: 'legacy-session',
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      ),
    );
  }

  Future<void> writeSession(AuthSession? session) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert(session?.toJson() ?? {'activeUserId': null}),
      flush: true,
    );
  }

  Future<File> _file() async {
    final explicitPath = filePath;
    if (explicitPath != null && explicitPath.isNotEmpty) {
      return File(explicitPath);
    }

    final directory = await AppStorageDirectory.resolve();
    return File('${directory.path}${Platform.pathSeparator}$fileName');
  }
}
