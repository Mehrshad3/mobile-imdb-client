import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/json_read.dart';
import '../models/omdb_title_details.dart';
import 'imdb_api_exception.dart';

class OmdbApiClient {
  OmdbApiClient({
    String apiKey = const String.fromEnvironment('OMDB_API_KEY'),
    HttpClient? httpClient,
    Duration? timeout,
  }) : apiKey = apiKey.trim(),
       _httpClient = httpClient ?? HttpClient(),
       timeout = timeout ?? const Duration(seconds: 10);

  final String apiKey;
  final HttpClient _httpClient;
  final Duration timeout;
  final Map<String, _JsonCacheEntry> _jsonCache = {};

  bool get isConfigured => apiKey.isNotEmpty;

  Future<OmdbTitleDetails?> fetchTitleById(String imdbId) async {
    final id = imdbId.trim();
    if (!isConfigured || id.isEmpty) {
      return null;
    }

    final json = await _get({'i': id, 'plot': 'full', 'r': 'json'});
    return OmdbTitleDetails.fromJson(json);
  }

  Future<List<OmdbTitleDetails>> searchTitles({
    required String query,
    String? type,
    int page = 1,
  }) async {
    final trimmed = query.trim();
    if (!isConfigured || trimmed.isEmpty) {
      return const [];
    }

    final parameters = {'s': trimmed, 'page': page.toString(), 'r': 'json'};
    final typeFilter = type;
    if (typeFilter != null) {
      parameters['type'] = typeFilter;
    }

    final json = await _get(parameters);

    final results = <OmdbTitleDetails>[];
    for (final rawTitle in asList(json['Search'])) {
      final map = asMap(rawTitle);
      if (map == null) {
        continue;
      }
      final title = OmdbTitleDetails.fromJson(map);
      if (title.imdbId.isNotEmpty) {
        results.add(title);
      }
    }
    return results;
  }

  Future<OmdbSeason?> fetchSeason(String imdbId, int seasonNumber) async {
    final id = imdbId.trim();
    if (!isConfigured || id.isEmpty || seasonNumber < 1) {
      return null;
    }

    final json = await _get({
      'i': id,
      'Season': seasonNumber.toString(),
      'r': 'json',
    });
    return OmdbSeason.fromJson(json, seasonNumber);
  }

  void close() {
    _httpClient.close(force: true);
  }

  Future<JsonMap> _get(Map<String, String> queryParameters) async {
    final uri = Uri.https('www.omdbapi.com', '/', {
      'apikey': apiKey,
      ...queryParameters,
    });
    final cacheKey = uri.toString();
    final cached = _jsonCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.json;
    }

    try {
      final request = await _httpClient.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      final responseText = await utf8.decoder
          .bind(response)
          .join()
          .timeout(timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ImdbApiException(
          'OMDb API returned an HTTP error.',
          uri: uri,
          statusCode: response.statusCode,
          responseBody: responseText,
        );
      }

      final json = asMap(jsonDecode(responseText));
      if (json == null) {
        throw ImdbApiException(
          'OMDb API returned a non-object JSON response.',
          uri: uri,
          responseBody: responseText,
        );
      }

      final ok = asString(json['Response']);
      if (ok == 'False') {
        throw ImdbApiException(
          asString(json['Error']) ?? 'OMDb API returned an error.',
          uri: uri,
          responseBody: responseText,
        );
      }

      _jsonCache[cacheKey] = _JsonCacheEntry(json);
      return json;
    } on ImdbApiException {
      rethrow;
    } on TimeoutException catch (error) {
      throw ImdbApiException(
        'OMDb request timed out: ${error.message ?? timeout.toString()}',
        uri: uri,
      );
    } on SocketException catch (error) {
      throw ImdbApiException(
        'Network error while connecting to OMDb: ${error.message}',
        uri: uri,
      );
    } on FormatException catch (error) {
      throw ImdbApiException(
        'Could not decode OMDb JSON response: ${error.message}',
        uri: uri,
      );
    }
  }
}

class _JsonCacheEntry {
  _JsonCacheEntry(this.json) : createdAt = DateTime.now();

  static const Duration ttl = Duration(minutes: 15);

  final JsonMap json;
  final DateTime createdAt;

  bool get isExpired => DateTime.now().difference(createdAt) > ttl;
}
