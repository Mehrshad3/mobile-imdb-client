import 'json_read.dart';

class Episode {
  const Episode({
    required this.id,
    required this.title,
    this.seasonNumber,
    this.episodeNumber,
    this.releaseDate,
    this.plot,
    this.imageUrl,
    this.rating,
    this.voteCount,
  });

  final String id;
  final String title;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? releaseDate;
  final String? plot;
  final String? imageUrl;
  final double? rating;
  final int? voteCount;

  factory Episode.fromNode(JsonMap json) {
    final ratings = asMap(json['ratingsSummary']);
    final displayableEpisodeNumber = readPath(json, [
      'series',
      'displayableEpisodeNumber',
    ]);

    return Episode(
      id: asString(json['id']) ?? '',
      title: readTitleText(json) ?? 'Untitled',
      seasonNumber: asInt(
        readPath(displayableEpisodeNumber, ['displayableSeason', 'season']),
      ),
      episodeNumber: asInt(
        readPath(displayableEpisodeNumber, ['episodeNumber', 'episodeNumber']),
      ),
      releaseDate: readReleaseDate(json['releaseDate']),
      plot: readText(json['plot']),
      imageUrl: readImageUrl(json),
      rating: asDouble(ratings?['aggregateRating']),
      voteCount: asInt(ratings?['voteCount']),
    );
  }

  String get numberLabel {
    final season = seasonNumber == null ? '?' : seasonNumber.toString();
    final episode = episodeNumber == null ? '?' : episodeNumber.toString();
    return 'S$season E$episode';
  }

  String get ratingLabel {
    if (rating == null) {
      return '';
    }
    final votes = voteCount == null ? '' : ' ($voteCount)';
    return '${rating!.toStringAsFixed(1)}$votes';
  }

  bool get isValid => id.isNotEmpty && title.isNotEmpty;
}
