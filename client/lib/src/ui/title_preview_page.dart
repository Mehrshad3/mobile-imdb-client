import 'package:flutter/material.dart';

import '../api/imdb_api_exception.dart';
import '../api/imdb_error_messages.dart';
import '../debug/imdb_search_debug_log.dart';
import '../models/episode.dart';
import '../models/local_title_stats.dart';
import '../models/series_overview.dart';
import '../models/title_details_bundle.dart';
import '../models/title_summary.dart';
import '../models/watchlist_item.dart';
import '../repositories/imdb_repository.dart';
import '../repositories/local_title_stats_repository.dart';
import '../repositories/mock_auth_repository.dart';
import '../repositories/watchlist_repository.dart';
import '../storage/watchlist_store.dart';
import 'cached_poster_image.dart';
import 'mock_login_sheet.dart';

class TitlePreviewPage extends StatefulWidget {
  const TitlePreviewPage({
    super.key,
    required this.summary,
    required this.repository,
    this.watchlistRepository,
    this.authRepository,
  });

  final TitleSummary summary;
  final ImdbRepository repository;
  final WatchlistRepository? watchlistRepository;
  final MockAuthRepository? authRepository;

  @override
  State<TitlePreviewPage> createState() => _TitlePreviewPageState();
}

class _TitlePreviewPageState extends State<TitlePreviewPage> {
  late final Future<TitleDetailsBundle> _bundleFuture;
  late final WatchlistRepository _watchlistRepository;
  late final bool _ownsWatchlistRepository;
  late final MockAuthRepository _authRepository;
  late final bool _ownsAuthRepository;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? MockAuthRepository();
    _ownsAuthRepository = widget.authRepository == null;
    _authRepository.addListener(_onAuthChanged);
    _watchlistRepository =
        widget.watchlistRepository ??
        WatchlistRepository(
          store: WatchlistStore(fileName: _watchlistFileName),
        );
    _ownsWatchlistRepository = widget.watchlistRepository == null;
    _authRepository.load();
    imdbSearchDebugLog(
      'TitlePreview.init id=${widget.summary.id} '
      'title="${widget.summary.title}"',
    );
    _bundleFuture = _loadBundle();
  }

  Future<TitleDetailsBundle> _loadBundle() async {
    final summary = widget.summary;
    imdbSearchDebugLog('TitlePreview.load -> id=${summary.id}');
    try {
      final bundle = await widget.repository.titleDetailsBundle(summary);
      imdbSearchDebugLog(
        'TitlePreview.load <- id=${bundle.id} title="${bundle.title}" '
        'hasAnyDetails=${bundle.hasAnyDetails} errors=${bundle.errors.length}',
      );
      return bundle;
    } catch (error) {
      imdbSearchDebugLog(
        'TitlePreview.load error id=${summary.id}: ${debugErrorSummary(error)}',
      );
      rethrow;
    }
  }

  void _onAuthChanged() {
    if (_ownsWatchlistRepository) {
      _watchlistRepository.switchStore(
        WatchlistStore(fileName: _watchlistFileName),
      );
    }
    if (mounted) {
      setState(() {});
    }
  }

  String get _watchlistFileName {
    final user = _authRepository.currentUser;
    return user == null
        ? 'watchlist_guest.json'
        : 'watchlist_${user.storageKey}.json';
  }

  @override
  void dispose() {
    _authRepository.removeListener(_onAuthChanged);
    if (_ownsAuthRepository) {
      _authRepository.dispose();
    }
    if (_ownsWatchlistRepository) {
      _watchlistRepository.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.summary.title)),
        body: SafeArea(
          child: FutureBuilder<TitleDetailsBundle>(
            future: _bundleFuture,
            builder: (context, snapshot) {
              final bundle = snapshot.data;
              final loading = snapshot.connectionState != ConnectionState.done;

              if (bundle == null && loading) {
                return _LoadingDetails(summary: widget.summary);
              }
              if (snapshot.hasError && bundle == null) {
                return _FatalError(
                  summary: widget.summary,
                  error: snapshot.error!,
                );
              }

              return _DetailsContent(
                bundle: bundle!,
                repository: widget.repository,
                watchlistRepository: _watchlistRepository,
                authRepository: _authRepository,
                loading: loading,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DetailsContent extends StatelessWidget {
  const _DetailsContent({
    required this.bundle,
    required this.repository,
    required this.watchlistRepository,
    required this.authRepository,
    required this.loading,
  });

  final TitleDetailsBundle bundle;
  final ImdbRepository repository;
  final WatchlistRepository watchlistRepository;
  final MockAuthRepository authRepository;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Header(bundle: bundle, watchlistRepository: watchlistRepository),
        const SizedBox(height: 12),
        _WatchlistActions(
          bundle: bundle,
          repository: watchlistRepository,
          authRepository: authRepository,
        ),
        if (loading) ...[
          const SizedBox(height: 14),
          const LinearProgressIndicator(),
        ],
        if (bundle.errors.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SourceWarning(errors: bundle.errors),
        ],
        const SizedBox(height: 18),
        if (bundle.plot != null) ...[
          _SectionTitle('خلاصه داستان', icon: Icons.subject),
          Text(bundle.plot!),
          const SizedBox(height: 18),
        ],
        _SectionTitle('اطلاعات اثر', icon: Icons.info_outline),
        _InfoGrid(rows: _detailRows(bundle)),
        if (bundle.canHaveEpisodes) ...[
          const SizedBox(height: 18),
          _SeriesSection(
            bundle: bundle,
            repository: repository,
            watchlistRepository: watchlistRepository,
            authRepository: authRepository,
          ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.bundle, required this.watchlistRepository});

  final TitleDetailsBundle bundle;
  final WatchlistRepository watchlistRepository;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Poster(url: bundle.imageUrl),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                bundle.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                [
                  bundle.id,
                  if (bundle.type != null) bundle.type!,
                  if (bundle.yearLabel.isNotEmpty) bundle.yearLabel,
                ].join(' / '),
                textDirection: TextDirection.ltr,
              ),
              const SizedBox(height: 8),
              _RatingLine(
                bundle: bundle,
                watchlistRepository: watchlistRepository,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WatchlistActions extends StatefulWidget {
  const _WatchlistActions({
    required this.bundle,
    required this.repository,
    required this.authRepository,
  });

  final TitleDetailsBundle bundle;
  final WatchlistRepository repository;
  final MockAuthRepository authRepository;

  @override
  State<_WatchlistActions> createState() => _WatchlistActionsState();
}

class _WatchlistActionsState extends State<_WatchlistActions> {
  late Future<void> _loadFuture;
  late Future<LocalTitleStats> _statsFuture;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.repository.addListener(_onStateChanged);
    widget.authRepository.addListener(_onStateChanged);
    _loadFuture = widget.repository.load();
    _statsFuture = _statsRepository.statsForTitle(widget.bundle.id);
  }

  @override
  void didUpdateWidget(covariant _WatchlistActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      oldWidget.repository.removeListener(_onStateChanged);
      widget.repository.addListener(_onStateChanged);
      _loadFuture = widget.repository.load();
    }
    if (oldWidget.authRepository != widget.authRepository) {
      oldWidget.authRepository.removeListener(_onStateChanged);
      widget.authRepository.addListener(_onStateChanged);
    }
  }

  @override
  void dispose() {
    widget.repository.removeListener(_onStateChanged);
    widget.authRepository.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) {
      setState(() {
        _statsFuture = _statsRepository.statsForTitle(widget.bundle.id);
      });
    }
  }

  Future<WatchlistItem> _ensureItem({
    WatchStatus status = WatchStatus.planned,
    bool? favorite,
  }) {
    return widget.repository.addOrUpdateFromBundle(
      widget.bundle,
      status: status,
      favorite: favorite,
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
    });
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _setRating(int? rating) async {
    await _run(() async {
      final item =
          widget.repository.find(widget.bundle.id) ?? await _ensureItem();
      await widget.repository.setUserRating(item.id, rating);
    });
  }

  Future<void> _editReview(WatchlistItem? item) async {
    final draft = await showDialog<_ReviewDraft>(
      context: context,
      builder: (context) => _ReviewDialog(
        initialText: item?.reviewText ?? '',
        initialHasSpoiler: item?.reviewHasSpoiler ?? false,
      ),
    );
    if (draft == null) {
      return;
    }

    await _run(() async {
      final ensured =
          widget.repository.find(widget.bundle.id) ?? await _ensureItem();
      await widget.repository.setReview(
        ensured.id,
        text: draft.text,
        hasSpoiler: draft.hasSpoiler,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.authRepository.isGuest) {
      return _GuestDetailsPrompt(
        onLogin: () => showMockLoginSheet(context, widget.authRepository),
      );
    }

    return FutureBuilder<void>(
      future: _loadFuture,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState != ConnectionState.done;
        final item = widget.repository.find(widget.bundle.id);
        final disabled = loading || _busy;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.bookmarks_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'لیست من',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (loading || _busy)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (item == null)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: disabled
                          ? null
                          : () => _run(() => _ensureItem()),
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: const Text('افزودن'),
                    ),
                    OutlinedButton.icon(
                      onPressed: disabled
                          ? null
                          : () => _run(() => _ensureItem(favorite: true)),
                      icon: const Icon(Icons.favorite_border),
                      label: const Text('علاقه‌مندی'),
                    ),
                  ],
                )
              else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    IconButton.filledTonal(
                      tooltip: item.favorite
                          ? 'حذف از علاقه‌مندی'
                          : 'افزودن به علاقه‌مندی',
                      onPressed: disabled
                          ? null
                          : () => _run(
                              () => widget.repository.toggleFavorite(item.id),
                            ),
                      icon: Icon(
                        item.favorite ? Icons.favorite : Icons.favorite_border,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: disabled
                          ? null
                          : () => _run(() => widget.repository.remove(item.id)),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('حذف'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final status in WatchStatus.values)
                      ChoiceChip(
                        label: Text(_watchStatusLabel(status)),
                        selected: item.status == status,
                        onSelected: disabled
                            ? null
                            : (_) => _run(
                                () => widget.repository.setStatus(
                                  item.id,
                                  status,
                                ),
                              ),
                      ),
                  ],
                ),
              ],
              const Divider(height: 22),
              _UserRatingControl(
                rating: item?.userRating,
                disabled: disabled,
                onRatingChanged: _setRating,
              ),
              const SizedBox(height: 10),
              FutureBuilder<LocalTitleStats>(
                future: _statsFuture,
                builder: (context, statsSnapshot) {
                  return _ReviewBlock(
                    item: item,
                    stats: statsSnapshot.data ?? const LocalTitleStats(),
                    disabled: disabled,
                    onEdit: () => _editReview(item),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  static const LocalTitleStatsRepository _statsRepository =
      LocalTitleStatsRepository();
}

class _GuestDetailsPrompt extends StatelessWidget {
  const _GuestDetailsPrompt({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'حالت مهمان',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'مشاهده و جست‌وجو آزاد است. برای ذخیره لیست، امتیاز، نظر و پیشرفت قسمت‌ها وارد یکی از حساب‌های ماک شو.',
          ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: onLogin,
              icon: const Icon(Icons.login),
              label: const Text('ورود ماک'),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserRatingControl extends StatelessWidget {
  const _UserRatingControl({
    required this.rating,
    required this.disabled,
    required this.onRatingChanged,
  });

  final int? rating;
  final bool disabled;
  final ValueChanged<int?> onRatingChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.star_border, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                rating == null
                    ? 'امتیاز من: ثبت نشده'
                    : 'امتیاز من: $rating/10',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            if (rating != null)
              TextButton.icon(
                onPressed: disabled ? null : () => onRatingChanged(null),
                icon: const Icon(Icons.close),
                label: const Text('حذف'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var value = 1; value <= 10; value++)
              ChoiceChip(
                label: Text(value.toString()),
                selected: rating == value,
                onSelected: disabled ? null : (_) => onRatingChanged(value),
              ),
          ],
        ),
      ],
    );
  }
}

class _ReviewBlock extends StatefulWidget {
  const _ReviewBlock({
    required this.item,
    required this.stats,
    required this.disabled,
    required this.onEdit,
  });

  final WatchlistItem? item;
  final LocalTitleStats stats;
  final bool disabled;
  final VoidCallback onEdit;

  @override
  State<_ReviewBlock> createState() => _ReviewBlockState();
}

class _ReviewBlockState extends State<_ReviewBlock> {
  final Set<String> _revealedSpoilers = <String>{};

  @override
  void didUpdateWidget(covariant _ReviewBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stats.reviews.length != widget.stats.reviews.length) {
      _revealedSpoilers.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hasMyReview = item?.hasReview ?? false;
    final reviews = widget.stats.reviews;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.rate_review_outlined, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'نظرهای کاربران',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              onPressed: widget.disabled ? null : widget.onEdit,
              icon: Icon(hasMyReview ? Icons.edit_outlined : Icons.add_comment),
              label: Text(hasMyReview ? 'ویرایش نظر من' : 'ثبت نظر من'),
            ),
          ],
        ),
        if (reviews.isEmpty)
          const Text('هنوز هیچ کاربر محلی برای این عنوان نظری ثبت نکرده است.')
        else
          for (final review in reviews) ...[
            const SizedBox(height: 8),
            _LocalReviewTile(
              review: review,
              revealed: _revealedSpoilers.contains(review.userId),
              onReveal: () {
                setState(() {
                  _revealedSpoilers.add(review.userId);
                });
              },
            ),
          ],
      ],
    );
  }
}

class _LocalReviewTile extends StatelessWidget {
  const _LocalReviewTile({
    required this.review,
    required this.revealed,
    required this.onReveal,
  });

  final LocalTitleReview review;
  final bool revealed;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final shouldHide = review.hasSpoiler && !revealed;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                review.userDisplayName,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              if (review.userRating != null) Text('${review.userRating}/10'),
              if (review.hasSpoiler) const Text('اسپویل'),
            ],
          ),
          const SizedBox(height: 6),
          if (shouldHide)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: onReveal,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('نمایش نظر اسپویل‌دار'),
              ),
            )
          else
            Text(review.text),
        ],
      ),
    );
  }
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({
    required this.initialText,
    required this.initialHasSpoiler,
  });

  final String initialText;
  final bool initialHasSpoiler;

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  late final TextEditingController _controller;
  late bool _hasSpoiler;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _hasSpoiler = widget.initialHasSpoiler;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('نظر من'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _controller,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'متن نظر',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _hasSpoiler,
                onChanged: (value) {
                  setState(() {
                    _hasSpoiler = value ?? false;
                  });
                },
                contentPadding: EdgeInsets.zero,
                title: const Text('این نظر اسپویل دارد'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('انصراف'),
          ),
          if (widget.initialText.trim().isNotEmpty)
            TextButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(const _ReviewDraft(text: '', hasSpoiler: false)),
              child: const Text('حذف نظر'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(
              _ReviewDraft(text: _controller.text, hasSpoiler: _hasSpoiler),
            ),
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
  }
}

class _ReviewDraft {
  const _ReviewDraft({required this.text, required this.hasSpoiler});

  final String text;
  final bool hasSpoiler;
}

class _RatingLine extends StatefulWidget {
  const _RatingLine({required this.bundle, required this.watchlistRepository});

  final TitleDetailsBundle bundle;
  final WatchlistRepository watchlistRepository;

  @override
  State<_RatingLine> createState() => _RatingLineState();
}

class _RatingLineState extends State<_RatingLine> {
  late Future<LocalTitleStats> _statsFuture;

  @override
  void initState() {
    super.initState();
    widget.watchlistRepository.addListener(_reloadStats);
    _statsFuture = _statsRepository.statsForTitle(widget.bundle.id);
  }

  @override
  void didUpdateWidget(covariant _RatingLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.watchlistRepository != widget.watchlistRepository) {
      oldWidget.watchlistRepository.removeListener(_reloadStats);
      widget.watchlistRepository.addListener(_reloadStats);
    }
    if (oldWidget.bundle.id != widget.bundle.id) {
      _statsFuture = _statsRepository.statsForTitle(widget.bundle.id);
    }
  }

  @override
  void dispose() {
    widget.watchlistRepository.removeListener(_reloadStats);
    super.dispose();
  }

  void _reloadStats() {
    if (!mounted) {
      return;
    }
    setState(() {
      _statsFuture = _statsRepository.statsForTitle(widget.bundle.id);
    });
  }

  static const LocalTitleStatsRepository _statsRepository =
      LocalTitleStatsRepository();

  @override
  Widget build(BuildContext context) {
    final rating = widget.bundle.rating;
    final votes =
        widget.bundle.omdbDetails?.imdbVotes ??
        widget.bundle.voteCount?.toString();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Icon(Icons.star, size: 20),
        Text(rating == null ? 'IMDb -' : 'IMDb ${rating.toStringAsFixed(1)}'),
        if (votes != null) Text('($votes رأی)'),
        FutureBuilder<LocalTitleStats>(
          future: _statsFuture,
          builder: (context, snapshot) {
            final stats = snapshot.data;
            if (stats == null) {
              return const Text('کاربران ما -');
            }
            final localRating = stats.averageRating;
            if (localRating == null) {
              return const Text('کاربران ما: بدون امتیاز');
            }
            return Text(
              'کاربران ما ${localRating.toStringAsFixed(1)} '
              '(${stats.ratingCount} کاربر)',
            );
          },
        ),
      ],
    );
  }
}

class _SeriesSection extends StatefulWidget {
  const _SeriesSection({
    required this.bundle,
    required this.repository,
    required this.watchlistRepository,
    required this.authRepository,
  });

  final TitleDetailsBundle bundle;
  final ImdbRepository repository;
  final WatchlistRepository watchlistRepository;
  final MockAuthRepository authRepository;

  @override
  State<_SeriesSection> createState() => _SeriesSectionState();
}

class _SeriesSectionState extends State<_SeriesSection> {
  late int _selectedSeason;
  late Future<List<Episode>> _episodesFuture;

  @override
  void initState() {
    super.initState();
    widget.watchlistRepository.addListener(_onStateChanged);
    widget.authRepository.addListener(_onStateChanged);
    _selectedSeason = 1;
    _episodesFuture = _loadSeason(_selectedSeason);
  }

  @override
  void didUpdateWidget(covariant _SeriesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.watchlistRepository != widget.watchlistRepository) {
      oldWidget.watchlistRepository.removeListener(_onStateChanged);
      widget.watchlistRepository.addListener(_onStateChanged);
    }
    if (oldWidget.authRepository != widget.authRepository) {
      oldWidget.authRepository.removeListener(_onStateChanged);
      widget.authRepository.addListener(_onStateChanged);
    }
  }

  @override
  void dispose() {
    widget.watchlistRepository.removeListener(_onStateChanged);
    widget.authRepository.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<List<Episode>> _loadSeason(int season) {
    return widget.repository.seasonEpisodesWithFallback(
      widget.bundle.id,
      season,
    );
  }

  void _selectSeason(int season) {
    setState(() {
      _selectedSeason = season;
      _episodesFuture = _loadSeason(season);
    });
  }

  Future<void> _toggleEpisode(Episode episode, bool watched) async {
    if (widget.authRepository.isGuest) {
      await showMockLoginSheet(context, widget.authRepository);
      return;
    }

    final item =
        widget.watchlistRepository.find(widget.bundle.id) ??
        await widget.watchlistRepository.addOrUpdateFromBundle(
          widget.bundle,
          status: WatchStatus.watching,
        );
    await widget.watchlistRepository.toggleEpisodeWatched(
      item.id,
      episode.id,
      watched: watched,
    );
  }

  @override
  Widget build(BuildContext context) {
    final seasonCount = widget.bundle.seasonCount ?? 1;
    final safeSeasonCount = seasonCount.clamp(1, 40);
    final item = widget.watchlistRepository.find(widget.bundle.id);
    final watchedEpisodeCount = item?.watchedEpisodeIds.length ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle('فصل‌ها و قسمت‌ها', icon: Icons.view_list),
        _EpisodeProgressBox(
          isGuest: widget.authRepository.isGuest,
          watchedCount: watchedEpisodeCount,
          totalCount: widget.bundle.seriesOverview?.totalEpisodes,
          onLogin: () => showMockLoginSheet(context, widget.authRepository),
        ),
        const SizedBox(height: 12),
        if (widget.bundle.seriesOverview != null) ...[
          _SeriesOverviewBox(overview: widget.bundle.seriesOverview!),
          const SizedBox(height: 12),
        ],
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var season = 1; season <= safeSeasonCount; season++)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    label: Text('فصل $season'),
                    selected: season == _selectedSeason,
                    onSelected: (_) => _selectSeason(season),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<Episode>>(
          future: _episodesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LinearProgressIndicator();
            }
            if (snapshot.hasError) {
              return _ErrorBox(error: snapshot.error!);
            }

            final episodes = snapshot.data ?? const <Episode>[];
            if (episodes.isEmpty) {
              return const _EmptyBox(text: 'قسمتی برای این فصل پیدا نشد.');
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${episodes.length} قسمت در فصل $_selectedSeason',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                for (final episode in episodes)
                  _EpisodeTile(
                    episode: episode,
                    watched:
                        item?.watchedEpisodeIds.contains(episode.id) ?? false,
                    isGuest: widget.authRepository.isGuest,
                    onWatchedChanged: (watched) =>
                        _toggleEpisode(episode, watched),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SeriesOverviewBox extends StatelessWidget {
  const _SeriesOverviewBox({required this.overview});

  final SeriesOverview overview;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('وضعیت: ${overview.isOngoing ? 'در حال پخش' : 'پایان‌یافته'}'),
          Text('تعداد کل قسمت‌ها: ${overview.totalEpisodes ?? '-'}'),
          Text(
            'آخرین قسمت: ${_episodeNumber(overview.latestSeasonNumber, overview.latestEpisodeNumber)}'
            '${overview.latestReleaseDate == null ? '' : ' / ${overview.latestReleaseDate}'}',
            textDirection: TextDirection.ltr,
          ),
          Text(
            'قسمت بعدی: ${_episodeNumber(overview.nextSeasonNumber, overview.nextEpisodeNumber)}'
            '${overview.nextReleaseDate == null ? '' : ' / ${overview.nextReleaseDate}'}',
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
    );
  }
}

class _EpisodeProgressBox extends StatelessWidget {
  const _EpisodeProgressBox({
    required this.isGuest,
    required this.watchedCount,
    required this.totalCount,
    required this.onLogin,
  });

  final bool isGuest;
  final int watchedCount;
  final int? totalCount;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final hasTotal = totalCount != null && totalCount! > 0;
    final progress = hasTotal
        ? (watchedCount / totalCount!).clamp(0.0, 1.0)
        : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.playlist_play, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'پیشرفت قسمت‌ها',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (isGuest)
                TextButton.icon(
                  onPressed: onLogin,
                  icon: const Icon(Icons.login),
                  label: const Text('ورود'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (progress == null)
            Text('$watchedCount قسمت دیده‌شده')
          else ...[
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text('$watchedCount از $totalCount قسمت دیده شده'),
          ],
        ],
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    required this.watched,
    required this.isGuest,
    required this.onWatchedChanged,
  });

  final Episode episode;
  final bool watched;
  final bool isGuest;
  final ValueChanged<bool> onWatchedChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _EpisodeImage(url: episode.imageUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${episode.numberLabel} / ${episode.title}',
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    episode.id,
                    if (episode.releaseDate != null) episode.releaseDate!,
                    if (episode.ratingLabel.isNotEmpty)
                      'IMDb ${episode.ratingLabel}',
                  ].join(' / '),
                  textDirection: TextDirection.ltr,
                ),
                if (episode.plot != null) ...[
                  const SizedBox(height: 8),
                  Text(episode.plot!),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: isGuest ? 'برای ثبت پیشرفت وارد شو' : 'علامت دیده‌شده',
            child: Checkbox(
              value: watched,
              onChanged: isGuest
                  ? null
                  : (value) => onWatchedChanged(value ?? false),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.rows});

  final List<_InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    final visibleRows = rows.where((row) => row.value.trim().isNotEmpty);
    if (visibleRows.isEmpty) {
      return const _EmptyBox(text: 'اطلاعات تکمیلی برای این عنوان پیدا نشد.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in visibleRows)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    row.label,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                Expanded(
                  child: Text(
                    row.value,
                    textDirection: _looksLatin(row.value)
                        ? TextDirection.ltr
                        : TextDirection.rtl,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 8),
          Text(text, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _SourceWarning extends StatelessWidget {
  const _SourceWarning({required this.errors});

  final List<Object> errors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'بخشی از منابع تکمیلی پاسخ ندادند، اطلاعات موجود نمایش داده شد.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final message = error is ImdbApiException
        ? friendlyErrorMessage(error)
        : error.toString();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.error),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text),
    );
  }
}

class _LoadingDetails extends StatelessWidget {
  const _LoadingDetails({required this.summary});

  final TitleSummary summary;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Poster(url: summary.imageUrl),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    summary.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(summary.id, textDirection: TextDirection.ltr),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const LinearProgressIndicator(),
      ],
    );
  }
}

class _FatalError extends StatelessWidget {
  const _FatalError({required this.summary, required this.error});

  final TitleSummary summary;
  final Object error;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(summary.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(summary.id, textDirection: TextDirection.ltr),
        const SizedBox(height: 12),
        _ErrorBox(error: error),
      ],
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(8);
    if (url == null) {
      return _PosterFallback(width: 112, height: 164, radius: radius);
    }

    return ClipRRect(
      borderRadius: radius,
      child: CachedPosterImage(
        url: url,
        width: 112,
        height: 164,
        fit: BoxFit.cover,
        fallback: _PosterFallback(width: 112, height: 164, radius: radius),
      ),
    );
  }
}

class _EpisodeImage extends StatelessWidget {
  const _EpisodeImage({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(6);
    if (url == null) {
      return _PosterFallback(width: 72, height: 52, radius: radius);
    }
    return ClipRRect(
      borderRadius: radius,
      child: CachedPosterImage(
        url: url,
        width: 72,
        height: 52,
        fit: BoxFit.cover,
        fallback: _PosterFallback(width: 72, height: 52, radius: radius),
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: radius,
      ),
      child: const Icon(Icons.movie_outlined),
    );
  }
}

class _InfoRow {
  const _InfoRow(this.label, String? value) : value = value ?? '';

  final String label;
  final String value;
}

List<_InfoRow> _detailRows(TitleDetailsBundle bundle) {
  final omdb = bundle.omdbDetails;
  final runtime = bundle.runtimeMinutes;

  return [
    _InfoRow('شناسه', bundle.id),
    _InfoRow('عنوان اصلی', bundle.originalTitle),
    _InfoRow('نوع', bundle.type),
    _InfoRow('ژانر', _join(bundle.genres)),
    _InfoRow('تاریخ انتشار', bundle.releaseDate),
    _InfoRow('مدت زمان', runtime == null ? null : '$runtime دقیقه'),
    _InfoRow('رده‌بندی', bundle.certificate),
    _InfoRow('کشور', omdb?.country),
    _InfoRow('زبان', omdb?.language),
    _InfoRow('کارگردان', omdb?.director),
    _InfoRow('نویسنده', omdb?.writer),
    _InfoRow('بازیگران', omdb?.actors),
    _InfoRow('جوایز', omdb?.awards),
    _InfoRow('فصل‌ها', bundle.seasonCount?.toString()),
    _InfoRow('وضعیت', bundle.imdbDetails?.productionStatus),
  ];
}

String? _join(List<String> values) {
  if (values.isEmpty) {
    return null;
  }
  return values.join(', ');
}

String _episodeNumber(int? season, int? episode) {
  if (season == null || episode == null) {
    return '-';
  }
  return 'S$season E$episode';
}

bool _looksLatin(String value) {
  return RegExp(r'^[\x00-\x7F]+$').hasMatch(value);
}

String _watchStatusLabel(WatchStatus status) {
  return switch (status) {
    WatchStatus.planned => 'قصد دیدن',
    WatchStatus.watching => 'در حال تماشا',
    WatchStatus.watched => 'دیده‌شده',
    WatchStatus.stopped => 'متوقف‌شده',
    WatchStatus.dropped => 'رها شده',
  };
}
