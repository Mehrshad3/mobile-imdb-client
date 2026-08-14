import 'package:flutter/foundation.dart';

import '../api/imdb_api_exception.dart';

const bool _enabled = bool.fromEnvironment(
  'IMDB_SEARCH_TRACE',
  defaultValue: false,
);

void imdbSearchDebugLog(String message) {
  if (!kDebugMode || !_enabled) {
    return;
  }
  debugPrint('[imdb-debug] $message');
}

String debugErrorSummary(Object error) {
  if (error is ImdbApiException) {
    final parts = <String>[error.message];
    if (error.statusCode != null) {
      parts.add('status=${error.statusCode}');
    }
    if (error.uri != null) {
      parts.add('uri=${_safeUri(error.uri!)}');
    }
    final body = error.responseBody;
    if (body != null && body.isNotEmpty) {
      parts.add('body=${_shorten(body)}');
    }
    return parts.join(' | ');
  }

  return _shorten(error.toString());
}

String _safeUri(Uri uri) {
  final query = uri.hasQuery ? '?queryLength=${uri.query.length}' : '';
  return '${uri.scheme}://${uri.host}${uri.path}$query';
}

String _shorten(String value, [int maxLength = 260]) {
  final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compact.length <= maxLength) {
    return compact;
  }
  return '${compact.substring(0, maxLength)}...';
}
