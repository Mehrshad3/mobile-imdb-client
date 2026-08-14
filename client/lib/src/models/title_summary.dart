import 'json_read.dart';

class TitleSummary {
  const TitleSummary({
    required this.id,
    required this.title,
    this.type,
    this.year,
    this.endYear,
    this.imageUrl,
    this.rank,
    this.subtitle,
    this.rating,
    this.voteCount,
    this.canHaveEpisodes = false,
  });

  final String id;
  final String title;
  final String? type;
  final int? year;
  final int? endYear;
  final String? imageUrl;
  final int? rank;
  final String? subtitle;
  final double? rating;
  final int? voteCount;
  final bool canHaveEpisodes;

  factory TitleSummary.fromSuggestion(JsonMap json) {
    final type = asString(json['q']) ?? asString(json['qid']);
    final yearRange = asString(json['yr']);
    final canHaveEpisodes =
        asString(json['qid']) == 'tvSeries' ||
        (type?.toLowerCase().contains('tv') ?? false);

    return TitleSummary(
      id: asString(json['id']) ?? '',
      title: readTitleText(json) ?? 'Untitled',
      type: type,
      year: asInt(json['y']) ?? _firstYear(yearRange),
      endYear: _endYear(yearRange),
      imageUrl: readImageUrl(json),
      rank: asInt(json['rank']),
      subtitle: asString(json['s']),
      canHaveEpisodes: canHaveEpisodes,
    );
  }

  factory TitleSummary.fromTitleNode(JsonMap json, {int? rank}) {
    final titleType = asMap(json['titleType']);
    final releaseYear = asMap(json['releaseYear']);
    final ratings = asMap(json['ratingsSummary']);
    final yearRange = asString(json['yr']);
    final type =
        readText(titleType?['displayableProperty']) ??
        asString(titleType?['text']) ??
        asString(titleType?['id']) ??
        asString(json['q']) ??
        asString(json['qid']);

    return TitleSummary(
      id: asString(json['id']) ?? '',
      title: readTitleText(json) ?? 'Untitled',
      type: type,
      year:
          asInt(releaseYear?['year']) ??
          asInt(json['y']) ??
          _firstYear(yearRange),
      endYear: asInt(releaseYear?['endYear']) ?? _endYear(yearRange),
      imageUrl: readImageUrl(json),
      rank: rank ?? asInt(json['rank']),
      subtitle: asString(json['s']) ?? readText(json['plot']),
      rating: asDouble(ratings?['aggregateRating']),
      voteCount: asInt(ratings?['voteCount']),
      canHaveEpisodes: asBool(titleType?['canHaveEpisodes']) ?? false,
    );
  }

  factory TitleSummary.fromTrendingEdge(JsonMap edge) {
    final node = asMap(edge['node']) ?? edge;
    final itemNode = asMap(node['item']);
    final titleNode =
        asMap(itemNode?['title']) ?? itemNode ?? asMap(node['title']) ?? node;
    final rank =
        asInt(node['currentRank']) ??
        asInt(node['rank']) ??
        asInt(node['position']) ??
        asInt(edge['currentRank']) ??
        asInt(edge['rank']);

    return TitleSummary.fromTitleNode(titleNode, rank: rank);
  }

  factory TitleSummary.fromAdvancedEdge(JsonMap edge) {
    final node = asMap(edge['node']) ?? edge;
    final titleNode = asMap(node['title']) ?? asMap(node['item']) ?? node;
    final rank =
        asInt(node['position']) ??
        asInt(node['rank']) ??
        asInt(edge['position']) ??
        asInt(edge['rank']);

    return TitleSummary.fromTitleNode(titleNode, rank: rank);
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

  String get ratingLabel {
    if (rating == null) {
      return '';
    }
    final votes = voteCount == null ? '' : ' ($voteCount)';
    return '${rating!.toStringAsFixed(1)}$votes';
  }

  bool get isValid => id.isNotEmpty && title.isNotEmpty;
}

int? _firstYear(String? value) {
  if (value == null) {
    return null;
  }
  final match = RegExp(r'\d{4}').firstMatch(value);
  return match == null ? null : int.tryParse(match.group(0)!);
}

int? _endYear(String? value) {
  if (value == null) {
    return null;
  }
  final matches = RegExp(r'\d{4}').allMatches(value).toList();
  if (matches.length < 2) {
    return null;
  }
  return int.tryParse(matches[1].group(0)!);
}
