import 'package:flutter/material.dart';

import '../api/backend_api_client.dart';
import '../repositories/mock_auth_repository.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.authRepository});

  final MockAuthRepository authRepository;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  late Future<_AdminDashboardData> _future;
  bool _deletingReview = false;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  BackendApiClient _requireClient() {
    final client = widget.authRepository.backendClient;
    if (client == null) {
      throw const BackendApiException(
        'آدرس سرور برای پنل مدیریت تنظیم نشده است.',
      );
    }
    return client;
  }

  String _requireToken() {
    final token = widget.authRepository.accessToken;
    if (token == null || token.isEmpty) {
      throw const AuthException(
        'برای استفاده از پنل مدیریت باید وارد حساب مدیر شوی.',
      );
    }
    return token;
  }

  Future<_AdminDashboardData> _loadData() async {
    await widget.authRepository.load();
    final user = widget.authRepository.currentUser;
    if (user == null) {
      throw const AuthException(
        'برای استفاده از پنل مدیریت باید وارد حساب شوی.',
      );
    }
    if (!user.isAdmin) {
      throw const AuthException('این بخش فقط برای مدیران برنامه است.');
    }

    final client = _requireClient();
    final token = _requireToken();
    final usersFuture = client.adminUsers(token);
    final reviewsFuture = client.adminReviews(token);

    return _AdminDashboardData(
      users: await usersFuture,
      reviews: await reviewsFuture,
    );
  }

  void _reload() {
    setState(() {
      _future = _loadData();
    });
  }

  Future<void> _deleteReview(AdminReview review) async {
    if (_deletingReview) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف نظر'),
        content: Text(
          'نظر ${review.userDisplayName} برای «${review.title}» حذف شود؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      _deletingReview = true;
    });

    try {
      await _requireClient().adminDeleteReview(_requireToken(), review.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('نظر حذف شد.')));
      _reload();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_adminErrorMessage(error))));
    } finally {
      if (mounted) {
        setState(() {
          _deletingReview = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مدیریت'),
          actions: [
            IconButton(
              tooltip: 'بازخوانی',
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: FutureBuilder<_AdminDashboardData>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _AdminError(
                  message: _adminErrorMessage(snapshot.error!),
                  onRetry: _reload,
                );
              }

              final data = snapshot.data;
              if (data == null) {
                return _AdminError(
                  message: 'پاسخ پنل مدیریت خالی بود.',
                  onRetry: _reload,
                );
              }

              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _AdminSectionHeader(
                      icon: Icons.people_outline,
                      title: 'کاربران',
                      subtitle: '${data.users.total} کاربر ثبت شده',
                    ),
                    const SizedBox(height: 10),
                    if (data.users.items.isEmpty)
                      const _AdminEmpty(text: 'کاربری برای نمایش وجود ندارد.')
                    else
                      for (final user in data.users.items)
                        _AdminUserTile(user: user),
                    const SizedBox(height: 20),
                    _AdminSectionHeader(
                      icon: Icons.rate_review_outlined,
                      title: 'نظرات کاربران',
                      subtitle: '${data.reviews.total} نظر ثبت شده',
                    ),
                    const SizedBox(height: 10),
                    if (data.reviews.items.isEmpty)
                      const _AdminEmpty(text: 'نظری برای بررسی وجود ندارد.')
                    else
                      for (final review in data.reviews.items)
                        _AdminReviewTile(
                          review: review,
                          deleting: _deletingReview,
                          onDelete: () => _deleteReview(review),
                        ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AdminDashboardData {
  const _AdminDashboardData({required this.users, required this.reviews});

  final AdminUsersPage users;
  final AdminReviewsPage reviews;
}

class _AdminSectionHeader extends StatelessWidget {
  const _AdminSectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _AdminUserTile extends StatelessWidget {
  const _AdminUserTile({required this.user});

  final AdminUser user;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: CircleAvatar(child: Text(_avatarLetter(user.displayName))),
        title: Text(user.displayNameWithRole),
        subtitle: Text(
          [
            if (user.email.isNotEmpty) user.email,
            if (user.username.isNotEmpty) '@${user.username}',
          ].join('\n'),
          textDirection: TextDirection.ltr,
        ),
        isThreeLine: user.email.isNotEmpty && user.username.isNotEmpty,
        trailing: _RolePill(role: user.role),
      ),
    );
  }
}

class _AdminReviewTile extends StatelessWidget {
  const _AdminReviewTile({
    required this.review,
    required this.deleting,
    required this.onDelete,
  });

  final AdminReview review;
  final bool deleting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
              Expanded(
                child: Text(
                  review.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: 'حذف نظر نامناسب',
                onPressed: deleting ? null : onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          Text(
            'از ${review.userDisplayName}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(review.text),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _InfoPill(label: review.titleId),
              if (review.email != null) _InfoPill(label: review.email!),
              if (review.containsSpoiler) const _InfoPill(label: 'اسپویل'),
              _InfoPill(
                label: _shortDate(review.updatedAt ?? review.createdAt),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RolePill extends StatelessWidget {
  const _RolePill({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final isAdmin = role.toLowerCase().trim() == 'admin';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: isAdmin
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(isAdmin ? 'مدیر' : 'کاربر'),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, textDirection: TextDirection.ltr),
    );
  }
}

class _AdminEmpty extends StatelessWidget {
  const _AdminEmpty({required this.text});

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

class _AdminError extends StatelessWidget {
  const _AdminError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.admin_panel_settings_outlined,
              size: 42,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('تلاش دوباره'),
            ),
          ],
        ),
      ),
    );
  }
}

String _avatarLetter(String value) {
  final text = value.trim();
  return text.isEmpty ? '?' : text.characters.first;
}

String _shortDate(DateTime? value) {
  if (value == null) {
    return '-';
  }
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}/$month/$day $hour:$minute';
}

String _adminErrorMessage(Object error) {
  if (error is BackendApiException) {
    return error.message;
  }
  if (error is AuthException) {
    return error.message;
  }
  return error.toString();
}
