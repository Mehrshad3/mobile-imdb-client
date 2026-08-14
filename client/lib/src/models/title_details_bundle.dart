import 'omdb_title_details.dart';
import 'series_overview.dart';
import 'title_details.dart';
import 'title_summary.dart';

class TitleDetailsBundle {
  const TitleDetailsBundle({
    required this.summary,
    this.imdbDetails,
    this.omdbDetails,
    this.seriesOverview,
    this.errors = const [],
  });

  final TitleSummary summary;
  final TitleDetails? imdbDetails;
  final OmdbTitleDetails? omdbDetails;
  final SeriesOverview? seriesOverview;
  final List<Object> errors;

  String get id => imdbDetails?.id ?? omdbDetails?.imdbId ?? summary.id;

  String get title {
    return imdbDetails?.title ?? omdbDetails?.title ?? summary.title;
  }

  String? get originalTitle => imdbDetails?.originalTitle;

  String? get type {
    return imdbDetails?.type ?? omdbDetails?.type ?? summary.type;
  }

  String? get imageUrl {
    return imdbDetails?.imageUrl ?? summary.imageUrl ?? omdbDetails?.poster;
  }

  String get yearLabel {
    final imdbYear = imdbDetails?.yearLabel ?? '';
    if (imdbYear.isNotEmpty) {
      return imdbYear;
    }
    if (summary.yearLabel.isNotEmpty) {
      return summary.yearLabel;
    }
    return omdbDetails?.year ?? '';
  }

  String? get plot =>
      omdbDetails?.plot ?? imdbDetails?.plot ?? summary.subtitle;

  double? get rating {
    return imdbDetails?.rating ?? omdbDetails?.imdbRating ?? summary.rating;
  }

  int? get voteCount => imdbDetails?.voteCount ?? summary.voteCount;

  int? get runtimeMinutes {
    return imdbDetails?.runtimeMinutes ?? omdbDetails?.runtimeMinutes;
  }

  String? get certificate {
    return imdbDetails?.certificate ?? omdbDetails?.rated;
  }

  String? get releaseDate {
    return imdbDetails?.releaseDate ?? omdbDetails?.released;
  }

  List<String> get genres {
    if (imdbDetails != null && imdbDetails!.genres.isNotEmpty) {
      return imdbDetails!.genres;
    }
    return omdbDetails?.genres ?? const [];
  }

  bool get canHaveEpisodes {
    if (imdbDetails?.canHaveEpisodes ?? false) {
      return true;
    }
    if (omdbDetails?.isSeries ?? false) {
      return true;
    }
    if (summary.canHaveEpisodes) {
      return true;
    }
    final normalizedType = type?.toLowerCase() ?? '';
    return normalizedType.contains('series') || normalizedType.contains('tv');
  }

  int? get seasonCount {
    return omdbDetails?.totalSeasons ?? seriesOverview?.latestSeasonNumber;
  }

  bool get hasAnyDetails => imdbDetails != null || omdbDetails != null;

  TitleSummary toSummary() {
    return TitleSummary(
      id: id,
      title: title,
      type: type,
      year: summary.year,
      endYear: summary.endYear,
      imageUrl: imageUrl,
      subtitle: plot,
      rating: rating,
      voteCount: voteCount,
      canHaveEpisodes: canHaveEpisodes,
    );
  }
}
