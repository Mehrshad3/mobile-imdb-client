import 'json_read.dart';
import 'title_summary.dart';

class TitleDetails {
  const TitleDetails({
    required this.id,
    required this.title,
    this.originalTitle,
    this.type,
    this.canHaveEpisodes = false,
    this.imageUrl,
    this.releaseYear,
    this.endYear,
    this.rating,
    this.voteCount,
    this.runtimeSeconds,
    this.certificate,
    this.genres = const [],
    this.plot,
    this.releaseDate,
    this.productionStatus,
    this.latestTrailerId,
  });

  final String id;
  final String title;
  final String? originalTitle;
  final String? type;
  final bool canHaveEpisodes;
  final String? imageUrl;
  final int? releaseYear;
  final int? endYear;
  final double? rating;
  final int? voteCount;
  final int? runtimeSeconds;
  final String? certificate;
  final List<String> genres;
  final String? plot;
  final String? releaseDate;
  final String? productionStatus;
  final String? latestTrailerId;

  factory TitleDetails.fromMetadata(JsonMap json) {
    final titleType = asMap(json['titleType']);
    final releaseYear = asMap(json['releaseYear']);
    final ratings = asMap(json['ratingsSummary']);
    final runtime = asMap(json['runtime']);
    final certificate = asMap(json['certificate']);
    final latestTrailer = asMap(json['latestTrailer']);
    final releaseDate = asMap(json['releaseDate']);

    return TitleDetails(
      id: asString(json['id']) ?? '',
      title: readTitleText(json) ?? 'Untitled',
      originalTitle: asString(readPath(json, ['originalTitleText', 'text'])),
      type:
          readText(titleType?['displayableProperty']) ??
          asString(titleType?['text']) ??
          asString(titleType?['id']),
      canHaveEpisodes: asBool(titleType?['canHaveEpisodes']) ?? false,
      imageUrl: readImageUrl(json),
      releaseYear: asInt(releaseYear?['year']),
      endYear: asInt(releaseYear?['endYear']),
      rating: asDouble(ratings?['aggregateRating']),
      voteCount: asInt(ratings?['voteCount']),
      runtimeSeconds: asInt(runtime?['seconds']),
      certificate: asString(certificate?['rating']),
      genres: _readGenres(json),
      plot: readText(json['plot']),
      releaseDate: readReleaseDate(releaseDate),
      productionStatus: readText(
        readPath(json, ['productionStatus', 'currentProductionStage']),
      ),
      latestTrailerId: asString(latestTrailer?['id']),
    );
  }

  int? get runtimeMinutes {
    if (runtimeSeconds == null) {
      return null;
    }
    return (runtimeSeconds! / 60).round();
  }

  String get yearLabel {
    if (releaseYear == null) {
      return '';
    }
    if (endYear == null || endYear == releaseYear) {
      return releaseYear.toString();
    }
    return '$releaseYear-$endYear';
  }

  TitleSummary toSummary() {
    return TitleSummary(
      id: id,
      title: title,
      type: type,
      year: releaseYear,
      endYear: endYear,
      imageUrl: imageUrl,
      rating: rating,
      voteCount: voteCount,
      canHaveEpisodes: canHaveEpisodes,
    );
  }
}

List<String> _readGenres(JsonMap json) {
  final rawGenres = asList(readPath(json, ['titleGenres', 'genres']));
  final genres = <String>[];

  for (final rawGenre in rawGenres) {
    final text = readText(rawGenre);
    if (text != null) {
      genres.add(text);
    }
  }
  return genres;
}
