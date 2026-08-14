import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/episode.dart';
import '../models/json_read.dart';
import '../models/series_overview.dart';
import '../models/title_details.dart';
import '../models/title_summary.dart';
import 'imdb_api_exception.dart';

class ImdbApiClient {
  ImdbApiClient({HttpClient? httpClient, Duration? timeout})
    : _httpClient = httpClient ?? HttpClient(),
      timeout = timeout ?? const Duration(seconds: 12);

  static final Uri _graphqlUri = Uri.https('caching.graphql.imdb.com', '/');

  static const String _trendingHash =
      '419b4fc66817a78c3046e0cedef747033d5ac2711080338a59a366630f9742c1';
  static const String _advancedSearchHash =
      '78932519bc74ceb6be628fe452c0e59a48bcf8ca91fc550dd5de43ab200acd52';
  static const String _favoriteTitlesMetadataHash =
      'd326f6473ec76e947098d2585c35f0891c4b47c2ef261c14b7c82902ae196d1b';
  static const String _seriesOverviewHash =
      '3f56a4c9c2cca81733ebabbf5e317e3da7f2a4a02069d406bec001ed611c80e4';
  static const String _seasonEpisodesHash =
      '5cd1a7aa5ba917bd6e519570375e6f3f570ad3503e6a9d202b1fa4cb5ae6a56d';

  final HttpClient _httpClient;
  final Duration timeout;

  static const Map<String, String> defaultHeaders = {
    'Accept': 'application/graphql+json, application/json',
    'Accept-Language': 'en-US,en;q=0.9',
    'Content-Type': 'application/json',
    'Referer': 'https://www.imdb.com/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36',
    'x-imdb-client-name': 'imdb-web-next-localized',
    'x-imdb-user-language': 'en-US',
    'x-imdb-user-country': 'US',
  };

  Future<List<TitleSummary>> searchSuggestions(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const [];
    }

    final bucket = _suggestionBucket(trimmed);
    final uri = Uri(
      scheme: 'https',
      host: 'v3.sg.media-imdb.com',
      pathSegments: ['suggestion', bucket, '$trimmed.json'],
      queryParameters: const {'includeVideos': '1'},
    );

    final json = await _sendJson('GET', uri);
    final results = <TitleSummary>[];
    for (final item in asList(json['d'])) {
      final map = asMap(item);
      if (map == null) {
        continue;
      }
      final title = TitleSummary.fromSuggestion(map);
      if (title.isValid) {
        results.add(title);
      }
    }
    return results;
  }

  Future<List<TitleSummary>> fetchTrending({int first = 8}) async {
    final json = await _getGraphqlPersisted(
      operationName: 'Trending',
      variables: {
        'first': first,
        'input': {'dataWindow': 'HOURS', 'trafficSource': 'XWW'},
      },
      hash: _trendingHash,
    );

    final edges = asList(
      readPath(json, ['data', 'topTrendingTitles', 'edges']),
    );
    final results = <TitleSummary>[];
    for (final edge in edges) {
      final map = asMap(edge);
      if (map == null) {
        continue;
      }
      final title = TitleSummary.fromTrendingEdge(map);
      if (title.isValid) {
        results.add(title);
      }
    }
    return results;
  }

  Future<List<TitleSummary>> advancedTitleSearch({
    String searchTerm = '',
    int first = 20,
    List<String> titleTypeIds = const ['movie', 'tvSeries'],
    String sortBy = 'POPULARITY',
    String sortOrder = 'ASC',
    DateTime? releaseDateStart,
    DateTime? releaseDateEnd,
    double? minimumRating,
    int? minimumVotes,
    bool topRatedMoviesOnly = false,
  }) async {
    final trimmed = searchTerm.trim();

    final variables = <String, Object?>{
      'locale': 'en-US',
      'first': first,
      'sortBy': sortBy,
      'sortOrder': sortOrder,
    };
    if (trimmed.isNotEmpty) {
      variables['titleTextConstraint'] = {'searchTerm': trimmed};
    }
    if (titleTypeIds.isNotEmpty) {
      variables['titleTypeConstraint'] = {'anyTitleTypeIds': titleTypeIds};
    }
    if (releaseDateStart != null || releaseDateEnd != null) {
      variables['releaseDateConstraint'] = {
        'releaseDateRange': {
          if (releaseDateStart != null) 'start': _formatDate(releaseDateStart),
          if (releaseDateEnd != null) 'end': _formatDate(releaseDateEnd),
        },
      };
    }
    if (minimumRating != null || minimumVotes != null) {
      variables['userRatingsConstraint'] = {
        if (minimumRating != null)
          'aggregateRatingRange': {'min': minimumRating, 'max': 10},
        if (minimumVotes != null) 'ratingsCountRange': {'min': minimumVotes},
      };
    }
    if (topRatedMoviesOnly) {
      variables['rankedTitleListConstraint'] = {
        'allRankedTitleLists': [
          {
            'rankedTitleListType': 'TOP_RATED_MOVIES',
            'rankRange': {'max': 250},
          },
        ],
        'excludeRankedTitleLists': [],
      };
    }

    final json = await _postGraphqlPersisted(
      operationName: 'AdvancedTitleSearch',
      variables: variables,
      hash: _advancedSearchHash,
    );

    final edges = asList(
      readPath(json, ['data', 'advancedTitleSearch', 'edges']),
    );
    final results = <TitleSummary>[];
    for (final edge in edges) {
      final map = asMap(edge);
      if (map == null) {
        continue;
      }
      final title = TitleSummary.fromAdvancedEdge(map);
      if (title.isValid) {
        results.add(title);
      }
    }
    return results;
  }

  Future<List<TitleDetails>> fetchTitleMetadata(List<String> titleIds) async {
    final ids = titleIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) {
      return const [];
    }

    final json = await _getGraphqlPersisted(
      operationName: 'FavoriteTitlesMetadata',
      variables: {'locale': 'en-US', 'tconsts': ids},
      hash: _favoriteTitlesMetadataHash,
    );

    final titles = <TitleDetails>[];
    for (final title in asList(readPath(json, ['data', 'titles']))) {
      final map = asMap(title);
      if (map == null) {
        continue;
      }
      final details = TitleDetails.fromMetadata(map);
      if (details.id.isNotEmpty && details.title.isNotEmpty) {
        titles.add(details);
      }
    }
    return titles;
  }

  Future<SeriesOverview> fetchSeriesOverview(String titleId) async {
    final id = titleId.trim();
    if (id.isEmpty) {
      throw const ImdbApiException('Title id is required.');
    }

    final json = await _getGraphqlPersisted(
      operationName: 'HERO_SUB_NAV_EPISODE',
      variables: _seriesOverviewVariables(id),
      hash: _seriesOverviewHash,
    );

    return SeriesOverview.fromHeroSubNav(id, json);
  }

  Future<List<Episode>> fetchSeasonEpisodes(
    String titleId,
    int seasonNumber,
  ) async {
    final id = titleId.trim();
    if (id.isEmpty) {
      throw const ImdbApiException('Title id is required.');
    }
    if (seasonNumber < 1) {
      throw const ImdbApiException('Season number must be positive.');
    }

    final json = await _getGraphqlPersisted(
      operationName: 'EpisodeRatings_SeasonDetail',
      variables: {
        'id': id,
        'locale': 'en-US',
        'seasons': [seasonNumber.toString()],
      },
      hash: _seasonEpisodesHash,
    );

    final edges = asList(
      readPath(json, ['data', 'title', 'episodes', 'episodes', 'edges']),
    );
    final episodes = <Episode>[];
    for (final edge in edges) {
      final node = asMap(readPath(edge, ['node']));
      if (node == null) {
        continue;
      }
      final episode = Episode.fromNode(node);
      if (episode.isValid) {
        episodes.add(episode);
      }
    }
    return episodes;
  }

  void close() {
    _httpClient.close(force: true);
  }

  Future<JsonMap> _getGraphqlPersisted({
    required String operationName,
    required Map<String, Object?> variables,
    required String hash,
  }) {
    final uri = _graphqlUri.replace(
      queryParameters: {
        'operationName': operationName,
        'variables': jsonEncode(variables),
        'extensions': jsonEncode(_persistedQuery(hash)),
      },
    );
    return _sendJson('GET', uri);
  }

  Future<JsonMap> _postGraphqlPersisted({
    required String operationName,
    required Map<String, Object?> variables,
    required String hash,
  }) {
    return _sendJson(
      'POST',
      _graphqlUri,
      body: jsonEncode({
        'operationName': operationName,
        'variables': variables,
        'extensions': _persistedQuery(hash),
      }),
    );
  }

  Future<JsonMap> _sendJson(String method, Uri uri, {String? body}) async {
    try {
      final request = await _httpClient.openUrl(method, uri).timeout(timeout);
      defaultHeaders.forEach(request.headers.set);

      if (body != null) {
        request.add(utf8.encode(body));
      }

      final response = await request.close().timeout(timeout);
      final responseText = await utf8.decoder
          .bind(response)
          .join()
          .timeout(timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ImdbApiException(
          'IMDb API returned an HTTP error.',
          uri: uri,
          statusCode: response.statusCode,
          responseBody: _shorten(responseText),
        );
      }

      final decoded = jsonDecode(responseText);
      final json = asMap(decoded);
      if (json == null) {
        throw ImdbApiException(
          'IMDb API returned a non-object JSON response.',
          uri: uri,
          responseBody: _shorten(responseText),
        );
      }

      final errors = asList(json['errors']);
      if (errors.isNotEmpty) {
        throw ImdbApiException(
          _graphqlErrorMessage(errors),
          uri: uri,
          responseBody: _shorten(responseText),
        );
      }

      return json;
    } on ImdbApiException {
      rethrow;
    } on TimeoutException catch (error) {
      throw ImdbApiException(
        'IMDb API request timed out: ${error.message ?? timeout.toString()}',
        uri: uri,
      );
    } on SocketException catch (error) {
      throw ImdbApiException(
        'Network error while connecting to IMDb: ${error.message}',
        uri: uri,
      );
    } on FormatException catch (error) {
      throw ImdbApiException(
        'Could not decode IMDb JSON response: ${error.message}',
        uri: uri,
      );
    }
  }

  Map<String, Object> _persistedQuery(String hash) {
    return {
      'persistedQuery': {'version': 1, 'sha256Hash': hash},
    };
  }

  Map<String, Object?> _seriesOverviewVariables(String titleId) {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    return {
      'heroNowDateDay': now.day,
      'heroNowDateMonth': now.month,
      'heroNowDateYear': now.year,
      'heroYesterdayDateDay': yesterday.day,
      'heroYesterdayDateMonth': yesterday.month,
      'heroYesterdayDateYear': yesterday.year,
      'locale': 'en-US',
      'titleId': titleId,
    };
  }

  String _suggestionBucket(String query) {
    final first = query[0].toLowerCase();
    if (RegExp(r'^[a-z0-9]$').hasMatch(first)) {
      return first;
    }
    return 'a';
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String _graphqlErrorMessage(List<dynamic> errors) {
    final messages = <String>[];
    for (final error in errors) {
      final message = asString(readPath(error, ['message']));
      if (message != null) {
        messages.add(message);
      }
    }
    if (messages.isEmpty) {
      return 'IMDb GraphQL returned an error.';
    }
    return 'IMDb GraphQL error: ${messages.join(' | ')}';
  }

  String _shorten(String value, {int maxLength = 700}) {
    if (value.length <= maxLength) {
      return value;
    }
    return '${value.substring(0, maxLength)}...';
  }
}
