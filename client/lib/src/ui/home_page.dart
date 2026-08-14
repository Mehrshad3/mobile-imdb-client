import 'package:flutter/material.dart';

import '../api/imdb_api_exception.dart';
import '../api/imdb_error_messages.dart';
import '../debug/imdb_search_debug_log.dart';
import '../models/personal_list.dart';
import '../models/title_summary.dart';
import '../models/watchlist_item.dart';
import '../repositories/imdb_repository.dart';
import '../repositories/mock_auth_repository.dart';
import '../repositories/personal_list_repository.dart';
import '../repositories/watchlist_repository.dart';
import '../storage/personal_list_store.dart';
import '../storage/watchlist_store.dart';
import 'api_debug_page.dart';
import 'cached_poster_image.dart';
import 'mock_login_sheet.dart';
import 'title_preview_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.repository,
    this.watchlistRepository,
    this.personalListRepository,
    this.authRepository,
    this.autoLoad = true,
  });

  final ImdbRepository? repository;
  final WatchlistRepository? watchlistRepository;
  final PersonalListRepository? personalListRepository;
  final MockAuthRepository? authRepository;
  final bool autoLoad;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final ImdbRepository _repository;
  late final bool _ownsRepository;
  late final WatchlistRepository _watchlistRepository;
  late final bool _ownsWatchlistRepository;
  late final PersonalListRepository _personalListRepository;
  late final bool _ownsPersonalListRepository;
  late final MockAuthRepository _authRepository;
  late final bool _ownsAuthRepository;
  late Future<void> _watchlistFuture;
  late Future<void> _personalListFuture;

  final TextEditingController _searchController = TextEditingController(
    text: 'breaking bad',
  );

  int _selectedIndex = 0;
  _SearchFilter _searchFilter = _SearchFilter.all;
  _WatchlistFilter _watchlistFilter = _WatchlistFilter.all;
  String? _selectedPersonalListId;
  bool _searching = false;
  String? _searchError;
  String? _lastSearch;
  List<TitleSummary> _searchResults = const [];

  late Future<List<TitleSummary>> _trendingFuture;
  late Future<List<TitleSummary>> _popularMoviesFuture;
  late Future<List<TitleSummary>> _popularSeriesFuture;
  late Future<List<TitleSummary>> _newTitlesFuture;
  late Future<List<TitleSummary>> _topRatedFuture;
  late Future<List<TitleSummary>> _recommendationsFuture;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? ImdbRepository();
    _ownsRepository = widget.repository == null;
    _authRepository = widget.authRepository ?? MockAuthRepository();
    _ownsAuthRepository = widget.authRepository == null;
    _authRepository.addListener(_onAuthChanged);
    _watchlistRepository =
        widget.watchlistRepository ??
        WatchlistRepository(
          store: WatchlistStore(fileName: _watchlistFileName),
        );
    _ownsWatchlistRepository = widget.watchlistRepository == null;
    _watchlistFuture = _watchlistRepository.load();
    _watchlistRepository.addListener(_onWatchlistChanged);
    _personalListRepository =
        widget.personalListRepository ??
        PersonalListRepository(
          store: PersonalListStore(fileName: _personalListFileName),
        );
    _ownsPersonalListRepository = widget.personalListRepository == null;
    _personalListFuture = _personalListRepository.load();
    _personalListRepository.addListener(_onPersonalListsChanged);
    _authRepository.load();
    _resetHomeFutures(load: widget.autoLoad);
  }

  @override
  void dispose() {
    if (_ownsRepository) {
      _repository.close();
    }
    _authRepository.removeListener(_onAuthChanged);
    if (_ownsAuthRepository) {
      _authRepository.dispose();
    }
    _watchlistRepository.removeListener(_onWatchlistChanged);
    if (_ownsWatchlistRepository) {
      _watchlistRepository.dispose();
    }
    _personalListRepository.removeListener(_onPersonalListsChanged);
    if (_ownsPersonalListRepository) {
      _personalListRepository.dispose();
    }
    _searchController.dispose();
    super.dispose();
  }

  void _onWatchlistChanged() {
    if (mounted) {
      setState(() {
        _recommendationsFuture = _loadRecommendations();
      });
    }
  }

  void _onPersonalListsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onAuthChanged() {
    if (_ownsWatchlistRepository) {
      final future = _watchlistRepository.switchStore(
        WatchlistStore(fileName: _watchlistFileName),
      );
      if (mounted) {
        setState(() {
          _watchlistFuture = future;
          if (_ownsPersonalListRepository) {
            _personalListFuture = _personalListRepository.switchStore(
              PersonalListStore(fileName: _personalListFileName),
            );
          }
          _watchlistFilter = _WatchlistFilter.all;
          _selectedPersonalListId = null;
          _recommendationsFuture = _loadRecommendations();
        });
      }
      return;
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

  String get _personalListFileName {
    final user = _authRepository.currentUser;
    return user == null
        ? 'personal_lists_guest.json'
        : 'personal_lists_${user.storageKey}.json';
  }

  void _resetHomeFutures({bool load = true}) {
    if (!load) {
      _trendingFuture = Future.value(const []);
      _popularMoviesFuture = Future.value(const []);
      _popularSeriesFuture = Future.value(const []);
      _newTitlesFuture = Future.value(const []);
      _topRatedFuture = Future.value(const []);
      _recommendationsFuture = Future.value(const []);
      return;
    }

    _trendingFuture = _repository.trending(first: 12);
    _popularMoviesFuture = _repository.popularMovies();
    _popularSeriesFuture = _repository.popularSeries();
    _newTitlesFuture = _repository.newTitles();
    _topRatedFuture = _repository.topRatedMovies();
    _recommendationsFuture = _loadRecommendations();
  }

  void _refreshHome() {
    setState(_resetHomeFutures);
  }

  Future<void> _runSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      imdbSearchDebugLog('Home.search skipped empty input');
      setState(() {
        _searchError = 'عبارت جست‌وجو را وارد کن.';
        _searchResults = const [];
        _lastSearch = null;
      });
      return;
    }

    final detectedId = extractImdbTitleId(query);
    imdbSearchDebugLog(
      'Home.search pressed query="$query" filter=${_searchFilter.name} '
      'detectedId=${detectedId ?? 'none'}',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _searching = true;
      _searchError = null;
      _lastSearch = query;
    });

    try {
      final results = switch (_searchFilter) {
        _ when detectedId != null => await _repository.titleSummaryById(
          query,
          fallbackTitle: titleSearchTextWithoutImdbId(query),
        ),
        _SearchFilter.all => await _repository.searchSmart(query),
        _SearchFilter.movie => await _repository.searchMovies(query),
        _SearchFilter.series => await _repository.searchSeries(query),
      };
      if (!mounted) {
        return;
      }
      imdbSearchDebugLog(
        'Home.search completed query="$query" filter=${_searchFilter.name} '
        'count=${results.length} ids=[${_debugTitleIds(results)}]',
      );
      setState(() {
        _searchResults = results;
      });
    } on ImdbApiException catch (error) {
      imdbSearchDebugLog(
        'Home.search ImdbApiException: ${debugErrorSummary(error)}',
      );
      _setSearchError(friendlyErrorMessage(error));
    } catch (error) {
      imdbSearchDebugLog('Home.search error: ${debugErrorSummary(error)}');
      _setSearchError(friendlyErrorMessage(error));
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
    imdbSearchDebugLog(
      'Home.openTitle push id=${title.id} title="${title.title}"',
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TitlePreviewPage(
          summary: title,
          repository: _repository,
          watchlistRepository: _watchlistRepository,
          authRepository: _authRepository,
        ),
      ),
    );
  }

  Future<void> _showLogin() {
    return showMockLoginSheet(context, _authRepository);
  }

  Future<void> _createPersonalList() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _PersonalListNameDialog(),
    );
    if (name == null || name.trim().isEmpty) {
      return;
    }
    await _personalListRepository.create(name);
  }

  Future<void> _deletePersonalList(PersonalList list) async {
    await _personalListRepository.delete(list.id);
    await _watchlistRepository.removePersonalListFromItems(list.id);
    if (mounted && _selectedPersonalListId == list.id) {
      setState(() {
        _selectedPersonalListId = null;
      });
    }
  }

  Future<void> _toggleItemPersonalList(
    WatchlistItem item,
    String listId,
    bool included,
  ) {
    return _watchlistRepository.togglePersonalList(
      item.id,
      listId,
      included: included,
    );
  }

  Future<List<TitleSummary>> _loadRecommendations() async {
    if (!widget.autoLoad) {
      return const [];
    }
    final items = _watchlistRepository.items;
    if (_authRepository.isGuest || items.isEmpty) {
      return _repository.topRatedMovies(first: 12);
    }

    final seriesCount = items.where(_looksSeriesItem).length;
    final savedIds = items.map((item) => item.id).toSet();
    final source = seriesCount > items.length - seriesCount
        ? await _repository.popularSeries(first: 18)
        : await _repository.popularMovies(first: 18);
    final filtered = source
        .where((title) => !savedIds.contains(title.id))
        .take(12)
        .toList();
    return filtered.isEmpty ? source.take(12).toList() : filtered;
  }

  void _openDebugPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ApiDebugPage(
          repository: _repository,
          watchlistRepository: _watchlistRepository,
          authRepository: _authRepository,
        ),
      ),
    );
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
            _AccountAction(
              authRepository: _authRepository,
              onLogin: _showLogin,
              onLogout: _authRepository.logout,
            ),
            IconButton(
              tooltip: 'جست‌وجوی پیشرفته',
              onPressed: _openDebugPage,
              icon: const Icon(Icons.manage_search),
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
                    title: _authRepository.isGuest
                        ? 'پیشنهادهای عمومی'
                        : 'پیشنهادهای ساده برای تو',
                    icon: Icons.auto_awesome_outlined,
                    future: _recommendationsFuture,
                  ),
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
              _WatchlistTab(
                authRepository: _authRepository,
                repository: _watchlistRepository,
                loadFuture: _watchlistFuture,
                personalListRepository: _personalListRepository,
                personalListFuture: _personalListFuture,
                filter: _watchlistFilter,
                selectedPersonalListId: _selectedPersonalListId,
                onFilterChanged: (filter) {
                  setState(() {
                    _watchlistFilter = filter;
                    _selectedPersonalListId = null;
                  });
                },
                onPersonalListSelected: (listId) {
                  setState(() {
                    _selectedPersonalListId = listId;
                    _watchlistFilter = _WatchlistFilter.all;
                  });
                },
                onCreatePersonalList: _createPersonalList,
                onDeletePersonalList: _deletePersonalList,
                onToggleItemPersonalList: _toggleItemPersonalList,
                onLogin: _showLogin,
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
            NavigationDestination(
              icon: Icon(Icons.bookmarks_outlined),
              selectedIcon: Icon(Icons.bookmarks),
              label: 'لیست من',
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

class _AccountAction extends StatelessWidget {
  const _AccountAction({
    required this.authRepository,
    required this.onLogin,
    required this.onLogout,
  });

  final MockAuthRepository authRepository;
  final VoidCallback onLogin;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final user = authRepository.currentUser;
    if (user == null) {
      return IconButton(
        tooltip: 'حساب کاربری',
        onPressed: onLogin,
        icon: const Icon(Icons.login),
      );
    }

    return PopupMenuButton<_AccountMenuAction>(
      tooltip: user.displayName,
      icon: CircleAvatar(
        radius: 15,
        child: Text(user.displayName.characters.first),
      ),
      onSelected: (action) {
        switch (action) {
          case _AccountMenuAction.switchUser:
            onLogin();
            break;
          case _AccountMenuAction.logout:
            onLogout();
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: Text(user.displayName),
            subtitle: Text('@${user.username}'),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _AccountMenuAction.switchUser,
          child: Text('حساب کاربری'),
        ),
        const PopupMenuItem(
          value: _AccountMenuAction.logout,
          child: Text('خروج'),
        ),
      ],
    );
  }
}

class _GuestAccessPrompt extends StatelessWidget {
  const _GuestAccessPrompt({
    required this.icon,
    required this.title,
    required this.text,
    required this.onLogin,
  });

  final IconData icon;
  final String title;
  final String text;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(text),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: onLogin,
              icon: const Icon(Icons.login),
              label: const Text('ورود با حساب کاربری'),
            ),
          ),
        ],
      ),
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
            labelText: 'نام فیلم، سریال یا شناسه IMDb',
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

class _WatchlistTab extends StatelessWidget {
  const _WatchlistTab({
    required this.authRepository,
    required this.repository,
    required this.loadFuture,
    required this.personalListRepository,
    required this.personalListFuture,
    required this.filter,
    required this.selectedPersonalListId,
    required this.onFilterChanged,
    required this.onPersonalListSelected,
    required this.onCreatePersonalList,
    required this.onDeletePersonalList,
    required this.onToggleItemPersonalList,
    required this.onLogin,
    required this.onOpenTitle,
  });

  final MockAuthRepository authRepository;
  final WatchlistRepository repository;
  final Future<void> loadFuture;
  final PersonalListRepository personalListRepository;
  final Future<void> personalListFuture;
  final _WatchlistFilter filter;
  final String? selectedPersonalListId;
  final ValueChanged<_WatchlistFilter> onFilterChanged;
  final ValueChanged<String?> onPersonalListSelected;
  final VoidCallback onCreatePersonalList;
  final ValueChanged<PersonalList> onDeletePersonalList;
  final Future<void> Function(WatchlistItem item, String listId, bool included)
  onToggleItemPersonalList;
  final VoidCallback onLogin;
  final ValueChanged<TitleSummary> onOpenTitle;

  @override
  Widget build(BuildContext context) {
    final user = authRepository.currentUser;
    if (user == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _GuestAccessPrompt(
            icon: Icons.bookmarks_outlined,
            title: 'لیست من مخصوص کاربران است',
            text:
                'به عنوان مهمان می‌توانی جست‌وجو کنی و جزئیات فیلم‌ها و سریال‌ها را ببینی. برای ذخیره لیست، علاقه‌مندی، امتیاز، نظر و پیشرفت قسمت‌ها وارد حساب کاربری شو.',
            onLogin: onLogin,
          ),
        ],
      );
    }

    return FutureBuilder<List<void>>(
      future: Future.wait([loadFuture, personalListFuture]),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [_InlineError(error: snapshot.error!)],
          );
        }

        final personalLists = personalListRepository.lists;
        final items = _filteredWatchlistItems(
          repository.items,
          filter,
          selectedPersonalListId,
        );
        final selectedList = selectedPersonalListId == null
            ? null
            : personalListRepository.find(selectedPersonalListId!);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const Icon(Icons.bookmarks_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'لیست ${user.displayName}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text('${items.length} عنوان'),
              ],
            ),
            const SizedBox(height: 12),
            _WatchlistStats(items: repository.items),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _WatchlistFilterChip(
                  label: 'همه',
                  selected: filter == _WatchlistFilter.all,
                  onSelected: () => onFilterChanged(_WatchlistFilter.all),
                ),
                _WatchlistFilterChip(
                  label: 'علاقه‌مندی',
                  selected: filter == _WatchlistFilter.favorite,
                  onSelected: () => onFilterChanged(_WatchlistFilter.favorite),
                ),
                _WatchlistFilterChip(
                  label: 'دیده‌شده',
                  selected: filter == _WatchlistFilter.watched,
                  onSelected: () => onFilterChanged(_WatchlistFilter.watched),
                ),
                _WatchlistFilterChip(
                  label: 'ندیده‌شده',
                  selected: filter == _WatchlistFilter.unwatched,
                  onSelected: () => onFilterChanged(_WatchlistFilter.unwatched),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _PersonalListsBar(
              lists: personalLists,
              selectedListId: selectedPersonalListId,
              onSelected: onPersonalListSelected,
              onCreate: onCreatePersonalList,
              onDelete: onDeletePersonalList,
            ),
            const SizedBox(height: 16),
            if (repository.items.isEmpty)
              const _InlineEmpty(text: 'هنوز چیزی به لیست من اضافه نشده است.')
            else if (items.isEmpty)
              _InlineEmpty(
                text: selectedList == null
                    ? 'برای این فیلتر موردی وجود ندارد.'
                    : 'در فهرست «${selectedList.name}» هنوز عنوانی نیست.',
              )
            else
              for (final item in items)
                _WatchlistTile(
                  item: item,
                  personalLists: personalLists,
                  onTap: () => onOpenTitle(item.toSummary()),
                  onToggleFavorite: () => repository.toggleFavorite(item.id),
                  onRemove: () => repository.remove(item.id),
                  onStatusChanged: (status) =>
                      repository.setStatus(item.id, status),
                  onTogglePersonalList: (listId, included) =>
                      onToggleItemPersonalList(item, listId, included),
                ),
          ],
        );
      },
    );
  }
}

class _WatchlistFilterChip extends StatelessWidget {
  const _WatchlistFilterChip({
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

class _PersonalListsBar extends StatelessWidget {
  const _PersonalListsBar({
    required this.lists,
    required this.selectedListId,
    required this.onSelected,
    required this.onCreate,
    required this.onDelete,
  });

  final List<PersonalList> lists;
  final String? selectedListId;
  final ValueChanged<String?> onSelected;
  final VoidCallback onCreate;
  final ValueChanged<PersonalList> onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.playlist_add_check, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'فهرست‌های شخصی',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('فهرست جدید'),
            ),
          ],
        ),
        if (lists.isEmpty)
          const Text('هنوز فهرست دلخواهی نساخته‌ای.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final list in lists)
                InputChip(
                  label: Text(list.name),
                  selected: selectedListId == list.id,
                  onSelected: (_) {
                    onSelected(selectedListId == list.id ? null : list.id);
                  },
                  onDeleted: () => onDelete(list),
                  deleteIcon: const Icon(Icons.close, size: 18),
                ),
            ],
          ),
      ],
    );
  }
}

class _PersonalListNameDialog extends StatefulWidget {
  const _PersonalListNameDialog();

  @override
  State<_PersonalListNameDialog> createState() =>
      _PersonalListNameDialogState();
}

class _PersonalListNameDialogState extends State<_PersonalListNameDialog> {
  final TextEditingController _controller = TextEditingController();

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
        title: const Text('فهرست جدید'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'نام فهرست'),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('انصراف'),
          ),
          FilledButton(onPressed: _submit, child: const Text('ساخت')),
        ],
      ),
    );
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      return;
    }
    Navigator.of(context).pop(name);
  }
}

class _ItemPersonalListsDialog extends StatelessWidget {
  const _ItemPersonalListsDialog({
    required this.item,
    required this.lists,
    required this.onToggle,
  });

  final WatchlistItem item;
  final List<PersonalList> lists;
  final void Function(String listId, bool included) onToggle;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text('فهرست‌های ${item.title}'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final list in lists)
                CheckboxListTile(
                  value: item.personalListIds.contains(list.id),
                  onChanged: (value) {
                    onToggle(list.id, value ?? false);
                    Navigator.of(context).pop();
                  },
                  title: Text(list.name),
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('بستن'),
          ),
        ],
      ),
    );
  }
}

class _WatchlistStats extends StatelessWidget {
  const _WatchlistStats({required this.items});

  final List<WatchlistItem> items;

  @override
  Widget build(BuildContext context) {
    final watchedTitles = items
        .where((item) => item.status == WatchStatus.watched)
        .length;
    final watchedMovies = items
        .where(
          (item) =>
              item.status == WatchStatus.watched && !_looksSeriesItem(item),
        )
        .length;
    final watchedSeries = items
        .where(
          (item) =>
              item.status == WatchStatus.watched && _looksSeriesItem(item),
        )
        .length;
    final ratedItems = items.where((item) => item.userRating != null).toList();
    final watchedEpisodes = items.fold<int>(
      0,
      (sum, item) => sum + item.watchedEpisodeIds.length,
    );
    final watchedRuntimeMinutes = items
        .where((item) => item.status == WatchStatus.watched)
        .fold<int>(0, (sum, item) => sum + (item.runtimeMinutes ?? 0));
    final favoriteGenre = _favoriteGenre(items);
    final averageRating = ratedItems.isEmpty
        ? null
        : ratedItems.fold<int>(0, (sum, item) => sum + item.userRating!) /
              ratedItems.length;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _StatPill(
          icon: Icons.check_circle_outline,
          label: 'دیده‌شده',
          value: watchedTitles.toString(),
        ),
        _StatPill(
          icon: Icons.local_movies_outlined,
          label: 'فیلم',
          value: watchedMovies.toString(),
        ),
        _StatPill(
          icon: Icons.live_tv_outlined,
          label: 'سریال',
          value: watchedSeries.toString(),
        ),
        _StatPill(
          icon: Icons.star_border,
          label: 'امتیازها',
          value: ratedItems.length.toString(),
        ),
        _StatPill(
          icon: Icons.insights_outlined,
          label: 'میانگین',
          value: averageRating == null ? '-' : averageRating.toStringAsFixed(1),
        ),
        _StatPill(
          icon: Icons.playlist_play,
          label: 'قسمت‌ها',
          value: watchedEpisodes.toString(),
        ),
        _StatPill(
          icon: Icons.timer_outlined,
          label: 'زمان',
          value: _runtimeLabel(watchedRuntimeMinutes),
        ),
        _StatPill(
          icon: Icons.category_outlined,
          label: 'ژانر',
          value: favoriteGenre ?? '-',
        ),
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text('$label: $value'),
        ],
      ),
    );
  }
}

class _WatchlistTile extends StatelessWidget {
  const _WatchlistTile({
    required this.item,
    required this.personalLists,
    required this.onTap,
    required this.onToggleFavorite,
    required this.onRemove,
    required this.onStatusChanged,
    required this.onTogglePersonalList,
  });

  final WatchlistItem item;
  final List<PersonalList> personalLists;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final VoidCallback onRemove;
  final ValueChanged<WatchStatus> onStatusChanged;
  final void Function(String listId, bool included) onTogglePersonalList;

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
        leading: _Poster(url: item.imageUrl, width: 52, height: 74),
        title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              [
                item.id,
                if (item.yearLabel.isNotEmpty) item.yearLabel,
                if (item.type != null) item.type!,
              ].join(' / '),
              textDirection: TextDirection.ltr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(_watchStatusIcon(item.status), size: 16),
                const SizedBox(width: 4),
                Text(_watchStatusLabel(item.status)),
                if (item.favorite) ...[
                  const SizedBox(width: 10),
                  const Icon(Icons.favorite, size: 16),
                  const SizedBox(width: 4),
                  const Text('علاقه‌مندی'),
                ],
              ],
            ),
            if (item.userRating != null ||
                item.hasReview ||
                item.watchedEpisodeIds.isNotEmpty ||
                item.personalListIds.isNotEmpty) ...[
              const SizedBox(height: 2),
              Wrap(
                spacing: 10,
                runSpacing: 2,
                children: [
                  if (item.userRating != null)
                    Text('امتیاز من ${item.userRating}/10'),
                  if (item.hasReview) const Text('نظر ثبت شده'),
                  if (item.watchedEpisodeIds.isNotEmpty)
                    Text('${item.watchedEpisodeIds.length} قسمت دیده‌شده'),
                  if (item.personalListIds.isNotEmpty)
                    Text('${item.personalListIds.length} فهرست شخصی'),
                ],
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: item.favorite
                  ? 'حذف از علاقه‌مندی'
                  : 'افزودن به علاقه‌مندی',
              onPressed: onToggleFavorite,
              icon: Icon(
                item.favorite ? Icons.favorite : Icons.favorite_border,
              ),
            ),
            IconButton(
              tooltip: 'فهرست‌ها',
              onPressed: personalLists.isEmpty
                  ? null
                  : () => showDialog<void>(
                      context: context,
                      builder: (context) => _ItemPersonalListsDialog(
                        item: item,
                        lists: personalLists,
                        onToggle: onTogglePersonalList,
                      ),
                    ),
              icon: const Icon(Icons.playlist_add),
            ),
            PopupMenuButton<_WatchlistMenuAction>(
              tooltip: 'گزینه‌ها',
              onSelected: (action) {
                switch (action) {
                  case _WatchlistMenuAction.planned:
                    onStatusChanged(WatchStatus.planned);
                    break;
                  case _WatchlistMenuAction.watching:
                    onStatusChanged(WatchStatus.watching);
                    break;
                  case _WatchlistMenuAction.watched:
                    onStatusChanged(WatchStatus.watched);
                    break;
                  case _WatchlistMenuAction.stopped:
                    onStatusChanged(WatchStatus.stopped);
                    break;
                  case _WatchlistMenuAction.dropped:
                    onStatusChanged(WatchStatus.dropped);
                    break;
                  case _WatchlistMenuAction.remove:
                    onRemove();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _WatchlistMenuAction.planned,
                  child: Text('قصد دیدن'),
                ),
                const PopupMenuItem(
                  value: _WatchlistMenuAction.watching,
                  child: Text('در حال تماشا'),
                ),
                const PopupMenuItem(
                  value: _WatchlistMenuAction.watched,
                  child: Text('دیده‌شده'),
                ),
                const PopupMenuItem(
                  value: _WatchlistMenuAction.stopped,
                  child: Text('متوقف‌شده'),
                ),
                const PopupMenuItem(
                  value: _WatchlistMenuAction.dropped,
                  child: Text('رها شده'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: _WatchlistMenuAction.remove,
                  child: Text('حذف'),
                ),
              ],
            ),
          ],
        ),
      ),
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
        onTap: () {
          imdbSearchDebugLog(
            'Home.search result tapped id=${title.id} title="${title.title}"',
          );
          onTap();
        },
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
      child: CachedPosterImage(
        url: url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        fallback: _PosterFallback(width: width, height: height, radius: radius),
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

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({this.text = 'نتیجه‌ای پیدا نشد.'});

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

enum _WatchlistFilter { all, favorite, watched, unwatched }

enum _WatchlistMenuAction {
  planned,
  watching,
  watched,
  stopped,
  dropped,
  remove,
}

enum _AccountMenuAction { switchUser, logout }

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

String _debugTitleIds(List<TitleSummary> titles) {
  if (titles.isEmpty) {
    return '';
  }
  return titles.take(8).map((title) => title.id).join(', ');
}

List<WatchlistItem> _filteredWatchlistItems(
  List<WatchlistItem> items,
  _WatchlistFilter filter,
  String? personalListId,
) {
  if (personalListId != null) {
    return items
        .where((item) => item.personalListIds.contains(personalListId))
        .toList();
  }
  return switch (filter) {
    _WatchlistFilter.all => items,
    _WatchlistFilter.favorite => items.where((item) => item.favorite).toList(),
    _WatchlistFilter.watched =>
      items.where((item) => item.status == WatchStatus.watched).toList(),
    _WatchlistFilter.unwatched =>
      items.where((item) => item.status != WatchStatus.watched).toList(),
  };
}

bool _looksSeriesItem(WatchlistItem item) {
  if (item.canHaveEpisodes) {
    return true;
  }
  final type = item.type?.toLowerCase() ?? '';
  return type.contains('series') || type.contains('tv');
}

String? _favoriteGenre(List<WatchlistItem> items) {
  final counts = <String, int>{};
  for (final item in items) {
    final weight = item.userRating == null ? 1 : item.userRating!;
    for (final genre in item.genres) {
      counts[genre] = (counts[genre] ?? 0) + weight;
    }
  }
  if (counts.isEmpty) {
    return null;
  }
  final entries = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return entries.first.key;
}

String _runtimeLabel(int minutes) {
  if (minutes <= 0) {
    return '-';
  }
  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  if (hours == 0) {
    return '$minutes دقیقه';
  }
  if (remainingMinutes == 0) {
    return '$hours ساعت';
  }
  return '$hours ساعت و $remainingMinutes دقیقه';
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

IconData _watchStatusIcon(WatchStatus status) {
  return switch (status) {
    WatchStatus.planned => Icons.schedule,
    WatchStatus.watching => Icons.play_circle_outline,
    WatchStatus.watched => Icons.check_circle_outline,
    WatchStatus.stopped => Icons.pause_circle_outline,
    WatchStatus.dropped => Icons.remove_circle_outline,
  };
}
