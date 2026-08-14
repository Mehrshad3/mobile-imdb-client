import 'json_read.dart';

class SeriesOverview {
  const SeriesOverview({
    required this.titleId,
    this.isOngoing = false,
    this.totalEpisodes,
    this.latestSeasonNumber,
    this.latestEpisodeNumber,
    this.latestReleaseDate,
    this.nextSeasonNumber,
    this.nextEpisodeNumber,
    this.nextReleaseDate,
  });

  final String titleId;
  final bool isOngoing;
  final int? totalEpisodes;
  final int? latestSeasonNumber;
  final int? latestEpisodeNumber;
  final String? latestReleaseDate;
  final int? nextSeasonNumber;
  final int? nextEpisodeNumber;
  final String? nextReleaseDate;

  factory SeriesOverview.fromHeroSubNav(String titleId, JsonMap json) {
    final episodes = asMap(readPath(json, ['data', 'title', 'episodes']));
    final latestNode = _firstEdgeNode(episodes?['TMD_Hero_MostRecentEpisode']);
    final nextNode = _firstEdgeNode(episodes?['TMD_Hero_NextEpisode']);

    return SeriesOverview(
      titleId: titleId,
      isOngoing: asBool(episodes?['isOngoing']) ?? false,
      totalEpisodes: asInt(
        readPath(episodes, ['TMD_Hero_EpisodeCount', 'total']),
      ),
      latestSeasonNumber: asInt(
        readPath(latestNode, ['series', 'episodeNumber', 'seasonNumber']),
      ),
      latestEpisodeNumber: asInt(
        readPath(latestNode, ['series', 'episodeNumber', 'episodeNumber']),
      ),
      latestReleaseDate: readReleaseDate(latestNode?['releaseDate']),
      nextSeasonNumber: asInt(
        readPath(nextNode, ['series', 'episodeNumber', 'seasonNumber']),
      ),
      nextEpisodeNumber: asInt(
        readPath(nextNode, ['series', 'episodeNumber', 'episodeNumber']),
      ),
      nextReleaseDate: readReleaseDate(nextNode?['releaseDate']),
    );
  }
}

JsonMap? _firstEdgeNode(Object? connection) {
  final edges = asList(readPath(connection, ['edges']));
  if (edges.isEmpty) {
    return null;
  }
  return asMap(readPath(edges.first, ['node']));
}
