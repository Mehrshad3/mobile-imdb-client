import 'package:flutter/foundation.dart';

import '../api/email_otp_service.dart';
import '../models/mock_user.dart';
import '../models/user_account.dart';
import '../security/password_tools.dart';
import '../storage/session_store.dart';
import '../storage/user_account_store.dart';

class MockAuthRepository extends ChangeNotifier {
  MockAuthRepository({
    SessionStore? store,
    UserAccountStore? userStore,
    EmailOtpService? otpService,
    DateTime Function()? now,
  }) : _store = store ?? SessionStore(),
       _userStore = userStore ?? UserAccountStore(),
       _otpService = otpService ?? const EmailOtpService(),
       _now = now ?? DateTime.now,
       _loadPersistedUsers = userStore != null || store == null,
       _useLegacySessionApi = store != null;

  final SessionStore _store;
  final UserAccountStore _userStore;
  final EmailOtpService _otpService;
  final DateTime Function() _now;
  final bool _loadPersistedUsers;
  final bool _useLegacySessionApi;

  MockUser? _currentUser;
  bool _loaded = false;
  Future<void>? _loadFuture;
  List<MockUser> _users = MockUser.all;
  final Map<String, _PendingOtp> _pendingOtps = {};

  MockUser? get currentUser => _currentUser;
  bool get isGuest => _currentUser == null;
  bool get loaded => _loaded;
  List<MockUser> get users => List.unmodifiable(_users);

  Future<List<MockUser>> localUsers() async {
    await load();
    return List.unmodifiable(_users);
  }

  Future<void> load() {
    if (_loaded) {
      return Future.value();
    }
    return _loadFuture ??= _load();
  }

  Future<void> login(MockUser user) async {
    await load();
    await _writeSessionFor(user.id);
    _currentUser = user;
    notifyListeners();
  }

  Future<void> signIn({required String email, required String password}) async {
    await load();
    final account = await _userStore.findByEmail(email);
    if (account == null) {
      throw AuthException('حسابی با این ایمیل پیدا نشد.');
    }
    final hash = PasswordTools.hashPassword(password, account.passwordSalt);
    if (hash != account.passwordHash) {
      throw AuthException('ایمیل یا رمز عبور نادرست است.');
    }
    _currentUser = account.user;
    await _writeSessionFor(account.user.id);
    notifyListeners();
  }

  Future<void> requestRegistrationOtp(RegistrationDraft draft) async {
    await load();
    _validateRegistrationDraft(draft);
    if (await _userStore.emailExists(draft.email)) {
      throw AuthException('این ایمیل قبلا ثبت شده است.');
    }
    if (await _userStore.usernameExists(draft.username)) {
      throw AuthException('این نام کاربری قبلا ثبت شده است.');
    }
    final ticket = await _otpService.sendOtp(draft.email);
    _pendingOtps[_otpKey(draft.email, _OtpPurpose.registration)] = _PendingOtp(
      code: ticket.code,
      expiresAt: ticket.expiresAt,
      draft: draft,
    );
  }

  Future<void> confirmRegistrationOtp({
    required String email,
    required String otp,
  }) async {
    await load();
    final pending = _takePendingOtp(email, _OtpPurpose.registration, otp);
    final draft = pending.draft;
    if (draft == null) {
      throw AuthException('اطلاعات ثبت‌نام پیدا نشد. دوباره کد بگیر.');
    }
    if (await _userStore.emailExists(draft.email)) {
      throw AuthException('این ایمیل قبلا ثبت شده است.');
    }
    if (await _userStore.usernameExists(draft.username)) {
      throw AuthException('این نام کاربری قبلا ثبت شده است.');
    }

    final salt = PasswordTools.randomToken(bytes: 12);
    final user = MockUser(
      id: 'user_${PasswordTools.randomToken(bytes: 8)}',
      displayName: draft.displayName.trim(),
      username: draft.username.trim(),
      email: draft.email.trim().toLowerCase(),
      profileImageUrl: _nullIfBlank(draft.profileImageUrl),
      bio: _nullIfBlank(draft.bio),
      createdAt: _now(),
    );
    await _userStore.add(
      UserAccount(
        user: user,
        passwordSalt: salt,
        passwordHash: PasswordTools.hashPassword(draft.password, salt),
      ),
    );
    await _refreshUsers();
    _currentUser = user;
    await _writeSessionFor(user.id);
    notifyListeners();
  }

  Future<void> requestPasswordResetOtp(String email) async {
    await load();
    final account = await _userStore.findByEmail(email);
    if (account == null) {
      throw AuthException('حسابی با این ایمیل پیدا نشد.');
    }
    final ticket = await _otpService.sendOtp(email);
    _pendingOtps[_otpKey(email, _OtpPurpose.passwordReset)] = _PendingOtp(
      code: ticket.code,
      expiresAt: ticket.expiresAt,
    );
  }

  Future<void> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    await load();
    final account = await _userStore.findByEmail(email);
    if (account == null) {
      throw AuthException('حسابی با این ایمیل پیدا نشد.');
    }
    final message = PasswordTools.validate(
      password: newPassword,
      username: account.user.username,
      email: email,
    );
    if (message != null) {
      throw AuthException(message);
    }
    _takePendingOtp(email, _OtpPurpose.passwordReset, otp);
    final salt = PasswordTools.randomToken(bytes: 12);
    await _userStore.update(
      account.copyWith(
        passwordSalt: salt,
        passwordHash: PasswordTools.hashPassword(newPassword, salt),
      ),
    );
  }

  Future<void> logout() async {
    await load();
    _currentUser = null;
    await _store.writeActiveUserId(null);
    notifyListeners();
  }

  Future<void> _load() async {
    await _refreshUsers();
    if (_useLegacySessionApi) {
      final legacyUserId = await _store.readActiveUserId();
      _currentUser = MockUser.findById(legacyUserId, extra: _users);
    } else {
      final session = await _store.readSession();
      if (session != null && session.isValid(_now())) {
        _currentUser = MockUser.findById(session.userId, extra: _users);
      } else if (session != null) {
        await _store.writeSession(null);
      } else {
        final legacyUserId = await _store.readActiveUserId();
        _currentUser = MockUser.findById(legacyUserId, extra: _users);
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _refreshUsers() async {
    if (!_loadPersistedUsers) {
      _users = MockUser.all;
      return;
    }
    _users = await _userStore.readUsers();
  }

  Future<void> _writeSessionFor(String userId) {
    if (_useLegacySessionApi) {
      return _store.writeActiveUserId(userId);
    }
    return _store.writeSession(
      AuthSession(
        userId: userId,
        token: PasswordTools.randomToken(),
        expiresAt: _now().add(const Duration(days: 30)),
      ),
    );
  }

  void _validateRegistrationDraft(RegistrationDraft draft) {
    if (draft.displayName.trim().isEmpty) {
      throw AuthException('نام و نام خانوادگی را وارد کن.');
    }
    if (!RegExp(r'^[A-Za-z0-9_]{3,24}$').hasMatch(draft.username.trim())) {
      throw AuthException(
        'نام کاربری باید ۳ تا ۲۴ کاراکتر انگلیسی، عدد یا _ باشد.',
      );
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(draft.email.trim())) {
      throw AuthException('ایمیل معتبر نیست.');
    }
    final passwordMessage = PasswordTools.validate(
      password: draft.password,
      username: draft.username,
      email: draft.email,
    );
    if (passwordMessage != null) {
      throw AuthException(passwordMessage);
    }
  }

  _PendingOtp _takePendingOtp(
    String email,
    _OtpPurpose purpose,
    String enteredOtp,
  ) {
    final key = _otpKey(email, purpose);
    final pending = _pendingOtps[key];
    if (pending == null) {
      throw AuthException('کد تایید پیدا نشد. دوباره کد بگیر.');
    }
    if (_now().isAfter(pending.expiresAt)) {
      _pendingOtps.remove(key);
      throw AuthException('کد تایید منقضی شده است.');
    }
    if (pending.code != enteredOtp.trim()) {
      throw AuthException('کد تایید نادرست است.');
    }
    _pendingOtps.remove(key);
    return pending;
  }
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum _OtpPurpose { registration, passwordReset }

class _PendingOtp {
  const _PendingOtp({required this.code, required this.expiresAt, this.draft});

  final String code;
  final DateTime expiresAt;
  final RegistrationDraft? draft;
}

String _otpKey(String email, _OtpPurpose purpose) {
  return '${purpose.name}:${email.trim().toLowerCase()}';
}

String? _nullIfBlank(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
