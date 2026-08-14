import 'dart:convert';
import 'dart:io';

import 'app_storage_directory.dart';

class SessionStore {
  SessionStore({this.filePath, this.fileName = 'session.json'});

  final String? filePath;
  final String fileName;

  Future<String?> readActiveUserId() async {
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

  Future<void> writeActiveUserId(String? userId) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert({'activeUserId': userId}),
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
