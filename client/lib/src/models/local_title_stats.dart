class LocalTitleStats {
  const LocalTitleStats({
    this.ratingCount = 0,
    this.ratingTotal = 0,
    this.averageRatingOverride,
    this.reviewCount = 0,
    this.favoriteCount = 0,
    this.watchedCount = 0,
    this.reviews = const <LocalTitleReview>[],
  });

  final int ratingCount;
  final int ratingTotal;
  final double? averageRatingOverride;
  final int reviewCount;
  final int favoriteCount;
  final int watchedCount;
  final List<LocalTitleReview> reviews;

  double? get averageRating {
    if (averageRatingOverride != null) {
      return averageRatingOverride;
    }
    if (ratingCount == 0) {
      return null;
    }
    return ratingTotal / ratingCount;
  }

  bool get hasAnyActivity {
    return ratingCount > 0 ||
        reviewCount > 0 ||
        favoriteCount > 0 ||
        watchedCount > 0;
  }
}

class LocalTitleReview {
  const LocalTitleReview({
    required this.userId,
    required this.userDisplayName,
    required this.text,
    this.userRating,
    this.hasSpoiler = false,
    this.createdAt,
  });

  final String userId;
  final String userDisplayName;
  final String text;
  final int? userRating;
  final bool hasSpoiler;
  final DateTime? createdAt;
}
