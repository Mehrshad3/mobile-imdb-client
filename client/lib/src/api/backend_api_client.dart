import 'dart:convert';
import 'dart:io';

import '../models/episode.dart';
import '../models/local_title_stats.dart';
import '../models/mock_user.dart';
import '../models/omdb_title_details.dart';
import '../models/series_overview.dart';
import '../models/title_details.dart';
import '../models/title_details_bundle.dart';
import '../models/title_summary.dart';
import '../models/user_account.dart';
import '../models/watchlist_item.dart';

class BackendApiClient {
  BackendApiClient({String? baseUrl}) : baseUrl = _normalizeBaseUrl(baseUrl);

  factory BackendApiClient.fromEnvironment() {
    return BackendApiClient(baseUrl: _configuredBaseUrl);
  }

  static const _configuredBaseUrl = String.fromEnvironment('IMDB_BACKEND_URL');

  final String baseUrl;

  bool get isConfigured => baseUrl.isNotEmpty;

  Future<bool> isHealthy() async {
    if (!isConfigured) {
      return false;
    }

    try {
      await _sendJson('GET', '/health');
      return true;
    } on BackendApiException {
      return false;
    }
  }

  Future<BackendAuthResult> login({
    required String email,
    required String password,
  }) async {
    final payload = await _sendJson(
      'POST',
      '/auth/login',
      body: {'email': email.trim(), 'password': password},
    );
    return _authResultFromPayload(payload);
  }

  Future<void> requestRegistrationOtp(RegistrationDraft draft) {
    return _sendJson(
      'POST',
      '/auth/register/request-otp',
      body: {
        'full_name': draft.displayName.trim(),
        'display_name': draft.displayName.trim(),
        'username': draft.username.trim(),
        'email': draft.email.trim().toLowerCase(),
        'password': draft.password,
        'avatar_url': _blankToNull(draft.profileImageUrl),
        'profile_image_url': _blankToNull(draft.profileImageUrl),
        'bio': _blankToNull(draft.bio),
      },
    ).then((_) {});
  }

  Future<BackendAuthResult> confirmRegistrationOtp({
    required String email,
    required String otp,
  }) async {
    return confirmRegistrationOtpWithDraft(email: email, otp: otp);
  }

  Future<BackendAuthResult> confirmRegistrationOtpWithDraft({
    required String email,
    required String otp,
    RegistrationDraft? draft,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedOtp = otp.trim();
    final minimalBody = {'email': normalizedEmail, 'otp': normalizedOtp};

    try {
      final payload = await _sendJson(
        'POST',
        '/auth/register/confirm',
        body: minimalBody,
      );
      return _authResultFromPayload(payload);
    } on BackendApiException catch (error) {
      if (draft == null || !_shouldRetryRegistrationConfirm(error)) {
        rethrow;
      }
    }

    final payload = await _sendJson(
      'POST',
      '/auth/register/confirm',
      body: {
        ...minimalBody,
        'code': normalizedOtp,
        'passcode': normalizedOtp,
        'otp_code': normalizedOtp,
        'verification_code': normalizedOtp,
        ..._registrationDraftJson(draft, emailOverride: normalizedEmail),
      },
    );
    return _authResultFromPayload(payload);
  }

  Future<void> requestPasswordResetOtp(String email) {
    return _sendJson(
      'POST',
      '/auth/password-reset/request',
      body: {'email': email.trim().toLowerCase()},
    ).then((_) {});
  }

  Future<void> confirmPasswordReset({
    required String email,
    required String otp,
    required String newPassword,
  }) {
    return _sendJson(
      'POST',
      '/auth/password-reset/confirm',
      body: {
        'email': email.trim().toLowerCase(),
        'otp': otp.trim(),
        'new_password': newPassword,
        'newPassword': newPassword,
      },
    ).then((_) {});
  }

  Future<MockUser> currentUser(String token) async {
    final payload = await _sendJson('GET', '/users/me', token: token);
    return _userFromPayload(payload);
  }

  Future<AdminUsersPage> adminUsers(
    String token, {
    int limit = 50,
    int offset = 0,
  }) async {
    final payload = await _sendJson(
      'GET',
      _queryPath('/admin/users', {'limit': limit, 'offset': offset}),
      token: token,
    );
    final json = payload is Map ? payload.cast<String, Object?>() : null;
    final users = _extractList(payload, keys: const ['items', 'users'])
        .whereType<Map>()
        .map((item) => _adminUserFromJson(item.cast<String, Object?>()))
        .where((user) => user.id.isNotEmpty)
        .toList();

    return AdminUsersPage(
      items: users,
      total: _intValue(json?['total']) ?? users.length,
      limit: _intValue(json?['limit']) ?? limit,
      offset: _intValue(json?['offset']) ?? offset,
    );
  }

  Future<AdminReviewsPage> adminReviews(
    String token, {
    int limit = 50,
    int offset = 0,
  }) async {
    final payload = await _sendJson(
      'GET',
      _queryPath('/admin/reviews', {'limit': limit, 'offset': offset}),
      token: token,
    );
    final json = payload is Map ? payload.cast<String, Object?>() : null;
    final reviews = _extractList(payload, keys: const ['items', 'reviews'])
        .whereType<Map>()
        .map((item) => _adminReviewFromJson(item.cast<String, Object?>()))
        .where((review) => review.id.isNotEmpty && review.text.isNotEmpty)
        .toList();

    return AdminReviewsPage(
      items: reviews,
      total: _intValue(json?['total']) ?? reviews.length,
      limit: _intValue(json?['limit']) ?? limit,
      offset: _intValue(json?['offset']) ?? offset,
    );
  }

  Future<void> adminDeleteReview(String token, String reviewId) {
    return _sendJson(
      'DELETE',
      '/admin/reviews/${Uri.encodeComponent(reviewId)}',
      token: token,
    ).then((_) {});
  }

  Future<List<WatchlistItem>> watchlist(String token) async {
    final payload = await _sendJson('GET', '/watchlist', token: token);
    final items = _extractList(payload, keys: const ['items', 'watchlist']);
    return items
        .whereType<Map>()
        .map((item) => _watchlistItemFromJson(item.cast<String, Object?>()))
        .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
        .toList();
  }

  Future<Map<String, Set<String>>> watchProgress(String token) async {
    final payload = await _sendJson('GET', '/progress', token: token);
    final items = _extractList(payload, keys: const ['items', 'progress']);
    final progress = <String, Set<String>>{};
    for (final item in items.whereType<Map>()) {
      final json = item.cast<String, Object?>();
      final titleId = _stringValue(
        json['title_id'] ?? json['titleId'] ?? json['id'] ?? json['imdb_id'],
      );
      if (titleId == null) {
        continue;
      }
      progress[titleId] = _stringSetValue(
        json['watched_episode_ids'] ??
            json['watchedEpisodeIds'] ??
            json['episode_ids'] ??
            json['episodes'],
      );
    }
    return progress;
  }

  Future<void> saveWatchlistItem(String token, WatchlistItem item) {
    return _sendJson(
      'POST',
      '/watchlist',
      token: token,
      body: _watchlistItemToServerJson(item),
    ).then((_) {});
  }

  Future<void> patchWatchlistItem(
    String token,
    String titleId, {
    WatchStatus? status,
    bool? favorite,
  }) {
    final body = <String, Object?>{};
    if (status != null) {
      body['status'] = status.storageValue;
    }
    if (favorite != null) {
      body['favorite'] = favorite;
    }
    return _sendJson(
      'PATCH',
      '/watchlist/${Uri.encodeComponent(titleId)}',
      token: token,
      body: body,
    ).then((_) {});
  }

  Future<void> deleteWatchlistItem(String token, String titleId) {
    return _sendJson(
      'DELETE',
      '/watchlist/${Uri.encodeComponent(titleId)}',
      token: token,
    ).then((_) {});
  }

  Future<void> setEpisodeWatched(
    String token,
    WatchlistItem item,
    String episodeId, {
    required bool watched,
  }) {
    final titleId = Uri.encodeComponent(item.id);
    final encodedEpisodeId = Uri.encodeComponent(episodeId);
    final method = watched ? 'POST' : 'DELETE';
    return _sendJson(
      method,
      '/progress/$titleId/episodes/$encodedEpisodeId',
      token: token,
      body: watched ? _titleMetadataJson(item) : null,
    ).then((_) {});
  }

  Future<void> saveRating(String token, WatchlistItem item, int rating) {
    return _sendJson(
      'POST',
      '/titles/${Uri.encodeComponent(item.id)}/rating',
      token: token,
      body: {'rating': rating.clamp(1, 10), ..._titleMetadataJson(item)},
    ).then((_) {});
  }

  Future<void> deleteRating(String token, String titleId) {
    return _sendJson(
      'DELETE',
      '/titles/${Uri.encodeComponent(titleId)}/rating',
      token: token,
    ).then((_) {});
  }

  Future<void> saveReview(
    String token,
    WatchlistItem item, {
    required String text,
    required bool hasSpoiler,
  }) {
    return _sendJson(
      'POST',
      '/titles/${Uri.encodeComponent(item.id)}/review',
      token: token,
      body: {
        'text': text.trim(),
        'contains_spoiler': hasSpoiler,
        ..._titleMetadataJson(item),
      },
    ).then((_) {});
  }

  Future<void> deleteReview(String token, String titleId) {
    return _sendJson(
      'DELETE',
      '/titles/${Uri.encodeComponent(titleId)}/review',
      token: token,
    ).then((_) {});
  }

  Future<Map<String, int>> myRatings(String token) async {
    final payload = await _sendJson('GET', '/titles/me/ratings', token: token);
    final items = _extractList(payload, keys: const ['items', 'ratings']);
    final ratings = <String, int>{};
    for (final item in items.whereType<Map>()) {
      final json = item.cast<String, Object?>();
      final id = _stringValue(
        json['title_id'] ?? json['titleId'] ?? json['id'] ?? json['imdb_id'],
      );
      final rating = _intValue(json['rating'] ?? json['user_rating']);
      if (id != null && rating != null) {
        ratings[id] = rating;
      }
    }
    return ratings;
  }

  Future<Map<String, BackendReviewSnapshot>> myReviews(String token) async {
    final payload = await _sendJson('GET', '/titles/me/reviews', token: token);
    final items = _extractList(payload, keys: const ['items', 'reviews']);
    final reviews = <String, BackendReviewSnapshot>{};
    for (final item in items.whereType<Map>()) {
      final json = item.cast<String, Object?>();
      final id = _stringValue(
        json['title_id'] ?? json['titleId'] ?? json['id'] ?? json['imdb_id'],
      );
      final text = _stringValue(json['text'] ?? json['review']);
      if (id == null || text == null || text.trim().isEmpty) {
        continue;
      }
      reviews[id] = BackendReviewSnapshot(
        text: text,
        hasSpoiler: _boolValue(json['contains_spoiler']) ?? false,
        createdAt: _dateValue(json['created_at'] ?? json['createdAt']),
      );
    }
    return reviews;
  }

  Future<LocalTitleStats> titleFeedback(String token, String titleId) async {
    final payload = await _sendJson(
      'GET',
      '/titles/${Uri.encodeComponent(titleId)}/feedback',
      token: token,
    );
    if (payload is! Map) {
      return const LocalTitleStats();
    }

    final json = payload.cast<String, Object?>();
    final summary = json['rating_summary'] ?? json['ratingSummary'];
    final summaryJson = summary is Map ? summary.cast<String, Object?>() : null;
    final ratingCount = _intValue(summaryJson?['rating_count']) ?? 0;
    final averageRating = _doubleValue(summaryJson?['average_rating']);
    final reviews =
        _extractList(json, keys: const ['reviews'])
            .whereType<Map>()
            .map((review) => _reviewFromJson(review.cast<String, Object?>()))
            .where((review) => review.text.trim().isNotEmpty)
            .toList()
          ..sort(_compareReviews);

    return LocalTitleStats(
      ratingCount: ratingCount,
      averageRatingOverride: averageRating,
      reviewCount: reviews.length,
      reviews: reviews,
    );
  }

  Future<List<TitleSummary>> searchTitles({
    required String query,
    String type = 'all',
    int first = 20,
  }) async {
    final payload = await _sendJson(
      'GET',
      _queryPath('/titles/search', {
        'q': query.trim(),
        'type': type,
        'first': first,
      }),
    );
    return _titleSummariesFromPayload(payload);
  }

  Future<List<TitleSummary>> searchTitleById(String titleId) async {
    final payload = await _sendJson(
      'GET',
      '/titles/search-by-id/${Uri.encodeComponent(titleId.trim())}',
    );
    return _titleSummariesFromPayload(payload);
  }

  Future<List<TitleSummary>> advancedTitleSearch({
    String query = '',
    String type = 'all',
    int first = 20,
    String sortBy = 'POPULARITY',
    String sortOrder = 'ASC',
    DateTime? releaseDateStart,
    DateTime? releaseDateEnd,
    double? minimumRating,
    int? minimumVotes,
    bool topRatedMoviesOnly = false,
  }) async {
    final payload = await _sendJson(
      'GET',
      _queryPath('/titles/advanced-search', {
        'q': query.trim(),
        'type': type,
        'first': first,
        'sort_by': sortBy,
        'sort_order': sortOrder,
        'release_date_start': _dateParameter(releaseDateStart),
        'release_date_end': _dateParameter(releaseDateEnd),
        'minimum_rating': minimumRating,
        'minimum_votes': minimumVotes,
        'top_rated_movies_only': topRatedMoviesOnly,
      }),
    );
    return _titleSummariesFromPayload(payload);
  }

  Future<List<TitleSummary>> trendingTitles({int first = 12}) async {
    final payload = await _sendJson(
      'GET',
      _queryPath('/titles/trending', {'first': first}),
    );
    return _titleSummariesFromPayload(payload);
  }

  Future<List<TitleSummary>> popularMovies({int first = 12}) async {
    final payload = await _sendJson(
      'GET',
      _queryPath('/titles/popular/movies', {'first': first}),
    );
    return _titleSummariesFromPayload(payload);
  }

  Future<List<TitleSummary>> popularSeries({int first = 12}) async {
    final payload = await _sendJson(
      'GET',
      _queryPath('/titles/popular/series', {'first': first}),
    );
    return _titleSummariesFromPayload(payload);
  }

  Future<List<TitleSummary>> newTitles({int first = 12}) async {
    final payload = await _sendJson(
      'GET',
      _queryPath('/titles/new', {'first': first}),
    );
    return _titleSummariesFromPayload(payload);
  }

  Future<List<TitleSummary>> topRatedMovies({int first = 12}) async {
    final payload = await _sendJson(
      'GET',
      _queryPath('/titles/top-rated', {'first': first}),
    );
    return _titleSummariesFromPayload(payload);
  }

  Future<List<TitleDetails>> titleMetadata(List<String> titleIds) async {
    final ids = titleIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) {
      return const [];
    }

    final payload = await _sendJson(
      'GET',
      _queryPath('/titles/metadata', {'ids': ids.join(',')}),
    );
    final items = _extractList(payload, keys: const ['items']);
    return items
        .whereType<Map>()
        .map((item) => _titleDetailsFromJson(item.cast<String, Object?>()))
        .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
        .toList();
  }

  Future<TitleDetailsBundle> titleDetailsBundle(TitleSummary summary) async {
    final payload = await _sendJson(
      'GET',
      '/titles/${Uri.encodeComponent(summary.id)}',
    );
    final json = payload is Map ? payload.cast<String, Object?>() : null;
    if (json == null) {
      throw const BackendApiException('پاسخ جزئیات عنوان قابل خواندن نیست.');
    }

    final serverSummaryJson = _mapValue(json['summary']);
    final serverSummary = serverSummaryJson == null
        ? null
        : _titleSummaryFromJson(serverSummaryJson);
    final effectiveSummary = (serverSummary?.isValid ?? false)
        ? serverSummary!
        : summary;
    final imdbDetailsJson = _mapValue(json['imdbDetails']);
    final omdbDetailsJson = _mapValue(json['omdbDetails']);
    final overviewJson = _mapValue(json['seriesOverview']);

    return TitleDetailsBundle(
      summary: effectiveSummary,
      imdbDetails: imdbDetailsJson == null
          ? null
          : _titleDetailsFromJson(imdbDetailsJson),
      omdbDetails: omdbDetailsJson == null
          ? null
          : _omdbTitleDetailsFromJson(omdbDetailsJson),
      seriesOverview: overviewJson == null
          ? null
          : _seriesOverviewFromJson(overviewJson, effectiveSummary.id),
      errors: _objectListValue(json['errors']),
    );
  }

  Future<SeriesOverview> seriesOverview(String titleId) async {
    final id = titleId.trim();
    final payload = await _sendJson(
      'GET',
      '/titles/${Uri.encodeComponent(id)}/overview',
    );
    final json = payload is Map ? payload.cast<String, Object?>() : null;
    if (json == null) {
      throw const BackendApiException('پاسخ اطلاعات سریال قابل خواندن نیست.');
    }
    return _seriesOverviewFromJson(json, id);
  }

  Future<List<Episode>> seasonEpisodes(String titleId, int seasonNumber) async {
    final payload = await _sendJson(
      'GET',
      '/titles/${Uri.encodeComponent(titleId.trim())}/seasons/$seasonNumber/episodes',
    );
    final items = _extractList(payload, keys: const ['items', 'episodes']);
    return items
        .whereType<Map>()
        .map((item) => _episodeFromJson(item.cast<String, Object?>()))
        .where((episode) => episode.isValid)
        .toList();
  }

  Future<Object?> _sendJson(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? token,
  }) async {
    if (!isConfigured) {
      throw const BackendApiException('آدرس سرور تنظیم نشده است.');
    }

    final uri = Uri.parse('$baseUrl$path');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.openUrl(method, uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (token != null && token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }

      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      final payload = text.trim().isEmpty ? null : jsonDecode(text);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw BackendApiException(
          _errorMessage(payload) ?? 'درخواست سرور ناموفق بود.',
          statusCode: response.statusCode,
        );
      }

      return payload;
    } on BackendApiException {
      rethrow;
    } on FormatException catch (error) {
      throw BackendApiException('پاسخ سرور قابل خواندن نیست: $error');
    } on IOException catch (error) {
      throw BackendApiException('ارتباط با سرور برقرار نشد: $error');
    } finally {
      client.close(force: true);
    }
  }

  Future<BackendAuthResult> _authResultFromPayload(Object? payload) async {
    final token = _findToken(payload);
    if (token == null) {
      throw const BackendApiException('توکن ورود در پاسخ سرور وجود ندارد.');
    }

    final userPayload = _findUserPayload(payload);
    final user = userPayload == null
        ? await currentUser(token)
        : _userFromPayload(userPayload);

    return BackendAuthResult(token: token, user: user);
  }
}

class BackendAuthResult {
  const BackendAuthResult({required this.token, required this.user});

  final String token;
  final MockUser user;
}

class AdminUsersPage {
  const AdminUsersPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<AdminUser> items;
  final int total;
  final int limit;
  final int offset;
}

class AdminUser {
  const AdminUser({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    this.fullName,
    this.avatarUrl,
    this.bio,
    this.createdAt,
  });

  final String id;
  final String username;
  final String email;
  final String role;
  final String? fullName;
  final String? avatarUrl;
  final String? bio;
  final DateTime? createdAt;

  String get displayName {
    final name = fullName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    if (username.isNotEmpty) {
      return username;
    }
    return email;
  }

  bool get isAdmin => role.toLowerCase().trim() == 'admin';
  String get displayNameWithRole =>
      isAdmin ? '$displayName 👨‍🏭' : displayName;
}

class AdminReviewsPage {
  const AdminReviewsPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<AdminReview> items;
  final int total;
  final int limit;
  final int offset;
}

class AdminReview {
  const AdminReview({
    required this.id,
    required this.titleId,
    required this.title,
    required this.userId,
    required this.username,
    required this.text,
    this.fullName,
    this.email,
    this.containsSpoiler = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String titleId;
  final String title;
  final String userId;
  final String username;
  final String text;
  final String? fullName;
  final String? email;
  final bool containsSpoiler;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get userDisplayName {
    final name = fullName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    if (username.isNotEmpty) {
      return username;
    }
    return email ?? 'کاربر';
  }
}

class BackendReviewSnapshot {
  const BackendReviewSnapshot({
    required this.text,
    required this.hasSpoiler,
    this.createdAt,
  });

  final String text;
  final bool hasSpoiler;
  final DateTime? createdAt;
}

class BackendApiException implements Exception {
  const BackendApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() {
    final status = statusCode;
    if (status == null) {
      return message;
    }
    return '$message ($status)';
  }
}

Map<String, Object?> _watchlistItemToServerJson(WatchlistItem item) {
  return {
    'title_id': item.id,
    'title': item.title,
    'year': item.year?.toString(),
    'poster_url': item.imageUrl,
    'media_type': item.type,
    'type': item.type,
    'status': item.status.storageValue,
    'favorite': item.favorite,
    'subtitle': item.subtitle,
    'rating': item.rating,
    'vote_count': item.voteCount,
    'can_have_episodes': item.canHaveEpisodes,
  };
}

Map<String, Object?> _titleMetadataJson(WatchlistItem item) {
  return {
    'title': item.title,
    'year': item.year?.toString(),
    'poster_url': item.imageUrl,
    'media_type': item.type,
  };
}

List<TitleSummary> _titleSummariesFromPayload(Object? payload) {
  final items = _extractList(payload, keys: const ['items', 'titles']);
  return items
      .whereType<Map>()
      .map((item) => _titleSummaryFromJson(item.cast<String, Object?>()))
      .where((title) => title.isValid)
      .toList();
}

TitleSummary _titleSummaryFromJson(Map<String, Object?> json) {
  return TitleSummary(
    id:
        _stringValue(json['id']) ??
        _stringValue(json['imdbId']) ??
        _stringValue(json['imdb_id']) ??
        '',
    title: _stringValue(json['title']) ?? 'Untitled',
    type: _stringValue(json['type'] ?? json['media_type']),
    year: _intValue(json['year'] ?? json['releaseYear']),
    endYear: _intValue(json['endYear'] ?? json['end_year']),
    imageUrl: _stringValue(
      json['imageUrl'] ?? json['image_url'] ?? json['poster'],
    ),
    rank: _intValue(json['rank']),
    subtitle: _stringValue(json['subtitle'] ?? json['plot']),
    rating: _doubleValue(json['rating'] ?? json['imdbRating']),
    voteCount: _intValue(json['voteCount'] ?? json['vote_count']),
    canHaveEpisodes:
        _boolValue(json['canHaveEpisodes'] ?? json['can_have_episodes']) ??
        false,
  );
}

TitleDetails _titleDetailsFromJson(Map<String, Object?> json) {
  final runtimeSeconds =
      _intValue(json['runtimeSeconds'] ?? json['runtime_seconds']) ??
      _runtimeSecondsFromMinutes(json['runtimeMinutes']);
  return TitleDetails(
    id:
        _stringValue(json['id']) ??
        _stringValue(json['imdbId']) ??
        _stringValue(json['imdb_id']) ??
        '',
    title: _stringValue(json['title']) ?? 'Untitled',
    originalTitle: _stringValue(
      json['originalTitle'] ?? json['original_title'],
    ),
    type: _stringValue(json['type'] ?? json['media_type']),
    canHaveEpisodes:
        _boolValue(json['canHaveEpisodes'] ?? json['can_have_episodes']) ??
        false,
    imageUrl: _stringValue(
      json['imageUrl'] ?? json['image_url'] ?? json['poster'],
    ),
    releaseYear: _intValue(json['releaseYear'] ?? json['release_year']),
    endYear: _intValue(json['endYear'] ?? json['end_year']),
    rating: _doubleValue(json['rating'] ?? json['imdbRating']),
    voteCount: _intValue(json['voteCount'] ?? json['vote_count']),
    runtimeSeconds: runtimeSeconds,
    certificate: _stringValue(json['certificate'] ?? json['rated']),
    genres: _stringListValue(json['genres'] ?? json['genre']),
    plot: _stringValue(json['plot'] ?? json['subtitle']),
    releaseDate: _stringValue(json['releaseDate'] ?? json['release_date']),
    productionStatus: _stringValue(
      json['productionStatus'] ?? json['production_status'],
    ),
    latestTrailerId: _stringValue(
      json['latestTrailerId'] ?? json['latest_trailer_id'],
    ),
  );
}

OmdbTitleDetails _omdbTitleDetailsFromJson(Map<String, Object?> json) {
  return OmdbTitleDetails(
    imdbId:
        _stringValue(json['imdbId']) ??
        _stringValue(json['imdbID']) ??
        _stringValue(json['id']) ??
        '',
    title: _stringValue(json['title'] ?? json['Title']) ?? 'Untitled',
    year: _stringValue(json['year'] ?? json['Year']),
    type: _stringValue(json['type'] ?? json['Type']),
    rated: _stringValue(json['rated'] ?? json['Rated']),
    released: _stringValue(json['released'] ?? json['Released']),
    runtime: _stringValue(json['runtime'] ?? json['Runtime']),
    genre: _stringValue(json['genre'] ?? json['Genre']),
    director: _stringValue(json['director'] ?? json['Director']),
    writer: _stringValue(json['writer'] ?? json['Writer']),
    actors: _stringValue(json['actors'] ?? json['Actors']),
    plot: _stringValue(json['plot'] ?? json['Plot']),
    language: _stringValue(json['language'] ?? json['Language']),
    country: _stringValue(json['country'] ?? json['Country']),
    awards: _stringValue(json['awards'] ?? json['Awards']),
    poster: _stringValue(json['poster'] ?? json['Poster'] ?? json['imageUrl']),
    imdbRating: _doubleValue(json['imdbRating']),
    imdbVotes: _stringValue(json['imdbVotes']),
    totalSeasons: _intValue(json['totalSeasons'] ?? json['total_seasons']),
  );
}

SeriesOverview _seriesOverviewFromJson(
  Map<String, Object?> json,
  String fallbackTitleId,
) {
  return SeriesOverview(
    titleId:
        _stringValue(json['titleId'] ?? json['title_id']) ?? fallbackTitleId,
    isOngoing: _boolValue(json['isOngoing'] ?? json['is_ongoing']) ?? false,
    totalEpisodes: _intValue(json['totalEpisodes'] ?? json['total_episodes']),
    latestSeasonNumber: _intValue(
      json['latestSeasonNumber'] ?? json['latest_season_number'],
    ),
    latestEpisodeNumber: _intValue(
      json['latestEpisodeNumber'] ?? json['latest_episode_number'],
    ),
    latestReleaseDate: _stringValue(
      json['latestReleaseDate'] ?? json['latest_release_date'],
    ),
    nextSeasonNumber: _intValue(
      json['nextSeasonNumber'] ?? json['next_season_number'],
    ),
    nextEpisodeNumber: _intValue(
      json['nextEpisodeNumber'] ?? json['next_episode_number'],
    ),
    nextReleaseDate: _stringValue(
      json['nextReleaseDate'] ?? json['next_release_date'],
    ),
  );
}

Episode _episodeFromJson(Map<String, Object?> json) {
  return Episode(
    id:
        _stringValue(json['id']) ??
        _stringValue(json['imdbId']) ??
        _stringValue(json['imdbID']) ??
        '',
    title: _stringValue(json['title']) ?? 'Untitled',
    seasonNumber: _intValue(json['seasonNumber'] ?? json['season_number']),
    episodeNumber: _intValue(json['episodeNumber'] ?? json['episode_number']),
    releaseDate: _stringValue(json['releaseDate'] ?? json['release_date']),
    plot: _stringValue(json['plot']),
    imageUrl: _stringValue(json['imageUrl'] ?? json['image_url']),
    rating: _doubleValue(json['rating'] ?? json['imdbRating']),
    voteCount: _intValue(json['voteCount'] ?? json['vote_count']),
  );
}

WatchlistItem _watchlistItemFromJson(Map<String, Object?> json) {
  final now = DateTime.now();
  return WatchlistItem(
    id:
        _stringValue(json['title_id']) ??
        _stringValue(json['titleId']) ??
        _stringValue(json['imdb_id']) ??
        _stringValue(json['id']) ??
        '',
    title: _stringValue(json['title']) ?? '',
    type: _stringValue(json['media_type'] ?? json['type']),
    year: _intValue(json['year']),
    imageUrl: _stringValue(json['poster_url'] ?? json['imageUrl']),
    subtitle: _stringValue(json['subtitle']),
    rating: _doubleValue(json['official_rating']),
    voteCount: _intValue(json['vote_count'] ?? json['voteCount']),
    canHaveEpisodes: _boolValue(json['can_have_episodes']) ?? false,
    status: WatchStatus.fromStorage(_stringValue(json['status'])),
    favorite: _boolValue(json['favorite']) ?? false,
    watchedEpisodeIds: _stringSetValue(
      json['watched_episode_ids'] ??
          json['watchedEpisodeIds'] ??
          json['episode_ids'] ??
          json['episodes'],
    ),
    addedAt: _dateValue(json['created_at'] ?? json['addedAt']) ?? now,
    updatedAt: _dateValue(json['updated_at'] ?? json['updatedAt']),
  );
}

LocalTitleReview _reviewFromJson(Map<String, Object?> json) {
  final userId =
      _stringValue(json['user_id']) ??
      _stringValue(json['userId']) ??
      _stringValue(json['username']) ??
      '';
  return LocalTitleReview(
    userId: userId,
    userDisplayName:
        _stringValue(json['full_name']) ??
        _stringValue(json['displayName']) ??
        _stringValue(json['username']) ??
        'کاربر',
    text: _stringValue(json['text'] ?? json['review']) ?? '',
    userRating: _intValue(json['rating'] ?? json['user_rating']),
    hasSpoiler: _boolValue(json['contains_spoiler']) ?? false,
    createdAt: _dateValue(json['created_at'] ?? json['createdAt']),
  );
}

AdminUser _adminUserFromJson(Map<String, Object?> json) {
  return AdminUser(
    id:
        _stringValue(json['id']) ??
        _stringValue(json['user_id']) ??
        _stringValue(json['username']) ??
        '',
    username: _stringValue(json['username']) ?? '',
    email: _stringValue(json['email']) ?? '',
    role: _stringValue(json['role']) ?? 'user',
    fullName:
        _stringValue(json['full_name']) ??
        _stringValue(json['display_name']) ??
        _stringValue(json['displayName']) ??
        _stringValue(json['name']),
    avatarUrl: _stringValue(
      json['avatar_url'] ??
          json['profile_image_url'] ??
          json['profileImageUrl'],
    ),
    bio: _stringValue(json['bio']),
    createdAt: _dateValue(json['created_at'] ?? json['createdAt']),
  );
}

AdminReview _adminReviewFromJson(Map<String, Object?> json) {
  return AdminReview(
    id:
        _stringValue(json['id']) ??
        _stringValue(json['review_id']) ??
        _stringValue(json['reviewId']) ??
        '',
    titleId:
        _stringValue(json['title_id']) ??
        _stringValue(json['titleId']) ??
        _stringValue(json['imdb_id']) ??
        '',
    title: _stringValue(json['title']) ?? 'بدون عنوان',
    userId:
        _stringValue(json['user_id']) ??
        _stringValue(json['userId']) ??
        _stringValue(json['username']) ??
        '',
    username: _stringValue(json['username']) ?? '',
    fullName:
        _stringValue(json['full_name']) ??
        _stringValue(json['display_name']) ??
        _stringValue(json['displayName']),
    email: _stringValue(json['email']),
    text: _stringValue(json['text'] ?? json['review']) ?? '',
    containsSpoiler: _boolValue(json['contains_spoiler']) ?? false,
    createdAt: _dateValue(json['created_at'] ?? json['createdAt']),
    updatedAt: _dateValue(json['updated_at'] ?? json['updatedAt']),
  );
}

MockUser _userFromPayload(Object? payload) {
  final json = payload is Map ? payload.cast<String, Object?>() : null;
  if (json == null) {
    throw const BackendApiException('اطلاعات کاربر در پاسخ سرور وجود ندارد.');
  }

  final id =
      _stringValue(json['id']) ??
      _stringValue(json['user_id']) ??
      _stringValue(json['username']) ??
      _stringValue(json['email']) ??
      '';
  final username =
      _stringValue(json['username']) ??
      _stringValue(json['email'])?.split('@').first ??
      id;
  final displayName =
      _stringValue(json['full_name']) ??
      _stringValue(json['display_name']) ??
      _stringValue(json['displayName']) ??
      _stringValue(json['name']) ??
      username;

  return MockUser(
    id: 'server_$id',
    displayName: displayName,
    username: username,
    email: _stringValue(json['email']),
    profileImageUrl: _stringValue(
      json['avatar_url'] ??
          json['profile_image_url'] ??
          json['profileImageUrl'],
    ),
    bio: _stringValue(json['bio']),
    createdAt: _dateValue(json['created_at'] ?? json['createdAt']),
    role: _stringValue(json['role']) ?? 'user',
  );
}

String? _findToken(Object? payload) {
  if (payload is! Map) {
    return null;
  }
  final json = payload.cast<String, Object?>();
  final token = _stringValue(
    json['access_token'] ?? json['token'] ?? json['jwt'],
  );
  if (token != null && token.isNotEmpty) {
    return token;
  }
  final data = json['data'];
  return data is Map ? _findToken(data) : null;
}

Object? _findUserPayload(Object? payload) {
  if (payload is! Map) {
    return null;
  }
  final json = payload.cast<String, Object?>();
  final user = json['user'];
  if (user is Map) {
    return user;
  }
  final data = json['data'];
  if (data is Map) {
    return _findUserPayload(data);
  }
  return null;
}

List<Object?> _extractList(Object? payload, {required List<String> keys}) {
  if (payload is List) {
    return payload;
  }
  if (payload is Map) {
    final json = payload.cast<String, Object?>();
    for (final key in keys) {
      final value = json[key];
      if (value is List) {
        return value;
      }
    }
  }
  return const [];
}

Map<String, Object?>? _mapValue(Object? value) {
  if (value is Map) {
    return value.cast<String, Object?>();
  }
  return null;
}

List<String> _stringListValue(Object? value) {
  if (value is List) {
    return value
        .map(_stringValue)
        .whereType<String>()
        .where((item) => item.isNotEmpty)
        .toList();
  }
  final text = _stringValue(value);
  if (text == null) {
    return const [];
  }
  return text
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

List<Object> _objectListValue(Object? value) {
  if (value is List) {
    return value.whereType<Object>().toList();
  }
  if (value is Object) {
    return [value];
  }
  return const [];
}

int? _runtimeSecondsFromMinutes(Object? value) {
  final minutes = _intValue(value);
  return minutes == null ? null : minutes * 60;
}

String? _errorMessage(Object? payload) {
  if (payload is Map) {
    final json = payload.cast<String, Object?>();
    final detail = json['detail'];
    if (detail is String) {
      return detail;
    }
    if (detail is List && detail.isNotEmpty) {
      final message = _validationMessage(detail);
      if (message != null) {
        return message;
      }
      return detail.map((item) => item.toString()).join('\n');
    }
    return _stringValue(json['message'] ?? json['error']);
  }
  return _stringValue(payload);
}

Map<String, Object?> _registrationDraftJson(
  RegistrationDraft draft, {
  required String emailOverride,
}) {
  return {
    'full_name': draft.displayName.trim(),
    'display_name': draft.displayName.trim(),
    'name': draft.displayName.trim(),
    'username': draft.username.trim(),
    'email': emailOverride,
    'password': draft.password,
    'avatar_url': _blankToNull(draft.profileImageUrl),
    'profile_image_url': _blankToNull(draft.profileImageUrl),
    'bio': _blankToNull(draft.bio),
  };
}

bool _shouldRetryRegistrationConfirm(BackendApiException error) {
  if (error.statusCode == 422) {
    return true;
  }
  final text = error.message.toLowerCase();
  return text.contains('missing') ||
      text.contains('field required') ||
      text.contains('فیلد');
}

String? _validationMessage(List<Object?> detail) {
  final missingFields = <String>[];
  final messages = <String>[];

  for (final item in detail) {
    if (item is! Map) {
      continue;
    }
    final json = item.cast<String, Object?>();
    final type = _stringValue(json['type'])?.toLowerCase();
    final msg = _stringValue(json['msg']);
    final field = _validationFieldName(json['loc']);
    if (type == 'missing') {
      if (field != null) {
        missingFields.add(field);
      }
      continue;
    }
    if (msg != null) {
      messages.add(field == null ? msg : '$field: $msg');
    }
  }

  if (missingFields.isNotEmpty) {
    return 'چند فیلد لازم به سرور ارسال نشده است: ${missingFields.join('، ')}. دوباره کد تایید بگیر و ثبت نام را کامل کن.';
  }
  if (messages.isNotEmpty) {
    return messages.join('\n');
  }
  return null;
}

String? _validationFieldName(Object? loc) {
  if (loc is List && loc.isNotEmpty) {
    final parts = loc.map(_stringValue).whereType<String>().toList();
    if (parts.isEmpty) {
      return null;
    }
    return parts.last;
  }
  return _stringValue(loc);
}

String? _stringValue(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty || text == 'N/A' ? null : text;
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

double? _doubleValue(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '');
}

bool? _boolValue(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  final text = value?.toString().toLowerCase().trim();
  if (text == 'true' || text == '1') {
    return true;
  }
  if (text == 'false' || text == '0') {
    return false;
  }
  return null;
}

DateTime? _dateValue(Object? value) {
  final text = _stringValue(value);
  return text == null ? null : DateTime.tryParse(text);
}

Set<String> _stringSetValue(Object? value) {
  if (value is List) {
    return value
        .map(_stringValue)
        .whereType<String>()
        .where((item) => item.isNotEmpty)
        .toSet();
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return const <String>{};
    }
    if (trimmed.startsWith('[')) {
      try {
        return _stringSetValue(jsonDecode(trimmed));
      } on FormatException {
        return const <String>{};
      }
    }
    return trimmed
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
  }
  return const <String>{};
}

String? _blankToNull(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}

String _queryPath(String path, Map<String, Object?> queryParameters) {
  final sanitized = <String, String>{};
  for (final entry in queryParameters.entries) {
    final value = entry.value;
    if (value == null) {
      continue;
    }
    final text = value.toString().trim();
    if (text.isNotEmpty) {
      sanitized[entry.key] = text;
    }
  }
  return Uri(
    path: path,
    queryParameters: sanitized.isEmpty ? null : sanitized,
  ).toString();
}

String? _dateParameter(DateTime? value) {
  if (value == null) {
    return null;
  }
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

String _normalizeBaseUrl(String? value) {
  final text = (value ?? '').trim();
  if (text.endsWith('/')) {
    return text.substring(0, text.length - 1);
  }
  return text;
}

int _compareReviews(LocalTitleReview a, LocalTitleReview b) {
  final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  return bTime.compareTo(aTime);
}
