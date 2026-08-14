import 'episode.dart';
import 'json_read.dart';

class OmdbTitleDetails {
  const OmdbTitleDetails({
    required this.imdbId,
    required this.title,
    this.year,
    this.type,
    this.rated,
    this.released,
    this.runtime,
    this.genre,
    this.director,
    this.writer,
    this.actors,
    this.plot,
    this.language,
    this.country,
    this.awards,
    this.poster,
    this.imdbRating,
    this.imdbVotes,
    this.totalSeasons,
  });

  final String imdbId;
  final String title;
  final String? year;
  final String? type;
  final String? rated;
  final String? released;
  final String? runtime;
  final String? genre;
  final String? director;
  final String? writer;
  final String? actors;
  final String? plot;
  final String? language;
  final String? country;
  final String? awards;
  final String? poster;
  final double? imdbRating;
  final String? imdbVotes;
  final int? totalSeasons;

  factory OmdbTitleDetails.fromJson(JsonMap json) {
    return OmdbTitleDetails(
      imdbId: _clean(json['imdbID']) ?? '',
      title: _clean(json['Title']) ?? 'Untitled',
      year: _clean(json['Year']),
      type: _clean(json['Type']),
      rated: _clean(json['Rated']),
      released: _clean(json['Released']),
      runtime: _clean(json['Runtime']),
      genre: _clean(json['Genre']),
      director: _clean(json['Director']),
      writer: _clean(json['Writer']),
      actors: _clean(json['Actors']),
      plot: _clean(json['Plot']),
      language: _clean(json['Language']),
      country: _clean(json['Country']),
      awards: _clean(json['Awards']),
      poster: _clean(json['Poster']),
      imdbRating: asDouble(_clean(json['imdbRating'])),
      imdbVotes: _clean(json['imdbVotes']),
      totalSeasons: asInt(_clean(json['totalSeasons'])),
    );
  }

  bool get isSeries => type == 'series' || totalSeasons != null;

  int? get runtimeMinutes {
    final text = runtime;
    if (text == null) {
      return null;
    }
    final match = RegExp(r'\d+').firstMatch(text);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(0)!);
  }

  List<String> get genres => _splitList(genre);
  List<String> get directors => _splitList(director);
  List<String> get writers => _splitList(writer);
  List<String> get actorList => _splitList(actors);
}

class OmdbSeason {
  const OmdbSeason({
    required this.title,
    required this.seasonNumber,
    this.totalSeasons,
    this.episodes = const [],
  });

  final String title;
  final int seasonNumber;
  final int? totalSeasons;
  final List<Episode> episodes;

  factory OmdbSeason.fromJson(JsonMap json, int requestedSeason) {
    final seasonNumber = asInt(_clean(json['Season'])) ?? requestedSeason;
    final episodes = <Episode>[];

    for (final rawEpisode in asList(json['Episodes'])) {
      final map = asMap(rawEpisode);
      if (map == null) {
        continue;
      }
      final episode = _episodeFromOmdbJson(map, seasonNumber);
      if (episode.isValid) {
        episodes.add(episode);
      }
    }

    return OmdbSeason(
      title: _clean(json['Title']) ?? '',
      seasonNumber: seasonNumber,
      totalSeasons: asInt(_clean(json['totalSeasons'])),
      episodes: episodes,
    );
  }
}

Episode _episodeFromOmdbJson(JsonMap json, int seasonNumber) {
  return Episode(
    id: _clean(json['imdbID']) ?? '',
    title: _clean(json['Title']) ?? 'Untitled',
    seasonNumber: seasonNumber,
    episodeNumber: asInt(_clean(json['Episode'])),
    releaseDate: _clean(json['Released']),
    rating: asDouble(_clean(json['imdbRating'])),
  );
}

String? _clean(Object? value) {
  final text = asString(value);
  if (text == null || text == 'N/A') {
    return null;
  }
  return text;
}

List<String> _splitList(String? value) {
  if (value == null) {
    return const [];
  }
  return value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}
