import 'package:flutter/material.dart';

import '../models/mock_user.dart';
import '../repositories/mock_auth_repository.dart';

Future<void> showMockLoginSheet(
  BuildContext context,
  MockAuthRepository authRepository,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final currentUser = authRepository.currentUser;
      return Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'ورود ماک',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final user in MockUser.all)
                  ListTile(
                    leading: CircleAvatar(child: Text(user.displayName[0])),
                    title: Text(user.displayName),
                    subtitle: Text('@${user.username}'),
                    trailing: currentUser?.id == user.id
                        ? const Icon(Icons.check_circle)
                        : null,
                    onTap: () async {
                      await authRepository.login(user);
                      if (sheetContext.mounted) {
                        Navigator.of(sheetContext).pop();
                      }
                    },
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
