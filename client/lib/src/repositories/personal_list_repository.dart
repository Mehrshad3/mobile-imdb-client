import 'package:flutter/foundation.dart';

import '../models/personal_list.dart';
import '../storage/personal_list_store.dart';

class PersonalListRepository extends ChangeNotifier {
  PersonalListRepository({PersonalListStore? store})
    : _store = store ?? PersonalListStore();

  PersonalListStore _store;
  final List<PersonalList> _lists = [];

  bool _loaded = false;
  Future<void>? _loadFuture;

  List<PersonalList> get lists => List.unmodifiable(_lists);

  Future<void> switchStore(PersonalListStore store) async {
    _store = store;
    _loaded = false;
    _loadFuture = null;
    _lists.clear();
    notifyListeners();
    await load();
  }

  Future<void> load() {
    if (_loaded) {
      return Future.value();
    }
    return _loadFuture ??= _load();
  }

  PersonalList? find(String id) {
    for (final list in _lists) {
      if (list.id == id) {
        return list;
      }
    }
    return null;
  }

  Future<PersonalList> create(String name) async {
    await load();
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('List name is required.');
    }
    final list = PersonalList.create(trimmed);
    _lists.insert(0, list);
    await _saveAndNotify();
    return list;
  }

  Future<void> rename(String id, String name) async {
    await load();
    final index = _lists.indexWhere((list) => list.id == id);
    if (index == -1) {
      return;
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _lists[index] = _lists[index].copyWith(name: trimmed);
    await _saveAndNotify();
  }

  Future<void> delete(String id) async {
    await load();
    _lists.removeWhere((list) => list.id == id);
    await _saveAndNotify();
  }

  Future<void> _load() async {
    final loadedLists = await _store.read();
    _lists
      ..clear()
      ..addAll(_sorted(loadedLists));
    _loaded = true;
    notifyListeners();
  }

  Future<void> _saveAndNotify() async {
    final sortedLists = _sorted(_lists);
    _lists
      ..clear()
      ..addAll(sortedLists);
    await _store.write(_lists);
    notifyListeners();
  }
}

List<PersonalList> _sorted(Iterable<PersonalList> lists) {
  final sorted = lists.toList();
  sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return sorted;
}
