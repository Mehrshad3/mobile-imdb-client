import 'dart:async';
import 'dart:io';

import 'app_storage_directory.dart';

class PosterCacheStore {
  PosterCacheStore({HttpClient? httpClient, Duration? timeout})
    : _httpClient = httpClient ?? HttpClient(),
      timeout = timeout ?? const Duration(seconds: 15);

  static final PosterCacheStore instance = PosterCacheStore();

  final HttpClient _httpClient;
  final Duration timeout;
  final Map<String, Future<File?>> _pendingDownloads = {};

  Future<File?> imageFile(String url) {
    final normalizedUrl = _normalizeUrl(url);
    if (normalizedUrl == null) {
      return Future.value();
    }
    return _pendingDownloads.putIfAbsent(normalizedUrl, () async {
      try {
        return await _readOrDownload(normalizedUrl);
      } finally {
        _pendingDownloads.remove(normalizedUrl);
      }
    });
  }

  Future<File?> _readOrDownload(String url) async {
    final file = await _fileForUrl(url);
    if (await file.exists() && await file.length() > 0) {
      return file;
    }

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return null;
    }

    final tempFile = File('${file.path}.download');
    try {
      final request = await _httpClient.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'image/*,*/*;q=0.8');
      request.headers.set(HttpHeaders.refererHeader, 'https://www.imdb.com/');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36',
      );

      final response = await request.close().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      await file.parent.create(recursive: true);
      final sink = tempFile.openWrite();
      await response.pipe(sink).timeout(timeout);
      if (await tempFile.length() == 0) {
        return null;
      }
      if (await file.exists()) {
        await file.delete();
      }
      await tempFile.rename(file.path);
      return file;
    } on Object {
      return null;
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  Future<File> _fileForUrl(String url) async {
    final directory = await AppStorageDirectory.resolve();
    final cacheDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}poster_cache',
    );
    final extension = _imageExtension(url);
    return File(
      '${cacheDirectory.path}${Platform.pathSeparator}${_hashUrl(url)}$extension',
    );
  }
}

String? _normalizeUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (trimmed.startsWith('//')) {
    return 'https:$trimmed';
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return null;
  }
  if (uri.scheme == 'http') {
    return uri.replace(scheme: 'https').toString();
  }
  return uri.toString();
}

String _imageExtension(String url) {
  final uri = Uri.tryParse(url);
  final path = uri?.path.toLowerCase() ?? '';
  for (final extension in const ['.jpg', '.jpeg', '.png', '.webp']) {
    if (path.contains(extension)) {
      return extension == '.jpeg' ? '.jpg' : extension;
    }
  }
  return '.img';
}

String _hashUrl(String value) {
  var hash = 0xcbf29ce484222325;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
