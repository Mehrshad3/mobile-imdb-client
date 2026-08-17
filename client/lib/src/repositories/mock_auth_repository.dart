import 'package:flutter/foundation.dart';

import '../api/backend_api_client.dart';
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
    BackendApiClient? backendClient,
    DateTime Function()? now,
  }) : _store = store ?? SessionStore(),
       _userStore = userStore ?? UserAccountStore(),
       _otpService = otpService ?? const EmailOtpService(),
       _backendClient = backendClient ?? BackendApiClient.fromEnvironment(),
       _now = now ?? DateTime.now,
       _loadPersistedUsers = userStore != null || store == null,
       _useLegacySessionApi = store != null;

  final SessionStore _store;
  final UserAccountStore _userStore;
  final EmailOtpService _otpService;
  final BackendApiClient _backendClient;
  final DateTime Function() _now;
  final bool _loadPersistedUsers;
  final bool _useLegacySessionApi;

  MockUser? _currentUser;
  String? _accessToken;
  bool _loaded = false;
  Future<void>? _loadFuture;
  List<MockUser> _users = MockUser.all;
  final Map<String, _PendingOtp> _pendingOtps = {};
  final Map<String, RegistrationDraft> _pendingBackendRegistrationDrafts = {};

  MockUser? get currentUser => _currentUser;
  String? get accessToken => _accessToken;
  BackendApiClient? get backendClient =>
      _backendClient.isConfigured ? _backendClient : null;
  bool get isGuest => _currentUser == null;
  bool get loaded => _loaded;
  List<MockUser> get users => List.unmodifiable(_users);

  Future<List<MockUser>> localUsers() async {
    await load();
    if (_backendClient.isConfigured && _currentUser != null) {
      return [_currentUser!];
    }
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
    _accessToken = null;
    notifyListeners();
  }

  Future<void> signIn({required String email, required String password}) async {
    await load();
    if (_backendClient.isConfigured) {
      await _withBackendErrors(() async {
        final result = await _backendClient.login(
          email: email,
          password: password,
        );
        _currentUser = result.user;
        _accessToken = result.token;
        await _writeBackendSessionFor(result);
        notifyListeners();
      });
      return;
    }

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
    if (_backendClient.isConfigured) {
      await _withBackendErrors(
        () => _backendClient.requestRegistrationOtp(draft),
      );
      _pendingBackendRegistrationDrafts[_emailKey(draft.email)] = draft;
      return;
    }

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
    RegistrationDraft? registrationDraft,
  }) async {
    await load();
    if (_backendClient.isConfigured) {
      await _withBackendErrors(() async {
        final normalizedEmail = _emailKey(email);
        final effectiveDraft =
            _pendingBackendRegistrationDrafts[normalizedEmail] ??
            registrationDraft;
        final result = await _backendClient.confirmRegistrationOtpWithDraft(
          email: email,
          otp: otp,
          draft: effectiveDraft,
        );
        _currentUser = result.user;
        _accessToken = result.token;
        await _writeBackendSessionFor(result);
        _pendingBackendRegistrationDrafts.remove(normalizedEmail);
        notifyListeners();
      });
      return;
    }

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
    if (_backendClient.isConfigured) {
      await _withBackendErrors(
        () => _backendClient.requestPasswordResetOtp(email),
      );
      return;
    }

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
    if (_backendClient.isConfigured) {
      await _withBackendErrors(
        () => _backendClient.confirmPasswordReset(
          email: email,
          otp: otp,
          newPassword: newPassword,
        ),
      );
      return;
    }

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
    _accessToken = null;
    await _store.writeActiveUserId(null);
    notifyListeners();
  }

  Future<void> _load() async {
    await _refreshUsers();
    if (_backendClient.isConfigured) {
      final session = await _store.readSession();
      if (session != null &&
          session.isValid(_now()) &&
          !_isLocalSessionToken(session.token)) {
        try {
          _currentUser = await _backendClient.currentUser(session.token);
          _accessToken = session.token;
          _loaded = true;
          notifyListeners();
          return;
        } catch (error) {
          debugPrint('Backend session restore failed: $error');
          await _store.writeSession(null);
        }
      }
    }

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
        token: 'local:${PasswordTools.randomToken()}',
        expiresAt: _now().add(const Duration(days: 30)),
      ),
    );
  }

  Future<void> _writeBackendSessionFor(BackendAuthResult result) {
    return _store.writeSession(
      AuthSession(
        userId: result.user.id,
        token: result.token,
        expiresAt: _now().add(const Duration(days: 30)),
      ),
    );
  }

  Future<void> _withBackendErrors(Future<void> Function() action) async {
    try {
      await action();
    } on BackendApiException catch (error) {
      throw AuthException(error.message);
    }
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
  return '${purpose.name}:${_emailKey(email)}';
}

String _emailKey(String email) {
  return email.trim().toLowerCase();
}

String? _nullIfBlank(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

bool _isLocalSessionToken(String token) {
  return token == 'legacy-session' || token.startsWith('local:');
}
