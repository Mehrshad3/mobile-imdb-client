import 'mock_user.dart';

class UserAccount {
  const UserAccount({
    required this.user,
    required this.passwordSalt,
    required this.passwordHash,
  });

  final MockUser user;
  final String passwordSalt;
  final String passwordHash;

  UserAccount copyWith({
    MockUser? user,
    String? passwordSalt,
    String? passwordHash,
  }) {
    return UserAccount(
      user: user ?? this.user,
      passwordSalt: passwordSalt ?? this.passwordSalt,
      passwordHash: passwordHash ?? this.passwordHash,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'user': user.toJson(),
      'passwordSalt': passwordSalt,
      'passwordHash': passwordHash,
    };
  }

  static UserAccount fromJson(Map<String, Object?> json) {
    return UserAccount(
      user: MockUser.fromJson((json['user'] as Map).cast<String, Object?>()),
      passwordSalt: json['passwordSalt'] as String? ?? '',
      passwordHash: json['passwordHash'] as String? ?? '',
    );
  }
}

class RegistrationDraft {
  const RegistrationDraft({
    required this.displayName,
    required this.username,
    required this.email,
    required this.password,
    this.profileImageUrl,
    this.bio,
  });

  final String displayName;
  final String username;
  final String email;
  final String password;
  final String? profileImageUrl;
  final String? bio;
}
