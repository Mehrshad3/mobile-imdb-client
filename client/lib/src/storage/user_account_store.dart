import 'dart:convert';
import 'dart:io';

import '../models/mock_user.dart';
import '../models/user_account.dart';
import 'app_storage_directory.dart';

class UserAccountStore {
  UserAccountStore({this.filePath, this.fileName = 'user_accounts.json'});

  final String? filePath;
  final String fileName;

  Future<List<UserAccount>> readAccounts() async {
    final file = await _file();
    if (!await file.exists()) {
      return <UserAccount>[];
    }
    final text = await file.readAsString();
    if (text.trim().isEmpty) {
      return <UserAccount>[];
    }
    final decoded = jsonDecode(text);
    if (decoded is! List) {
      return <UserAccount>[];
    }
    return decoded
        .whereType<Map>()
        .map((json) => UserAccount.fromJson(json.cast<String, Object?>()))
        .where((account) => account.user.id.isNotEmpty)
        .toList();
  }

  Future<List<MockUser>> readUsers() async {
    final accounts = await readAccounts();
    return [...MockUser.all, ...accounts.map((account) => account.user)];
  }

  Future<UserAccount?> findByEmail(String email) async {
    final normalized = _normalizeEmail(email);
    for (final account in await readAccounts()) {
      if (_normalizeEmail(account.user.email ?? '') == normalized) {
        return account;
      }
    }
    return null;
  }

  Future<bool> usernameExists(String username) async {
    final normalized = _normalizeUsername(username);
    for (final user in await readUsers()) {
      if (_normalizeUsername(user.username) == normalized) {
        return true;
      }
    }
    return false;
  }

  Future<bool> emailExists(String email) async {
    final normalized = _normalizeEmail(email);
    for (final user in await readUsers()) {
      if (_normalizeEmail(user.email ?? '') == normalized) {
        return true;
      }
    }
    return false;
  }

  Future<void> add(UserAccount account) async {
    final accounts = await readAccounts();
    accounts.add(account);
    await writeAccounts(accounts);
  }

  Future<void> update(UserAccount updated) async {
    final accounts = await readAccounts();
    final index = accounts.indexWhere(
      (account) => account.user.id == updated.user.id,
    );
    if (index == -1) {
      accounts.add(updated);
    } else {
      accounts[index] = updated;
    }
    await writeAccounts(accounts);
  }

  Future<void> writeAccounts(List<UserAccount> accounts) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert(accounts.map((account) => account.toJson()).toList()),
      flush: true,
    );
  }

  Future<File> _file() async {
    final explicitPath = filePath;
    if (explicitPath != null && explicitPath.isNotEmpty) {
      return File(explicitPath);
    }
    final directory = await AppStorageDirectory.resolve();
    return File('${directory.path}${Platform.pathSeparator}$fileName');
  }
}

String _normalizeEmail(String value) => value.trim().toLowerCase();

String _normalizeUsername(String value) => value.trim().toLowerCase();
