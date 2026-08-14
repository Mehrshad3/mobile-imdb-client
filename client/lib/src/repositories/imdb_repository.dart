import '../api/imdb_api_client.dart';
import '../models/episode.dart';
import '../models/series_overview.dart';
import '../models/title_details.dart';
import '../models/title_summary.dart';

class ImdbRepository {
  ImdbRepository({ImdbApiClient? apiClient})
    : _apiClient = apiClient ?? ImdbApiClient();

  final ImdbApiClient _apiClient;

  Future<List<TitleSummary>> search(String query) {
    return _apiClient.searchSuggestions(query);
  }

  Future<List<TitleSummary>> trending({int first = 8}) {
    return _apiClient.fetchTrending(first: first);
  }

  Future<List<TitleSummary>> advancedSearch(String query) {
    return _apiClient.advancedTitleSearch(
      searchTerm: query,
      first: 20,
      titleTypeIds: const ['movie', 'tvSeries', 'tvMiniSeries'],
    );
  }

  Future<List<TitleSummary>> searchMovies(String query) {
    return _apiClient.advancedTitleSearch(
      searchTerm: query,
      first: 20,
      titleTypeIds: const ['movie'],
    );
  }

  Future<List<TitleSummary>> searchSeries(String query) {
    return _apiClient.advancedTitleSearch(
      searchTerm: query,
      first: 20,
      titleTypeIds: const ['tvSeries', 'tvMiniSeries'],
    );
  }

  Future<List<TitleSummary>> popularMovies({int first = 12}) {
    return _apiClient.advancedTitleSearch(
      first: first,
      titleTypeIds: const ['movie'],
    );
  }

  Future<List<TitleSummary>> popularSeries({int first = 12}) {
    return _apiClient.advancedTitleSearch(
      first: first,
      titleTypeIds: const ['tvSeries', 'tvMiniSeries'],
    );
  }

  Future<List<TitleSummary>> newTitles({int first = 12}) {
    final now = DateTime.now();
    return _apiClient.advancedTitleSearch(
      first: first,
      titleTypeIds: const ['movie', 'tvSeries', 'tvMiniSeries'],
      releaseDateStart: DateTime(now.year, 1, 1),
      releaseDateEnd: DateTime(now.year, 12, 31),
    );
  }

  Future<List<TitleSummary>> topRatedMovies({int first = 12}) {
    return _apiClient.advancedTitleSearch(
      first: first,
      titleTypeIds: const ['movie'],
      minimumRating: 8,
      minimumVotes: 50000,
      topRatedMoviesOnly: true,
    );
  }

  Future<List<TitleDetails>> titleDetails(List<String> titleIds) {
    return _apiClient.fetchTitleMetadata(titleIds);
  }

  Future<SeriesOverview> seriesOverview(String titleId) {
    return _apiClient.fetchSeriesOverview(titleId);
  }

  Future<List<Episode>> seasonEpisodes(String titleId, int seasonNumber) {
    return _apiClient.fetchSeasonEpisodes(titleId, seasonNumber);
  }

  void close() {
    _apiClient.close();
  }
}
