import 'dart:io';

import 'package:flutter/services.dart';

class AppStorageDirectory {
  AppStorageDirectory._();

  static const MethodChannel _channel = MethodChannel('imdb_api_1/app_storage');

  static Future<Directory> resolve() async {
    try {
      final path = await _channel.invokeMethod<String>(
        'getAppStorageDirectory',
      );
      if (path != null && path.isNotEmpty) {
        return Directory(path);
      }
    } on MissingPluginException {
      // Tests and non-Android desktop runs use the temp fallback below.
    } on PlatformException {
      // Keep the app usable if the native side is not available.
    }

    return Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}imdb_api_1',
    );
  }
}
