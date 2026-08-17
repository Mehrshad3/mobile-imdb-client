import 'package:flutter/foundation.dart';

import '../api/backend_api_client.dart';
import '../models/title_details_bundle.dart';
import '../models/title_summary.dart';
import '../models/watchlist_item.dart';
import '../storage/watchlist_store.dart';

typedef AuthTokenProvider = String? Function();

class WatchlistRepository extends ChangeNotifier {
  WatchlistRepository({
    WatchlistStore? store,
    BackendApiClient? backendClient,
    AuthTokenProvider? authTokenProvider,
  }) : _store = store ?? WatchlistStore(),
       _serverClient = backendClient,
       _tokenProvider = authTokenProvider;

  WatchlistStore _store;
  final BackendApiClient? _serverClient;
  final AuthTokenProvider? _tokenProvider;
  final List<WatchlistItem> _items = [];

  bool _loaded = false;
  Future<void>? _loadFuture;

  List<WatchlistItem> get items => List.unmodifiable(_items);

  Future<void> switchStore(WatchlistStore store) async {
    _store = store;
    _loaded = false;
    _loadFuture = null;
    _items.clear();
    notifyListeners();
    await load();
  }

  Future<void> load() {
    if (_loaded) {
      return Future.value();
    }
    return _loadFuture ??= _load();
  }

  WatchlistItem? find(String titleId) {
    final normalizedId = titleId.trim();
    for (final item in _items) {
      if (item.id == normalizedId) {
        return item;
      }
    }
    return null;
  }

  bool contains(String titleId) {
    return find(titleId) != null;
  }

  Future<WatchlistItem> addOrUpdateFromBundle(
    TitleDetailsBundle bundle, {
    WatchStatus status = WatchStatus.planned,
    bool? favorite,
  }) {
    return addOrUpdateFromSummary(
      bundle.toSummary(),
      status: status,
      favorite: favorite,
      genres: bundle.genres,
      runtimeMinutes: bundle.runtimeMinutes,
    );
  }

  Future<WatchlistItem> addOrUpdateFromSummary(
    TitleSummary summary, {
    WatchStatus status = WatchStatus.planned,
    bool? favorite,
    List<String>? genres,
    int? runtimeMinutes,
  }) async {
    await load();
    final now = DateTime.now();
    final index = _items.indexWhere((item) => item.id == summary.id);
    final item = index == -1
        ? WatchlistItem.fromSummary(
            summary,
            status: status,
            favorite: favorite ?? false,
            now: now,
          ).copyWith(genres: genres, runtimeMinutes: runtimeMinutes)
        : _items[index].copyWith(
            title: summary.title,
            type: summary.type,
            year: summary.year,
            endYear: summary.endYear,
            imageUrl: summary.imageUrl,
            subtitle: summary.subtitle,
            rating: summary.rating,
            voteCount: summary.voteCount,
            genres: genres?.isEmpty ?? true ? _items[index].genres : genres,
            runtimeMinutes: runtimeMinutes ?? _items[index].runtimeMinutes,
            canHaveEpisodes: summary.canHaveEpisodes,
            status: _items[index].status,
            favorite: favorite ?? _items[index].favorite,
            updatedAt: now,
          );

    if (index == -1) {
      _items.insert(0, item);
    } else {
      _items[index] = item;
    }
    await _saveAndNotify();
    await _syncWatchlistItem(item);
    return item;
  }

  Future<void> remove(String titleId) async {
    await load();
    _items.removeWhere((item) => item.id == titleId);
    await _saveAndNotify();
    await _deleteWatchlistItemFromBackend(titleId);
  }

  Future<void> setStatus(String titleId, WatchStatus status) async {
    final item = await _update(
      titleId,
      (item) => item.copyWith(status: status, updatedAt: DateTime.now()),
    );
    if (item != null) {
      await _patchWatchlistItemOnBackend(item.id, status: status);
    }
  }

  Future<void> toggleFavorite(String titleId) async {
    final item = await _update(
      titleId,
      (item) =>
          item.copyWith(favorite: !item.favorite, updatedAt: DateTime.now()),
    );
    if (item != null) {
      await _patchWatchlistItemOnBackend(item.id, favorite: item.favorite);
    }
  }

  Future<void> togglePersonalList(
    String titleId,
    String listId, {
    bool? included,
  }) async {
    final normalizedListId = listId.trim();
    if (normalizedListId.isEmpty) {
      return;
    }

    await _update(titleId, (item) {
      final listIds = Set<String>.from(item.personalListIds);
      final shouldInclude = included ?? !listIds.contains(normalizedListId);
      if (shouldInclude) {
        listIds.add(normalizedListId);
      } else {
        listIds.remove(normalizedListId);
      }
      return item.copyWith(personalListIds: listIds, updatedAt: DateTime.now());
    });
  }

  Future<void> removePersonalListFromItems(String listId) async {
    await load();
    var changed = false;
    for (var index = 0; index < _items.length; index++) {
      final item = _items[index];
      if (!item.personalListIds.contains(listId)) {
        continue;
      }
      final listIds = Set<String>.from(item.personalListIds)..remove(listId);
      _items[index] = item.copyWith(
        personalListIds: listIds,
        updatedAt: DateTime.now(),
      );
      changed = true;
    }
    if (changed) {
      await _saveAndNotify();
    }
  }

  Future<void> setUserRating(String titleId, int? rating) async {
    final item = await _update(titleId, (item) {
      final normalizedRating = rating?.clamp(1, 10);
      return item.copyWith(
        userRating: normalizedRating,
        updatedAt: DateTime.now(),
      );
    });
    if (item != null) {
      await _syncRating(item);
    }
  }

  Future<void> setReview(
    String titleId, {
    required String text,
    required bool hasSpoiler,
  }) async {
    final trimmed = text.trim();
    final item = await _update(titleId, (item) {
      return item.copyWith(
        reviewText: trimmed.isEmpty ? null : trimmed,
        reviewHasSpoiler: trimmed.isNotEmpty && hasSpoiler,
        reviewCreatedAt: trimmed.isEmpty ? null : DateTime.now(),
        updatedAt: DateTime.now(),
      );
    });
    if (item != null) {
      await _syncReview(item);
    }
  }

  Future<void> toggleEpisodeWatched(
    String titleId,
    String episodeId, {
    bool? watched,
  }) async {
    final normalizedEpisodeId = episodeId.trim();
    if (normalizedEpisodeId.isEmpty) {
      return;
    }

    final item = await _update(titleId, (item) {
      final episodeIds = Set<String>.from(item.watchedEpisodeIds);
      final shouldMarkWatched =
          watched ?? !episodeIds.contains(normalizedEpisodeId);
      if (shouldMarkWatched) {
        episodeIds.add(normalizedEpisodeId);
      } else {
        episodeIds.remove(normalizedEpisodeId);
      }
      final nextStatus =
          item.status == WatchStatus.planned && episodeIds.isNotEmpty
          ? WatchStatus.watching
          : item.status;
      return item.copyWith(
        watchedEpisodeIds: episodeIds,
        status: nextStatus,
        updatedAt: DateTime.now(),
      );
    });
    if (item != null) {
      final isWatched = item.watchedEpisodeIds.contains(normalizedEpisodeId);
      await _syncEpisodeProgress(item, normalizedEpisodeId, isWatched);
      if (item.status == WatchStatus.watching) {
        await _patchWatchlistItemOnBackend(item.id, status: item.status);
      }
    }
  }

  Future<WatchlistItem?> _update(
    String titleId,
    WatchlistItem Function(WatchlistItem item) update,
  ) async {
    await load();
    final index = _items.indexWhere((item) => item.id == titleId);
    if (index == -1) {
      return null;
    }
    _items[index] = update(_items[index]);
    final item = _items[index];
    await _saveAndNotify();
    return item;
  }

  Future<void> _load() async {
    final token = _authToken;
    final backend = _serverClient;
    if (backend != null && backend.isConfigured && token != null) {
      try {
        final loadedItems = await backend.watchlist(token);
        final ratings = await _readBackendPart(
          'ratings load',
          () => backend.myRatings(token),
          <String, int>{},
        );
        final reviews = await _readBackendPart(
          'reviews load',
          () => backend.myReviews(token),
          <String, BackendReviewSnapshot>{},
        );
        final progress = await _readBackendPart(
          'progress load',
          () => backend.watchProgress(token),
          <String, Set<String>>{},
        );
        _items
          ..clear()
          ..addAll(
            _sorted(_mergeFeedback(loadedItems, ratings, reviews, progress)),
          );
        _loaded = true;
        notifyListeners();
        return;
      } catch (error) {
        debugPrint('Backend watchlist load failed: $error');
      }
    }

    final loadedItems = await _store.read();
    _items
      ..clear()
      ..addAll(_sorted(loadedItems));
    _loaded = true;
    notifyListeners();
  }

  Future<void> _saveAndNotify() async {
    final sortedItems = _sorted(_items);
    _items
      ..clear()
      ..addAll(sortedItems);
    await _store.write(_items);
    notifyListeners();
  }

  String? get _authToken {
    final token = _tokenProvider?.call()?.trim();
    return token == null || token.isEmpty ? null : token;
  }

  Future<void> _syncWatchlistItem(WatchlistItem item) async {
    final token = _authToken;
    final backend = _serverClient;
    if (backend == null || !backend.isConfigured || token == null) {
      return;
    }
    try {
      await backend.saveWatchlistItem(token, item);
    } catch (error) {
      debugPrint('Backend watchlist save failed: $error');
    }
  }

  Future<void> _patchWatchlistItemOnBackend(
    String titleId, {
    WatchStatus? status,
    bool? favorite,
  }) async {
    final token = _authToken;
    final backend = _serverClient;
    if (backend == null || !backend.isConfigured || token == null) {
      return;
    }
    try {
      await backend.patchWatchlistItem(
        token,
        titleId,
        status: status,
        favorite: favorite,
      );
    } catch (error) {
      debugPrint('Backend watchlist patch failed: $error');
    }
  }

  Future<void> _deleteWatchlistItemFromBackend(String titleId) async {
    final token = _authToken;
    final backend = _serverClient;
    if (backend == null || !backend.isConfigured || token == null) {
      return;
    }
    try {
      await backend.deleteWatchlistItem(token, titleId);
    } catch (error) {
      debugPrint('Backend watchlist delete failed: $error');
    }
  }

  Future<void> _syncRating(WatchlistItem item) async {
    final token = _authToken;
    final backend = _serverClient;
    if (backend == null || !backend.isConfigured || token == null) {
      return;
    }
    try {
      final rating = item.userRating;
      if (rating == null) {
        await backend.deleteRating(token, item.id);
      } else {
        await backend.saveRating(token, item, rating);
      }
    } catch (error) {
      debugPrint('Backend rating sync failed: $error');
    }
  }

  Future<void> _syncReview(WatchlistItem item) async {
    final token = _authToken;
    final backend = _serverClient;
    if (backend == null || !backend.isConfigured || token == null) {
      return;
    }
    try {
      final text = item.reviewText?.trim() ?? '';
      if (text.isEmpty) {
        await backend.deleteReview(token, item.id);
      } else {
        await backend.saveReview(
          token,
          item,
          text: text,
          hasSpoiler: item.reviewHasSpoiler,
        );
      }
    } catch (error) {
      debugPrint('Backend review sync failed: $error');
    }
  }

  Future<void> _syncEpisodeProgress(
    WatchlistItem item,
    String episodeId,
    bool watched,
  ) async {
    final token = _authToken;
    final backend = _serverClient;
    if (backend == null || !backend.isConfigured || token == null) {
      return;
    }
    try {
      await backend.setEpisodeWatched(token, item, episodeId, watched: watched);
    } catch (error) {
      debugPrint('Backend episode progress sync failed: $error');
    }
  }
}

List<WatchlistItem> _sorted(Iterable<WatchlistItem> items) {
  final sorted = items.toList();
  sorted.sort((a, b) {
    final aTime = a.updatedAt ?? a.addedAt;
    final bTime = b.updatedAt ?? b.addedAt;
    return bTime.compareTo(aTime);
  });
  return sorted;
}

List<WatchlistItem> _mergeFeedback(
  List<WatchlistItem> items,
  Map<String, int> ratings,
  Map<String, BackendReviewSnapshot> reviews,
  Map<String, Set<String>> progress,
) {
  return [
    for (final item in items)
      item.copyWith(
        userRating: ratings[item.id],
        reviewText: reviews[item.id]?.text,
        reviewHasSpoiler: reviews[item.id]?.hasSpoiler ?? false,
        reviewCreatedAt: reviews[item.id]?.createdAt,
        watchedEpisodeIds: progress[item.id] ?? item.watchedEpisodeIds,
      ),
  ];
}

Future<T> _readBackendPart<T>(
  String label,
  Future<T> Function() load,
  T fallback,
) async {
  try {
    return await load();
  } catch (error) {
    debugPrint('Backend $label failed: $error');
    return fallback;
  }
}
