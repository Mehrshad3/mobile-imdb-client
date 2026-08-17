// ignore_for_file: prefer_initializing_formals

import '../api/backend_api_client.dart';
import '../api/imdb_api_client.dart';
import '../api/imdb_api_exception.dart';
import '../api/omdb_api_client.dart';
import '../debug/imdb_search_debug_log.dart';
import '../models/episode.dart';
import '../models/series_overview.dart';
import '../models/title_details_bundle.dart';
import '../models/title_details.dart';
import '../models/title_summary.dart';

class ImdbRepository {
  ImdbRepository({
    ImdbApiClient? apiClient,
    OmdbApiClient? omdbApiClient,
    BackendApiClient? backendClient,
  }) : _apiClient = apiClient ?? ImdbApiClient(),
       _omdbApiClient = omdbApiClient ?? OmdbApiClient(),
       _backendClient = backendClient;

  final ImdbApiClient _apiClient;
  final OmdbApiClient _omdbApiClient;
  final BackendApiClient? _backendClient;

  bool get _usesBackend => _backendClient?.isConfigured ?? false;

  Future<List<TitleSummary>> search(String query) async {
    final trimmed = query.trim();
    imdbSearchDebugLog('Repository.search -> suggestions query="$trimmed"');
    if (_usesBackend) {
      final results = await _serverCall(
        (server) => server.searchTitles(query: trimmed),
      );
      imdbSearchDebugLog(
        'Repository.search <- server count=${results.length} ${_titlesPreview(results)}',
      );
      return results;
    }

    final results = await _apiClient.searchSuggestions(trimmed);
    imdbSearchDebugLog(
      'Repository.search <- count=${results.length} ${_titlesPreview(results)}',
    );
    return results;
  }

  Future<List<TitleSummary>> searchSmart(String query) async {
    final trimmed = query.trim();
    final imdbId = extractImdbTitleId(trimmed);
    imdbSearchDebugLog(
      'Repository.searchSmart input="$trimmed" detectedId=${imdbId ?? 'none'}',
    );
    if (imdbId != null) {
      imdbSearchDebugLog('Repository.searchSmart route=idLookup id=$imdbId');
      return titleSummaryById(
        imdbId,
        fallbackTitle: titleSearchTextWithoutImdbId(trimmed),
      );
    }
    imdbSearchDebugLog('Repository.searchSmart route=suggestions');
    return search(trimmed);
  }

  Future<List<TitleSummary>> titleSummaryById(
    String titleId, {
    String? fallbackTitle,
  }) async {
    final rawInput = titleId.trim();
    final imdbId = extractImdbTitleId(rawInput);
    imdbSearchDebugLog(
      'Repository.titleSummaryById input="$rawInput" '
      'normalizedId=${imdbId ?? 'none'} fallbackTitle="${fallbackTitle ?? ''}"',
    );
    if (imdbId == null) {
      imdbSearchDebugLog('Repository.titleSummaryById stop=no-valid-imdb-id');
      return const [];
    }

    if (_usesBackend) {
      final results = await _serverCall((server) {
        final titleHint = _fallbackTitle(fallbackTitle);
        if (titleHint != null) {
          return server.searchTitles(query: '$titleHint $imdbId', first: 1);
        }
        return server.searchTitleById(imdbId);
      });
      imdbSearchDebugLog(
        'Repository.titleSummaryById <- server '
        'count=${results.length} ${_titlesPreview(results)}',
      );
      return results;
    }

    try {
      imdbSearchDebugLog(
        'Repository.titleSummaryById -> IMDb metadata ids=[$imdbId]',
      );
      final details = await _apiClient.fetchTitleMetadata([imdbId]);
      imdbSearchDebugLog(
        'Repository.titleSummaryById <- IMDb metadata '
        'count=${details.length} ${_detailsPreview(details)}',
      );
      if (details.isNotEmpty) {
        return [details.first.toSummary()];
      }
    } catch (error) {
      imdbSearchDebugLog(
        'Repository.titleSummaryById IMDb metadata error: '
        '${debugErrorSummary(error)}',
      );
      // Keep ID lookup usable even if this internal IMDb endpoint rejects a title.
    }

    try {
      imdbSearchDebugLog(
        'Repository.titleSummaryById -> OMDb id=$imdbId '
        'configured=${_omdbApiClient.isConfigured}',
      );
      final omdbDetails = await _omdbApiClient.fetchTitleById(imdbId);
      if (omdbDetails == null) {
        imdbSearchDebugLog('Repository.titleSummaryById <- OMDb result=null');
      } else {
        imdbSearchDebugLog(
          'Repository.titleSummaryById <- OMDb id=${omdbDetails.imdbId} '
          'title="${omdbDetails.title}" type="${omdbDetails.type}"',
        );
      }
      if (omdbDetails != null && omdbDetails.imdbId.isNotEmpty) {
        return [
          TitleSummary(
            id: omdbDetails.imdbId,
            title: omdbDetails.title,
            type: omdbDetails.type,
            year: _firstYear(omdbDetails.year),
            imageUrl: omdbDetails.poster,
            subtitle: omdbDetails.plot,
            rating: omdbDetails.imdbRating,
            canHaveEpisodes: omdbDetails.isSeries,
          ),
        ];
      }
    } catch (error) {
      imdbSearchDebugLog(
        'Repository.titleSummaryById OMDb error: ${debugErrorSummary(error)}',
      );
      // OMDb is optional and depends on OMDB_API_KEY.
    }

    imdbSearchDebugLog(
      'Repository.titleSummaryById fallback result id=$imdbId '
      'title="${_fallbackTitle(fallbackTitle) ?? imdbId}"',
    );
    return [
      TitleSummary(
        id: imdbId,
        title: _fallbackTitle(fallbackTitle) ?? imdbId,
        type: 'IMDb ID',
        subtitle: 'شناسه IMDb پیدا شد؛ برای دریافت جزئیات روی آن بزن.',
      ),
    ];
  }

  Future<List<TitleSummary>> trending({int first = 8}) async {
    if (_usesBackend) {
      return _serverCall((server) => server.trendingTitles(first: first));
    }

    final titles = await _apiClient.fetchTrending(first: first);
    if (titles.every((title) => title.imageUrl != null)) {
      return titles;
    }

    try {
      final ids = titles.map((title) => title.id).toList();
      final details = await _apiClient.fetchTitleMetadata(ids);
      final detailsById = {
        for (final detail in details) detail.id: detail.toSummary(),
      };
      return [
        for (final title in titles)
          title.imageUrl == null && detailsById[title.id]?.imageUrl != null
              ? title.copyWith(
                  imageUrl: detailsById[title.id]!.imageUrl,
                  rating: title.rating ?? detailsById[title.id]!.rating,
                  voteCount:
                      title.voteCount ?? detailsById[title.id]!.voteCount,
                  canHaveEpisodes:
                      title.canHaveEpisodes ||
                      detailsById[title.id]!.canHaveEpisodes,
                )
              : title,
      ];
    } catch (error) {
      imdbSearchDebugLog(
        'Repository.trending metadata image fallback failed: '
        '${debugErrorSummary(error)}',
      );
      return titles;
    }
  }

  Future<List<TitleSummary>> advancedSearch(String query) async {
    final trimmed = query.trim();
    final imdbId = extractImdbTitleId(trimmed);
    imdbSearchDebugLog(
      'Repository.advancedSearch input="$trimmed" '
      'detectedId=${imdbId ?? 'none'}',
    );
    if (imdbId != null) {
      imdbSearchDebugLog('Repository.advancedSearch route=idLookup id=$imdbId');
      return titleSummaryById(
        imdbId,
        fallbackTitle: titleSearchTextWithoutImdbId(trimmed),
      );
    }

    if (_usesBackend) {
      final results = await _serverCall(
        (server) =>
            server.advancedTitleSearch(query: trimmed, type: 'all', first: 20),
      );
      imdbSearchDebugLog(
        'Repository.advancedSearch <- server '
        'count=${results.length} ${_titlesPreview(results)}',
      );
      return results;
    }

    imdbSearchDebugLog(
      'Repository.advancedSearch -> AdvancedTitleSearch types=movie,tvSeries,tvMiniSeries',
    );
    final results = await _apiClient.advancedTitleSearch(
      searchTerm: trimmed,
      first: 20,
      titleTypeIds: const ['movie', 'tvSeries', 'tvMiniSeries'],
    );
    imdbSearchDebugLog(
      'Repository.advancedSearch <- count=${results.length} ${_titlesPreview(results)}',
    );
    return results;
  }

  Future<List<TitleSummary>> searchMovies(String query) async {
    final trimmed = query.trim();
    final imdbId = extractImdbTitleId(trimmed);
    imdbSearchDebugLog(
      'Repository.searchMovies input="$trimmed" detectedId=${imdbId ?? 'none'}',
    );
    if (imdbId != null) {
      imdbSearchDebugLog('Repository.searchMovies route=idLookup id=$imdbId');
      return titleSummaryById(
        imdbId,
        fallbackTitle: titleSearchTextWithoutImdbId(trimmed),
      );
    }

    if (_usesBackend) {
      final results = await _serverCall(
        (server) =>
            server.searchTitles(query: trimmed, type: 'movie', first: 20),
      );
      imdbSearchDebugLog(
        'Repository.searchMovies <- server '
        'count=${results.length} ${_titlesPreview(results)}',
      );
      return results;
    }

    imdbSearchDebugLog(
      'Repository.searchMovies -> AdvancedTitleSearch type=movie',
    );
    final results = await _apiClient.advancedTitleSearch(
      searchTerm: trimmed,
      first: 20,
      titleTypeIds: const ['movie'],
    );
    imdbSearchDebugLog(
      'Repository.searchMovies <- count=${results.length} ${_titlesPreview(results)}',
    );
    return results;
  }

  Future<List<TitleSummary>> searchSeries(String query) async {
    final trimmed = query.trim();
    final imdbId = extractImdbTitleId(trimmed);
    imdbSearchDebugLog(
      'Repository.searchSeries input="$trimmed" detectedId=${imdbId ?? 'none'}',
    );
    if (imdbId != null) {
      imdbSearchDebugLog('Repository.searchSeries route=idLookup id=$imdbId');
      return titleSummaryById(
        imdbId,
        fallbackTitle: titleSearchTextWithoutImdbId(trimmed),
      );
    }

    if (_usesBackend) {
      final results = await _serverCall(
        (server) =>
            server.searchTitles(query: trimmed, type: 'series', first: 20),
      );
      imdbSearchDebugLog(
        'Repository.searchSeries <- server '
        'count=${results.length} ${_titlesPreview(results)}',
      );
      return results;
    }

    imdbSearchDebugLog(
      'Repository.searchSeries -> AdvancedTitleSearch types=tvSeries,tvMiniSeries',
    );
    final results = await _apiClient.advancedTitleSearch(
      searchTerm: trimmed,
      first: 20,
      titleTypeIds: const ['tvSeries', 'tvMiniSeries'],
    );
    imdbSearchDebugLog(
      'Repository.searchSeries <- count=${results.length} ${_titlesPreview(results)}',
    );
    return results;
  }

  Future<List<TitleSummary>> popularMovies({int first = 12}) {
    if (_usesBackend) {
      return _serverCall((server) => server.popularMovies(first: first));
    }

    return _apiClient.advancedTitleSearch(
      first: first,
      titleTypeIds: const ['movie'],
    );
  }

  Future<List<TitleSummary>> popularSeries({int first = 12}) {
    if (_usesBackend) {
      return _serverCall((server) => server.popularSeries(first: first));
    }

    return _apiClient.advancedTitleSearch(
      first: first,
      titleTypeIds: const ['tvSeries', 'tvMiniSeries'],
    );
  }

  Future<List<TitleSummary>> newTitles({int first = 12}) {
    if (_usesBackend) {
      return _serverCall((server) => server.newTitles(first: first));
    }

    final now = DateTime.now();
    return _apiClient.advancedTitleSearch(
      first: first,
      titleTypeIds: const ['movie', 'tvSeries', 'tvMiniSeries'],
      releaseDateStart: DateTime(now.year, 1, 1),
      releaseDateEnd: DateTime(now.year, 12, 31),
    );
  }

  Future<List<TitleSummary>> topRatedMovies({int first = 12}) {
    if (_usesBackend) {
      return _serverCall((server) => server.topRatedMovies(first: first));
    }

    return _apiClient.advancedTitleSearch(
      first: first,
      titleTypeIds: const ['movie'],
      minimumRating: 8,
      minimumVotes: 50000,
      topRatedMoviesOnly: true,
    );
  }

  Future<List<TitleDetails>> titleDetails(List<String> titleIds) {
    if (_usesBackend) {
      return _serverCall((server) => server.titleMetadata(titleIds));
    }

    return _apiClient.fetchTitleMetadata(titleIds);
  }

  Future<TitleDetailsBundle> titleDetailsBundle(TitleSummary summary) async {
    if (_usesBackend) {
      return _serverCall((server) => server.titleDetailsBundle(summary));
    }

    final detailsFuture = _apiClient.fetchTitleMetadata([summary.id]);
    final omdbFuture = _omdbApiClient.fetchTitleById(summary.id);

    TitleDetails? details;
    Object? detailsError;
    try {
      final results = await detailsFuture;
      details = results.isEmpty ? null : results.first;
    } catch (error) {
      detailsError = error;
    }

    Object? omdbError;
    final omdbDetails = await _readSafely(
      omdbFuture,
      onError: (error) => omdbError = error,
    );

    SeriesOverview? overview;
    Object? overviewError;
    final provisionalBundle = TitleDetailsBundle(
      summary: summary,
      imdbDetails: details,
      omdbDetails: omdbDetails,
    );
    if (provisionalBundle.canHaveEpisodes) {
      overview = await _readSafely(
        _apiClient.fetchSeriesOverview(summary.id),
        onError: (error) => overviewError = error,
      );
    }

    final errors = [
      ?detailsError,
      ?omdbError,
      ?overviewError,
    ].whereType<Object>().toList();

    return TitleDetailsBundle(
      summary: summary,
      imdbDetails: details,
      omdbDetails: omdbDetails,
      seriesOverview: overview,
      errors: errors,
    );
  }

  Future<SeriesOverview> seriesOverview(String titleId) {
    if (_usesBackend) {
      return _serverCall((server) => server.seriesOverview(titleId));
    }

    return _apiClient.fetchSeriesOverview(titleId);
  }

  Future<List<Episode>> seasonEpisodes(String titleId, int seasonNumber) {
    if (_usesBackend) {
      return _serverCall(
        (server) => server.seasonEpisodes(titleId, seasonNumber),
      );
    }

    return _apiClient.fetchSeasonEpisodes(titleId, seasonNumber);
  }

  Future<List<Episode>> seasonEpisodesWithFallback(
    String titleId,
    int seasonNumber,
  ) async {
    if (_usesBackend) {
      return _serverCall(
        (server) => server.seasonEpisodes(titleId, seasonNumber),
      );
    }

    Object? imdbError;
    final imdbEpisodes = await _readSafely(
      _apiClient.fetchSeasonEpisodes(titleId, seasonNumber),
      onError: (error) => imdbError = error,
    );
    if (imdbEpisodes != null && imdbEpisodes.isNotEmpty) {
      return imdbEpisodes;
    }

    final omdbSeason = await _omdbApiClient.fetchSeason(titleId, seasonNumber);
    if (omdbSeason != null && omdbSeason.episodes.isNotEmpty) {
      return omdbSeason.episodes;
    }

    if (imdbError != null) {
      throw imdbError!;
    }
    return const [];
  }

  Future<T> _serverCall<T>(
    Future<T> Function(BackendApiClient server) action,
  ) async {
    final server = _backendClient;
    if (server == null || !server.isConfigured) {
      throw const ImdbApiException('Backend server is not configured.');
    }
    try {
      return await action(server);
    } on BackendApiException catch (error) {
      throw ImdbApiException(error.message, statusCode: error.statusCode);
    }
  }

  void close() {
    _apiClient.close();
    _omdbApiClient.close();
  }
}

String? extractImdbTitleId(String value) {
  final match = RegExp(r'tt\d+', caseSensitive: false).firstMatch(value.trim());
  return match?.group(0)?.toLowerCase();
}

String? titleSearchTextWithoutImdbId(String value) {
  final cleaned = value.replaceAll(RegExp(r'tt\d+', caseSensitive: false), ' ');
  return _fallbackTitle(cleaned);
}

String? _fallbackTitle(String? value) {
  final text = value?.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

int? _firstYear(String? value) {
  if (value == null) {
    return null;
  }
  final match = RegExp(r'\d{4}').firstMatch(value);
  if (match == null) {
    return null;
  }
  return int.tryParse(match.group(0)!);
}

String _titlesPreview(List<TitleSummary> titles) {
  if (titles.isEmpty) {
    return 'items=[]';
  }
  final items = titles
      .take(4)
      .map((title) => '${title.id}:${title.title}')
      .join(', ');
  return 'items=[$items]';
}

String _detailsPreview(List<TitleDetails> details) {
  if (details.isEmpty) {
    return 'items=[]';
  }
  final items = details
      .take(4)
      .map((title) => '${title.id}:${title.title}')
      .join(', ');
  return 'items=[$items]';
}

Future<T?> _readSafely<T>(
  Future<T> future, {
  required void Function(Object error) onError,
}) async {
  try {
    return await future;
  } catch (error) {
    onError(error);
    return null;
  }
}
