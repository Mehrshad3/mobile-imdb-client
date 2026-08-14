import 'package:flutter/foundation.dart';

import '../models/title_details_bundle.dart';
import '../models/title_summary.dart';
import '../models/watchlist_item.dart';
import '../storage/watchlist_store.dart';

class WatchlistRepository extends ChangeNotifier {
  WatchlistRepository({WatchlistStore? store})
    : _store = store ?? WatchlistStore();

  WatchlistStore _store;
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
    return item;
  }

  Future<void> remove(String titleId) async {
    await load();
    _items.removeWhere((item) => item.id == titleId);
    await _saveAndNotify();
  }

  Future<void> setStatus(String titleId, WatchStatus status) async {
    await load();
    final index = _items.indexWhere((item) => item.id == titleId);
    if (index == -1) {
      return;
    }
    _items[index] = _items[index].copyWith(
      status: status,
      updatedAt: DateTime.now(),
    );
    await _saveAndNotify();
  }

  Future<void> toggleFavorite(String titleId) async {
    await load();
    final index = _items.indexWhere((item) => item.id == titleId);
    if (index == -1) {
      return;
    }
    _items[index] = _items[index].copyWith(
      favorite: !_items[index].favorite,
      updatedAt: DateTime.now(),
    );
    await _saveAndNotify();
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
    await _update(titleId, (item) {
      final normalizedRating = rating?.clamp(1, 10);
      return item.copyWith(
        userRating: normalizedRating,
        updatedAt: DateTime.now(),
      );
    });
  }

  Future<void> setReview(
    String titleId, {
    required String text,
    required bool hasSpoiler,
  }) async {
    final trimmed = text.trim();
    await _update(titleId, (item) {
      return item.copyWith(
        reviewText: trimmed.isEmpty ? null : trimmed,
        reviewHasSpoiler: trimmed.isNotEmpty && hasSpoiler,
        reviewCreatedAt: trimmed.isEmpty ? null : DateTime.now(),
        updatedAt: DateTime.now(),
      );
    });
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

    await _update(titleId, (item) {
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
  }

  Future<void> _update(
    String titleId,
    WatchlistItem Function(WatchlistItem item) update,
  ) async {
    await load();
    final index = _items.indexWhere((item) => item.id == titleId);
    if (index == -1) {
      return;
    }
    _items[index] = update(_items[index]);
    await _saveAndNotify();
  }

  Future<void> _load() async {
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
