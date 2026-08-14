import 'package:flutter/material.dart';

import '../api/imdb_api_exception.dart';
import '../models/title_summary.dart';
import '../repositories/imdb_repository.dart';
import 'api_debug_page.dart';
import 'title_preview_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.repository, this.autoLoad = true});

  final ImdbRepository? repository;
  final bool autoLoad;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final ImdbRepository _repository;
  late final bool _ownsRepository;

  final TextEditingController _searchController = TextEditingController(
    text: 'breaking bad',
  );

  int _selectedIndex = 0;
  _SearchFilter _searchFilter = _SearchFilter.all;
  bool _searching = false;
  String? _searchError;
  String? _lastSearch;
  List<TitleSummary> _searchResults = const [];

  late Future<List<TitleSummary>> _trendingFuture;
  late Future<List<TitleSummary>> _popularMoviesFuture;
  late Future<List<TitleSummary>> _popularSeriesFuture;
  late Future<List<TitleSummary>> _newTitlesFuture;
  late Future<List<TitleSummary>> _topRatedFuture;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? ImdbRepository();
    _ownsRepository = widget.repository == null;
    _resetHomeFutures(load: widget.autoLoad);
  }

  @override
  void dispose() {
    if (_ownsRepository) {
      _repository.close();
    }
    _searchController.dispose();
    super.dispose();
  }

  void _resetHomeFutures({bool load = true}) {
    if (!load) {
      _trendingFuture = Future.value(const []);
      _popularMoviesFuture = Future.value(const []);
      _popularSeriesFuture = Future.value(const []);
      _newTitlesFuture = Future.value(const []);
      _topRatedFuture = Future.value(const []);
      return;
    }

    _trendingFuture = _repository.trending(first: 12);
    _popularMoviesFuture = _repository.popularMovies();
    _popularSeriesFuture = _repository.popularSeries();
    _newTitlesFuture = _repository.newTitles();
    _topRatedFuture = _repository.topRatedMovies();
  }

  void _refreshHome() {
    setState(_resetHomeFutures);
  }

  Future<void> _runSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchError = 'عبارت جست‌وجو را وارد کن.';
        _searchResults = const [];
        _lastSearch = null;
      });
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _searching = true;
      _searchError = null;
      _lastSearch = query;
    });

    try {
      final results = switch (_searchFilter) {
        _SearchFilter.all => await _repository.search(query),
        _SearchFilter.movie => await _repository.searchMovies(query),
        _SearchFilter.series => await _repository.searchSeries(query),
      };
      if (!mounted) {
        return;
      }
      setState(() {
        _searchResults = results;
      });
    } on ImdbApiException catch (error) {
      _setSearchError(error.message);
    } catch (error) {
      _setSearchError(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _searching = false;
        });
      }
    }
  }

  void _setSearchError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _searchError = message;
      _searchResults = const [];
    });
  }

  void _openTitle(TitleSummary title) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            TitlePreviewPage(summary: title, repository: _repository),
      ),
    );
  }

  void _openDebugPage() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ApiDebugPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('IMDb Tracker'),
          actions: [
            if (_selectedIndex == 0)
              IconButton(
                tooltip: 'بازخوانی',
                onPressed: _refreshHome,
                icon: const Icon(Icons.refresh),
              ),
            IconButton(
              tooltip: 'API debug',
              onPressed: _openDebugPage,
              icon: const Icon(Icons.bug_report_outlined),
            ),
          ],
        ),
        body: SafeArea(
          child: IndexedStack(
            index: _selectedIndex,
            children: [
              _HomeTab(
                sections: [
                  _HomeSectionData(
                    title: 'ترند امروز',
                    icon: Icons.trending_up,
                    future: _trendingFuture,
                  ),
                  _HomeSectionData(
                    title: 'فیلم‌های محبوب',
                    icon: Icons.local_movies_outlined,
                    future: _popularMoviesFuture,
                  ),
                  _HomeSectionData(
                    title: 'سریال‌های محبوب',
                    icon: Icons.live_tv_outlined,
                    future: _popularSeriesFuture,
                  ),
                  _HomeSectionData(
                    title: 'آثار جدید',
                    icon: Icons.new_releases_outlined,
                    future: _newTitlesFuture,
                  ),
                  _HomeSectionData(
                    title: 'فیلم‌های امتیازبالا',
                    icon: Icons.star_border,
                    future: _topRatedFuture,
                  ),
                ],
                onOpenTitle: _openTitle,
              ),
              _SearchTab(
                controller: _searchController,
                filter: _searchFilter,
                searching: _searching,
                error: _searchError,
                lastSearch: _lastSearch,
                results: _searchResults,
                onFilterChanged: (filter) {
                  setState(() {
                    _searchFilter = filter;
                  });
                  if (_lastSearch != null) {
                    _runSearch();
                  }
                },
                onSearch: _runSearch,
                onOpenTitle: _openTitle,
              ),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'خانه',
            ),
            NavigationDestination(
              icon: Icon(Icons.search),
              selectedIcon: Icon(Icons.manage_search),
              label: 'جست‌وجو',
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({required this.sections, required this.onOpenTitle});

  final List<_HomeSectionData> sections;
  final ValueChanged<TitleSummary> onOpenTitle;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      itemBuilder: (context, index) {
        final section = sections[index];
        return _TitleRail(section: section, onOpenTitle: onOpenTitle);
      },
      separatorBuilder: (_, _) => const SizedBox(height: 18),
      itemCount: sections.length,
    );
  }
}

class _TitleRail extends StatelessWidget {
  const _TitleRail({required this.section, required this.onOpenTitle});

  final _HomeSectionData section;
  final ValueChanged<TitleSummary> onOpenTitle;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TitleSummary>>(
      future: section.future,
      builder: (context, snapshot) {
        final titles = snapshot.data ?? const <TitleSummary>[];
        final loading = snapshot.connectionState != ConnectionState.done;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(section.icon, size: 22),
                const SizedBox(width: 8),
                Text(
                  section.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (loading)
              const _RailLoading()
            else if (snapshot.hasError)
              _InlineError(error: snapshot.error!)
            else if (titles.isEmpty)
              const _InlineEmpty()
            else
              SizedBox(
                height: 236,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (context, index) {
                    return _PosterTile(
                      title: titles[index],
                      onTap: () => onOpenTitle(titles[index]),
                    );
                  },
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemCount: titles.length,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SearchTab extends StatelessWidget {
  const _SearchTab({
    required this.controller,
    required this.filter,
    required this.searching,
    required this.error,
    required this.lastSearch,
    required this.results,
    required this.onFilterChanged,
    required this.onSearch,
    required this.onOpenTitle,
  });

  final TextEditingController controller;
  final _SearchFilter filter;
  final bool searching;
  final String? error;
  final String? lastSearch;
  final List<TitleSummary> results;
  final ValueChanged<_SearchFilter> onFilterChanged;
  final VoidCallback onSearch;
  final ValueChanged<TitleSummary> onOpenTitle;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          key: const ValueKey('title-search-field'),
          controller: controller,
          textDirection: TextDirection.ltr,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => onSearch(),
          decoration: InputDecoration(
            labelText: 'نام فیلم یا سریال',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: 'جست‌وجو',
              onPressed: searching ? null : onSearch,
              icon: const Icon(Icons.arrow_forward),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _FilterChipButton(
              label: 'همه',
              selected: filter == _SearchFilter.all,
              onSelected: () => onFilterChanged(_SearchFilter.all),
            ),
            _FilterChipButton(
              label: 'فیلم',
              selected: filter == _SearchFilter.movie,
              onSelected: () => onFilterChanged(_SearchFilter.movie),
            ),
            _FilterChipButton(
              label: 'سریال',
              selected: filter == _SearchFilter.series,
              onSelected: () => onFilterChanged(_SearchFilter.series),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (searching) const LinearProgressIndicator(),
        if (error != null) ...[
          if (searching) const SizedBox(height: 12),
          _InlineError(error: error!),
        ],
        if (!searching && error == null && lastSearch == null)
          const _SearchPlaceholder(),
        if (!searching &&
            error == null &&
            lastSearch != null &&
            results.isEmpty)
          const _InlineEmpty(),
        if (results.isNotEmpty) ...[
          Text(
            '${results.length} نتیجه برای "$lastSearch"',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 10),
          for (final title in results)
            _ResultTile(title: title, onTap: () => onOpenTitle(title)),
        ],
      ],
    );
  }
}

class _PosterTile extends StatelessWidget {
  const _PosterTile({required this.title, required this.onTap});

  final TitleSummary title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Poster(url: title.imageUrl, width: 126, height: 178),
              const SizedBox(height: 7),
              Text(
                title.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                _compactMeta(title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.title, required this.onTap});

  final TitleSummary title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        onTap: onTap,
        leading: _Poster(url: title.imageUrl, width: 52, height: 74),
        title: Text(title.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _compactMeta(title),
              textDirection: TextDirection.ltr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (title.subtitle != null)
              Text(
                title.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_left),
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.width, required this.height, this.url});

  final String? url;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(8);
    if (url == null) {
      return _PosterFallback(width: width, height: height, radius: radius);
    }

    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        url!,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) {
          return _PosterFallback(width: width, height: height, radius: radius);
        },
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

class _RailLoading extends StatelessWidget {
  const _RailLoading();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 236,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (_, _) => Container(
          width: 132,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemCount: 4,
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final message = error is ImdbApiException
        ? (error as ImdbApiException).message
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

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text('نتیجه‌ای پیدا نشد.'),
    );
  }
}

class _SearchPlaceholder extends StatelessWidget {
  const _SearchPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text('جست‌وجو آماده است.'),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}

class _HomeSectionData {
  const _HomeSectionData({
    required this.title,
    required this.icon,
    required this.future,
  });

  final String title;
  final IconData icon;
  final Future<List<TitleSummary>> future;
}

enum _SearchFilter { all, movie, series }

String _compactMeta(TitleSummary title) {
  final parts = [
    if (title.yearLabel.isNotEmpty) title.yearLabel,
    if (title.type != null) title.type!,
    if (title.ratingLabel.isNotEmpty) 'IMDb ${title.ratingLabel}',
  ];
  if (parts.isEmpty) {
    return title.id;
  }
  return '${title.id} / ${parts.join(' / ')}';
}
