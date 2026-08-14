import 'package:flutter/foundation.dart';

import '../models/mock_user.dart';
import '../storage/session_store.dart';

class MockAuthRepository extends ChangeNotifier {
  MockAuthRepository({SessionStore? store}) : _store = store ?? SessionStore();

  final SessionStore _store;

  MockUser? _currentUser;
  bool _loaded = false;
  Future<void>? _loadFuture;

  MockUser? get currentUser => _currentUser;
  bool get isGuest => _currentUser == null;
  bool get loaded => _loaded;

  Future<void> load() {
    if (_loaded) {
      return Future.value();
    }
    return _loadFuture ??= _load();
  }

  Future<void> login(MockUser user) async {
    await load();
    _currentUser = user;
    await _store.writeActiveUserId(user.id);
    notifyListeners();
  }

  Future<void> logout() async {
    await load();
    _currentUser = null;
    await _store.writeActiveUserId(null);
    notifyListeners();
  }

  Future<void> _load() async {
    _currentUser = MockUser.findById(await _store.readActiveUserId());
    _loaded = true;
    notifyListeners();
  }
}
