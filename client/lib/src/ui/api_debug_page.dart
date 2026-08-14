import 'package:flutter/material.dart';

import '../api/imdb_api_exception.dart';
import '../models/episode.dart';
import '../models/series_overview.dart';
import '../models/title_details.dart';
import '../models/title_summary.dart';
import '../repositories/imdb_repository.dart';

class ApiDebugPage extends StatefulWidget {
  const ApiDebugPage({super.key});

  @override
  State<ApiDebugPage> createState() => _ApiDebugPageState();
}

class _ApiDebugPageState extends State<ApiDebugPage> {
  late final ImdbRepository _repository;

  final TextEditingController _queryController = TextEditingController(
    text: 'young sheldon',
  );
  final TextEditingController _titleIdController = TextEditingController(
    text: 'tt6226232',
  );
  final TextEditingController _seasonController = TextEditingController(
    text: '1',
  );

  bool _loading = false;
  String? _error;
  String _summary = 'برای تست API یکی از دکمه‌ها را بزن.';
  List<TitleSummary> _titles = const [];
  List<TitleDetails> _details = const [];
  List<Episode> _episodes = const [];
  SeriesOverview? _seriesOverview;

  @override
  void initState() {
    super.initState();
    _repository = ImdbRepository();
  }

  @override
  void dispose() {
    _repository.close();
    _queryController.dispose();
    _titleIdController.dispose();
    _seasonController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _titles = const [];
      _details = const [];
      _episodes = const [];
      _seriesOverview = null;
    });

    try {
      await action();
    } on ImdbApiException catch (error) {
      _setError(error.message);
    } catch (error) {
      _setError(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _setError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _error = message;
      _summary = 'درخواست ناموفق بود.';
    });
  }

  Future<void> _search() {
    return _run(() async {
      final query = _queryController.text;
      final titles = await _repository.search(query);
      if (!mounted) {
        return;
      }
      setState(() {
        _titles = titles;
        _summary =
            '${titles.length} نتیجه از suggestion برای "$query" دریافت شد.';
      });
    });
  }

  Future<void> _trending() {
    return _run(() async {
      final titles = await _repository.trending();
      if (!mounted) {
        return;
      }
      setState(() {
        _titles = titles;
        _summary = '${titles.length} عنوان ترند دریافت شد.';
      });
    });
  }

  Future<void> _advancedSearch() {
    return _run(() async {
      final query = _queryController.text;
      final titles = await _repository.advancedSearch(query);
      if (!mounted) {
        return;
      }
      setState(() {
        _titles = titles;
        _summary =
            '${titles.length} نتیجه از AdvancedTitleSearch برای "$query" دریافت شد.';
      });
    });
  }

  Future<void> _metadata() {
    return _run(() async {
      final ids = _extractTitleIds(_titleIdController.text);
      if (ids.isEmpty) {
        throw const ImdbApiException('حداقل یک شناسه مثل tt6226232 وارد کن.');
      }

      final details = await _repository.titleDetails(ids);
      if (!mounted) {
        return;
      }
      setState(() {
        _details = details;
        _titles = details.map((item) => item.toSummary()).toList();
        _summary = '${details.length} جزئیات عنوان دریافت شد.';
      });
    });
  }

  Future<void> _series() {
    return _run(() async {
      final id = _titleIdController.text.trim();
      final overview = await _repository.seriesOverview(id);
      if (!mounted) {
        return;
      }
      setState(() {
        _seriesOverview = overview;
        _summary = 'خلاصه اپیزودهای سریال $id دریافت شد.';
      });
    });
  }

  Future<void> _episodesForSeason() {
    return _run(() async {
      final id = _titleIdController.text.trim();
      final season = int.tryParse(_seasonController.text.trim()) ?? 1;
      final episodes = await _repository.seasonEpisodes(id, season);
      if (!mounted) {
        return;
      }
      setState(() {
        _episodes = episodes;
        _summary = '${episodes.length} اپیزود برای فصل $season دریافت شد.';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('هسته API IMDb'),
          actions: [
            if (_loading)
              const Padding(
                padding: EdgeInsetsDirectional.only(end: 16),
                child: Center(
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ControlPanel(
                queryController: _queryController,
                titleIdController: _titleIdController,
                seasonController: _seasonController,
                loading: _loading,
                onSearch: _search,
                onTrending: _trending,
                onAdvancedSearch: _advancedSearch,
                onMetadata: _metadata,
                onSeries: _series,
                onEpisodes: _episodesForSeason,
              ),
              const SizedBox(height: 16),
              _StatusPanel(summary: _summary, error: _error, loading: _loading),
              const SizedBox(height: 12),
              if (_seriesOverview != null)
                _SeriesOverviewView(overview: _seriesOverview!),
              if (_details.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final details in _details) _TitleDetailsView(details),
              ],
              if (_episodes.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final episode in _episodes) _EpisodeTile(episode),
              ],
              if (_titles.isNotEmpty && _details.isEmpty) ...[
                const SizedBox(height: 12),
                for (final title in _titles) _TitleTile(title),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.queryController,
    required this.titleIdController,
    required this.seasonController,
    required this.loading,
    required this.onSearch,
    required this.onTrending,
    required this.onAdvancedSearch,
    required this.onMetadata,
    required this.onSeries,
    required this.onEpisodes,
  });

  final TextEditingController queryController;
  final TextEditingController titleIdController;
  final TextEditingController seasonController;
  final bool loading;
  final VoidCallback onSearch;
  final VoidCallback onTrending;
  final VoidCallback onAdvancedSearch;
  final VoidCallback onMetadata;
  final VoidCallback onSeries;
  final VoidCallback onEpisodes;

  @override
  Widget build(BuildContext context) {
    final onPressedSearch = loading ? null : onSearch;
    final onPressedTrending = loading ? null : onTrending;
    final onPressedAdvanced = loading ? null : onAdvancedSearch;
    final onPressedMetadata = loading ? null : onMetadata;
    final onPressedSeries = loading ? null : onSeries;
    final onPressedEpisodes = loading ? null : onEpisodes;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: queryController,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'عبارت جست‌وجو',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: titleIdController,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: 'شناسه IMDb',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.tag),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: seasonController,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'فصل',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const ValueKey('search-button'),
                onPressed: onPressedSearch,
                icon: const Icon(Icons.search),
                label: const Text('جست‌وجو'),
              ),
              OutlinedButton.icon(
                onPressed: onPressedTrending,
                icon: const Icon(Icons.trending_up),
                label: const Text('ترند'),
              ),
              OutlinedButton.icon(
                onPressed: onPressedAdvanced,
                icon: const Icon(Icons.tune),
                label: const Text('جست‌وجوی پیشرفته'),
              ),
              OutlinedButton.icon(
                onPressed: onPressedMetadata,
                icon: const Icon(Icons.info_outline),
                label: const Text('جزئیات عنوان'),
              ),
              OutlinedButton.icon(
                onPressed: onPressedSeries,
                icon: const Icon(Icons.live_tv),
                label: const Text('خلاصه سریال'),
              ),
              OutlinedButton.icon(
                onPressed: onPressedEpisodes,
                icon: const Icon(Icons.view_list),
                label: const Text('اپیزودها'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.summary,
    required this.error,
    required this.loading,
  });

  final String summary;
  final String? error;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: error == null ? colorScheme.outlineVariant : colorScheme.error,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 10),
          ],
          Text(summary, style: Theme.of(context).textTheme.titleSmall),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              textDirection: TextDirection.ltr,
              style: TextStyle(color: colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _TitleTile extends StatelessWidget {
  const _TitleTile(this.title);

  final TitleSummary title;

  @override
  Widget build(BuildContext context) {
    return _ResultBox(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Poster(url: title.imageUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                Text(
                  [
                    title.id,
                    if (title.type != null) title.type!,
                    if (title.yearLabel.isNotEmpty) title.yearLabel,
                    if (title.rank != null) 'Rank ${title.rank}',
                  ].join(' · '),
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (title.subtitle != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    title.subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (title.ratingLabel.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text('امتیاز: ${title.ratingLabel}'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleDetailsView extends StatelessWidget {
  const _TitleDetailsView(this.details);

  final TitleDetails details;

  @override
  Widget build(BuildContext context) {
    final runtime = details.runtimeMinutes == null
        ? null
        : '${details.runtimeMinutes} دقیقه';

    return _ResultBox(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Poster(url: details.imageUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  details.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    details.id,
                    if (details.type != null) details.type!,
                    if (details.yearLabel.isNotEmpty) details.yearLabel,
                    if (details.certificate != null) details.certificate!,
                    ?runtime,
                  ].join(' · '),
                  textDirection: TextDirection.ltr,
                ),
                if (details.genres.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('ژانرها: ${details.genres.join(', ')}'),
                ],
                if (details.rating != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'امتیاز: ${details.rating!.toStringAsFixed(1)}'
                    '${details.voteCount == null ? '' : ' (${details.voteCount})'}',
                  ),
                ],
                if (details.releaseDate != null) ...[
                  const SizedBox(height: 6),
                  Text('تاریخ انتشار: ${details.releaseDate}'),
                ],
                if (details.plot != null) ...[
                  const SizedBox(height: 8),
                  Text(details.plot!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SeriesOverviewView extends StatelessWidget {
  const _SeriesOverviewView({required this.overview});

  final SeriesOverview overview;

  @override
  Widget build(BuildContext context) {
    return _ResultBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'خلاصه سریال ${overview.titleId}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text('وضعیت: ${overview.isOngoing ? 'در حال پخش' : 'پایان‌یافته'}'),
          Text('تعداد کل اپیزودها: ${overview.totalEpisodes ?? '-'}'),
          Text(
            'آخرین اپیزود: ${_episodeNumber(overview.latestSeasonNumber, overview.latestEpisodeNumber)}'
            '${overview.latestReleaseDate == null ? '' : ' · ${overview.latestReleaseDate}'}',
            textDirection: TextDirection.ltr,
          ),
          Text(
            'اپیزود بعدی: ${_episodeNumber(overview.nextSeasonNumber, overview.nextEpisodeNumber)}'
            '${overview.nextReleaseDate == null ? '' : ' · ${overview.nextReleaseDate}'}',
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile(this.episode);

  final Episode episode;

  @override
  Widget build(BuildContext context) {
    return _ResultBox(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Poster(url: episode.imageUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${episode.numberLabel} · ${episode.title}',
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 5),
                Text(
                  [
                    episode.id,
                    if (episode.releaseDate != null) episode.releaseDate!,
                    if (episode.ratingLabel.isNotEmpty)
                      'Rating ${episode.ratingLabel}',
                  ].join(' · '),
                  textDirection: TextDirection.ltr,
                ),
                if (episode.plot != null) ...[
                  const SizedBox(height: 8),
                  Text(episode.plot!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(6);
    if (url == null) {
      return _PosterFallback(borderRadius: borderRadius);
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: Image.network(
        url!,
        width: 64,
        height: 92,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _PosterFallback(borderRadius: borderRadius),
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback({required this.borderRadius});

  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 92,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: borderRadius,
      ),
      child: const Icon(Icons.movie_outlined),
    );
  }
}

class _ResultBox extends StatelessWidget {
  const _ResultBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

List<String> _extractTitleIds(String value) {
  return RegExp(
    r'tt\d+',
  ).allMatches(value).map((match) => match.group(0)!).toSet().toList();
}

String _episodeNumber(int? season, int? episode) {
  if (season == null || episode == null) {
    return '-';
  }
  return 'S$season E$episode';
}
