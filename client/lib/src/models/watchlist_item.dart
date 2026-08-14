import 'title_summary.dart';

enum WatchStatus {
  planned('planned'),
  watching('watching'),
  watched('watched'),
  stopped('stopped'),
  dropped('dropped');

  const WatchStatus(this.storageValue);

  final String storageValue;

  static WatchStatus fromStorage(String? value) {
    return WatchStatus.values.firstWhere(
      (status) => status.storageValue == value,
      orElse: () => WatchStatus.planned,
    );
  }
}

const Object _unchanged = Object();

class WatchlistItem {
  const WatchlistItem({
    required this.id,
    required this.title,
    required this.addedAt,
    this.type,
    this.year,
    this.endYear,
    this.imageUrl,
    this.subtitle,
    this.rating,
    this.voteCount,
    this.genres = const <String>[],
    this.runtimeMinutes,
    this.canHaveEpisodes = false,
    this.status = WatchStatus.planned,
    this.favorite = false,
    this.personalListIds = const <String>{},
    this.userRating,
    this.reviewText,
    this.reviewHasSpoiler = false,
    this.reviewCreatedAt,
    this.watchedEpisodeIds = const <String>{},
    this.updatedAt,
  });

  final String id;
  final String title;
  final String? type;
  final int? year;
  final int? endYear;
  final String? imageUrl;
  final String? subtitle;
  final double? rating;
  final int? voteCount;
  final List<String> genres;
  final int? runtimeMinutes;
  final bool canHaveEpisodes;
  final WatchStatus status;
  final bool favorite;
  final Set<String> personalListIds;
  final int? userRating;
  final String? reviewText;
  final bool reviewHasSpoiler;
  final DateTime? reviewCreatedAt;
  final Set<String> watchedEpisodeIds;
  final DateTime addedAt;
  final DateTime? updatedAt;

  factory WatchlistItem.fromSummary(
    TitleSummary summary, {
    WatchStatus status = WatchStatus.planned,
    bool favorite = false,
    DateTime? now,
  }) {
    final createdAt = now ?? DateTime.now();
    return WatchlistItem(
      id: summary.id,
      title: summary.title,
      type: summary.type,
      year: summary.year,
      endYear: summary.endYear,
      imageUrl: summary.imageUrl,
      subtitle: summary.subtitle,
      rating: summary.rating,
      voteCount: summary.voteCount,
      canHaveEpisodes: summary.canHaveEpisodes,
      status: status,
      favorite: favorite,
      addedAt: createdAt,
      updatedAt: createdAt,
    );
  }

  factory WatchlistItem.fromJson(Map<String, Object?> json) {
    return WatchlistItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      type: json['type'] as String?,
      year: json['year'] as int?,
      endYear: json['endYear'] as int?,
      imageUrl: json['imageUrl'] as String?,
      subtitle: json['subtitle'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      voteCount: json['voteCount'] as int?,
      genres:
          (json['genres'] as List?)?.whereType<String>().toList() ?? const [],
      runtimeMinutes: json['runtimeMinutes'] as int?,
      canHaveEpisodes: json['canHaveEpisodes'] as bool? ?? false,
      status: WatchStatus.fromStorage(json['status'] as String?),
      favorite: json['favorite'] as bool? ?? false,
      personalListIds:
          (json['personalListIds'] as List?)?.whereType<String>().toSet() ??
          const <String>{},
      userRating: json['userRating'] as int?,
      reviewText: json['reviewText'] as String?,
      reviewHasSpoiler: json['reviewHasSpoiler'] as bool? ?? false,
      reviewCreatedAt: _readDate(json['reviewCreatedAt']),
      watchedEpisodeIds:
          (json['watchedEpisodeIds'] as List?)?.whereType<String>().toSet() ??
          const <String>{},
      addedAt: _readDate(json['addedAt']) ?? DateTime.now(),
      updatedAt: _readDate(json['updatedAt']),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'title': title,
      'type': type,
      'year': year,
      'endYear': endYear,
      'imageUrl': imageUrl,
      'subtitle': subtitle,
      'rating': rating,
      'voteCount': voteCount,
      'genres': genres,
      'runtimeMinutes': runtimeMinutes,
      'canHaveEpisodes': canHaveEpisodes,
      'status': status.storageValue,
      'favorite': favorite,
      'personalListIds': personalListIds.toList()..sort(),
      'userRating': userRating,
      'reviewText': reviewText,
      'reviewHasSpoiler': reviewHasSpoiler,
      'reviewCreatedAt': reviewCreatedAt?.toIso8601String(),
      'watchedEpisodeIds': watchedEpisodeIds.toList()..sort(),
      'addedAt': addedAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  WatchlistItem copyWith({
    String? title,
    String? type,
    int? year,
    int? endYear,
    String? imageUrl,
    String? subtitle,
    double? rating,
    int? voteCount,
    List<String>? genres,
    Object? runtimeMinutes = _unchanged,
    bool? canHaveEpisodes,
    WatchStatus? status,
    bool? favorite,
    Set<String>? personalListIds,
    Object? userRating = _unchanged,
    Object? reviewText = _unchanged,
    bool? reviewHasSpoiler,
    Object? reviewCreatedAt = _unchanged,
    Set<String>? watchedEpisodeIds,
    DateTime? updatedAt,
  }) {
    return WatchlistItem(
      id: id,
      title: title ?? this.title,
      type: type ?? this.type,
      year: year ?? this.year,
      endYear: endYear ?? this.endYear,
      imageUrl: imageUrl ?? this.imageUrl,
      subtitle: subtitle ?? this.subtitle,
      rating: rating ?? this.rating,
      voteCount: voteCount ?? this.voteCount,
      genres: genres ?? this.genres,
      runtimeMinutes: identical(runtimeMinutes, _unchanged)
          ? this.runtimeMinutes
          : runtimeMinutes as int?,
      canHaveEpisodes: canHaveEpisodes ?? this.canHaveEpisodes,
      status: status ?? this.status,
      favorite: favorite ?? this.favorite,
      personalListIds:
          personalListIds ?? Set<String>.from(this.personalListIds),
      userRating: identical(userRating, _unchanged)
          ? this.userRating
          : userRating as int?,
      reviewText: identical(reviewText, _unchanged)
          ? this.reviewText
          : reviewText as String?,
      reviewHasSpoiler: reviewHasSpoiler ?? this.reviewHasSpoiler,
      reviewCreatedAt: identical(reviewCreatedAt, _unchanged)
          ? this.reviewCreatedAt
          : reviewCreatedAt as DateTime?,
      watchedEpisodeIds:
          watchedEpisodeIds ?? Set<String>.from(this.watchedEpisodeIds),
      addedAt: addedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  TitleSummary toSummary() {
    return TitleSummary(
      id: id,
      title: title,
      type: type,
      year: year,
      endYear: endYear,
      imageUrl: imageUrl,
      subtitle: subtitle,
      rating: rating,
      voteCount: voteCount,
      canHaveEpisodes: canHaveEpisodes,
    );
  }

  String get yearLabel {
    if (year == null) {
      return '';
    }
    if (endYear == null || endYear == year) {
      return year.toString();
    }
    return '$year-$endYear';
  }

  bool get hasReview => reviewText != null && reviewText!.trim().isNotEmpty;
}

DateTime? _readDate(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}
