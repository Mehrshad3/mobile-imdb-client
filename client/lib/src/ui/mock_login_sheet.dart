import 'package:flutter/material.dart';

import '../api/email_otp_service.dart';
import '../models/mock_user.dart';
import '../models/user_account.dart';
import '../repositories/mock_auth_repository.dart';

Future<void> showMockLoginSheet(
  BuildContext context,
  MockAuthRepository authRepository,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: FractionallySizedBox(
          heightFactor: 0.92,
          child: SafeArea(child: _AuthSheet(authRepository: authRepository)),
        ),
      );
    },
  );
}

class _AuthSheet extends StatefulWidget {
  const _AuthSheet({required this.authRepository});

  final MockAuthRepository authRepository;

  @override
  State<_AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends State<_AuthSheet> {
  final _signInEmail = TextEditingController();
  final _signInPassword = TextEditingController();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _signupEmail = TextEditingController();
  final _signupPassword = TextEditingController();
  final _profileImage = TextEditingController();
  final _bio = TextEditingController();
  final _signupOtp = TextEditingController();
  final _resetEmail = TextEditingController();
  final _resetOtp = TextEditingController();
  final _newPassword = TextEditingController();

  bool _busy = false;
  bool _signupOtpSent = false;
  bool _resetOtpSent = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    _signInEmail.dispose();
    _signInPassword.dispose();
    _name.dispose();
    _username.dispose();
    _signupEmail.dispose();
    _signupPassword.dispose();
    _profileImage.dispose();
    _bio.dispose();
    _signupOtp.dispose();
    _resetEmail.dispose();
    _resetOtp.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on AuthException catch (error) {
      _setMessage(error.message, isError: true);
    } on OtpSendException catch (error) {
      _setMessage(error.message, isError: true);
    } catch (error) {
      _setMessage('خطای غیرمنتظره: $error', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _setMessage(String message, {required bool isError}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _message = message;
      _messageIsError = isError;
    });
  }

  Future<void> _signIn() {
    return _run(() async {
      await widget.authRepository.signIn(
        email: _signInEmail.text,
        password: _signInPassword.text,
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  Future<void> _requestSignupOtp() {
    return _run(() async {
      await widget.authRepository.requestRegistrationOtp(
        RegistrationDraft(
          displayName: _name.text,
          username: _username.text,
          email: _signupEmail.text,
          password: _signupPassword.text,
          profileImageUrl: _profileImage.text,
          bio: _bio.text,
        ),
      );
      setState(() {
        _signupOtpSent = true;
      });
      _setMessage('کد تایید به ایمیل ثبت‌نام ارسال شد.', isError: false);
    });
  }

  Future<void> _confirmSignupOtp() {
    return _run(() async {
      await widget.authRepository.confirmRegistrationOtp(
        email: _signupEmail.text,
        otp: _signupOtp.text,
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  Future<void> _requestResetOtp() {
    return _run(() async {
      await widget.authRepository.requestPasswordResetOtp(_resetEmail.text);
      setState(() {
        _resetOtpSent = true;
      });
      _setMessage('کد بازیابی به ایمیل کاربر ارسال شد.', isError: false);
    });
  }

  Future<void> _resetPassword() {
    return _run(() async {
      await widget.authRepository.resetPassword(
        email: _resetEmail.text,
        otp: _resetOtp.text,
        newPassword: _newPassword.text,
      );
      _setMessage(
        'رمز عبور تغییر کرد. حالا می‌توانی وارد شوی.',
        isError: false,
      );
      setState(() {
        _resetOtpSent = false;
        _resetOtp.clear();
        _newPassword.clear();
      });
    });
  }

  Future<void> _mockLogin(MockUser user) {
    return _run(() async {
      await widget.authRepository.login(user);
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text('حساب کاربری', style: theme.textTheme.titleLarge),
                ),
                if (_busy)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const TabBar(
            tabs: [
              Tab(text: 'ورود'),
              Tab(text: 'ثبت‌نام'),
              Tab(text: 'بازیابی'),
            ],
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                _message!,
                style: TextStyle(
                  color: _messageIsError
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
              ),
            ),
          Expanded(
            child: TabBarView(
              children: [
                _ScrollablePane(
                  children: [
                    _TextField(
                      controller: _signInEmail,
                      label: 'ایمیل',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    _TextField(
                      controller: _signInPassword,
                      label: 'رمز عبور',
                      icon: Icons.lock_outline,
                      obscureText: true,
                    ),
                    FilledButton.icon(
                      onPressed: _busy ? null : _signIn,
                      icon: const Icon(Icons.login),
                      label: const Text('ورود با ایمیل و رمز'),
                    ),
                    const Divider(height: 28),
                    Text('حساب‌های آماده', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 6),
                    for (final user in MockUser.all)
                      ListTile(
                        leading: CircleAvatar(child: Text(user.displayName[0])),
                        title: Text(user.displayName),
                        subtitle: Text('@${user.username}'),
                        onTap: _busy ? null : () => _mockLogin(user),
                      ),
                  ],
                ),
                _ScrollablePane(
                  children: [
                    _TextField(
                      controller: _name,
                      label: 'نام و نام خانوادگی',
                      icon: Icons.badge_outlined,
                    ),
                    _TextField(
                      controller: _username,
                      label: 'نام کاربری',
                      icon: Icons.alternate_email,
                      textDirection: TextDirection.ltr,
                    ),
                    _TextField(
                      controller: _signupEmail,
                      label: 'ایمیل',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      textDirection: TextDirection.ltr,
                    ),
                    _TextField(
                      controller: _signupPassword,
                      label: 'رمز عبور',
                      icon: Icons.lock_outline,
                      obscureText: true,
                    ),
                    _TextField(
                      controller: _profileImage,
                      label: 'لینک تصویر پروفایل اختیاری',
                      icon: Icons.image_outlined,
                      textDirection: TextDirection.ltr,
                    ),
                    _TextField(
                      controller: _bio,
                      label: 'توضیحات کوتاه اختیاری',
                      icon: Icons.notes_outlined,
                      maxLines: 2,
                    ),
                    FilledButton.icon(
                      onPressed: _busy ? null : _requestSignupOtp,
                      icon: const Icon(Icons.mark_email_read_outlined),
                      label: Text(
                        _signupOtpSent ? 'ارسال دوباره کد' : 'ارسال کد تایید',
                      ),
                    ),
                    if (_signupOtpSent) ...[
                      _TextField(
                        controller: _signupOtp,
                        label: 'کد تایید ایمیل',
                        icon: Icons.pin_outlined,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                      ),
                      FilledButton.icon(
                        onPressed: _busy ? null : _confirmSignupOtp,
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('تکمیل ثبت‌نام'),
                      ),
                    ],
                  ],
                ),
                _ScrollablePane(
                  children: [
                    _TextField(
                      controller: _resetEmail,
                      label: 'ایمیل حساب',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      textDirection: TextDirection.ltr,
                    ),
                    FilledButton.icon(
                      onPressed: _busy ? null : _requestResetOtp,
                      icon: const Icon(Icons.password_outlined),
                      label: Text(
                        _resetOtpSent ? 'ارسال دوباره کد' : 'ارسال کد بازیابی',
                      ),
                    ),
                    if (_resetOtpSent) ...[
                      _TextField(
                        controller: _resetOtp,
                        label: 'کد بازیابی',
                        icon: Icons.pin_outlined,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                      ),
                      _TextField(
                        controller: _newPassword,
                        label: 'رمز عبور جدید',
                        icon: Icons.lock_reset,
                        obscureText: true,
                      ),
                      FilledButton.icon(
                        onPressed: _busy ? null : _resetPassword,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('تغییر رمز عبور'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrollablePane extends StatelessWidget {
  const _ScrollablePane({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final child in children) ...[child, const SizedBox(height: 10)],
      ],
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.textDirection,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextDirection? textDirection;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textDirection: textDirection,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
    );
  }
}
