import '../models/local_title_stats.dart';
import '../models/mock_user.dart';
import '../models/watchlist_item.dart';
import '../storage/watchlist_store.dart';

typedef UserWatchlistStoreFactory = WatchlistStore Function(MockUser user);
typedef LocalUsersProvider = Future<List<MockUser>> Function();

class LocalTitleStatsRepository {
  const LocalTitleStatsRepository({this.storeForUser, this.usersProvider});

  final UserWatchlistStoreFactory? storeForUser;
  final LocalUsersProvider? usersProvider;

  Future<LocalTitleStats> statsForTitle(String titleId) async {
    final normalizedId = titleId.trim();
    if (normalizedId.isEmpty) {
      return const LocalTitleStats();
    }

    var ratingCount = 0;
    var ratingTotal = 0;
    var reviewCount = 0;
    var favoriteCount = 0;
    var watchedCount = 0;
    final reviews = <LocalTitleReview>[];

    final users = usersProvider == null ? MockUser.all : await usersProvider!();
    for (final user in users) {
      final storeFactory = storeForUser ?? _defaultWatchlistStoreForUser;
      final items = await storeFactory(user).read();
      final item = _find(items, normalizedId);
      if (item == null) {
        continue;
      }
      final rating = item.userRating;
      if (rating != null) {
        ratingCount++;
        ratingTotal += rating;
      }
      if (item.hasReview) {
        reviewCount++;
        reviews.add(
          LocalTitleReview(
            userId: user.id,
            userDisplayName: user.displayName,
            text: item.reviewText!.trim(),
            userRating: rating,
            hasSpoiler: item.reviewHasSpoiler,
            createdAt: item.reviewCreatedAt,
          ),
        );
      }
      if (item.favorite) {
        favoriteCount++;
      }
      if (item.status == WatchStatus.watched) {
        watchedCount++;
      }
    }

    return LocalTitleStats(
      ratingCount: ratingCount,
      ratingTotal: ratingTotal,
      reviewCount: reviewCount,
      favoriteCount: favoriteCount,
      watchedCount: watchedCount,
      reviews: reviews..sort(_compareReviews),
    );
  }
}

WatchlistStore _defaultWatchlistStoreForUser(MockUser user) {
  return WatchlistStore(fileName: 'watchlist_${user.storageKey}.json');
}

int _compareReviews(LocalTitleReview a, LocalTitleReview b) {
  final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  return bTime.compareTo(aTime);
}

WatchlistItem? _find(List<WatchlistItem> items, String titleId) {
  for (final item in items) {
    if (item.id == titleId) {
      return item;
    }
  }
  return null;
}
