class MockUser {
  const MockUser({
    required this.id,
    required this.displayName,
    required this.username,
    this.email,
    this.profileImageUrl,
    this.bio,
    this.createdAt,
    this.isMock = false,
    this.role = 'user',
  });

  final String id;
  final String displayName;
  final String username;
  final String? email;
  final String? profileImageUrl;
  final String? bio;
  final DateTime? createdAt;
  final bool isMock;
  final String role;

  String get storageKey => id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  bool get isAdmin => role.toLowerCase().trim() == 'admin';
  String get displayNameWithRole =>
      isAdmin ? '$displayName 👨‍🏭' : displayName;

  static const all = [
    MockUser(
      id: 'sara',
      displayName: 'سارا احمدی',
      username: 'sara',
      email: 'sara@example.com',
      isMock: true,
    ),
    MockUser(
      id: 'amir',
      displayName: 'امیر رضایی',
      username: 'amir',
      email: 'amir@example.com',
      isMock: true,
    ),
    MockUser(
      id: 'niloofar',
      displayName: 'نیلوفر کریمی',
      username: 'niloofar',
      email: 'niloofar@example.com',
      isMock: true,
    ),
  ];

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'username': username,
      'email': email,
      'profileImageUrl': profileImageUrl,
      'bio': bio,
      'createdAt': createdAt?.toIso8601String(),
      'isMock': isMock,
      'role': role,
    };
  }

  static MockUser fromJson(Map<String, Object?> json) {
    return MockUser(
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      username: json['username'] as String? ?? '',
      email: json['email'] as String?,
      profileImageUrl: json['profileImageUrl'] as String?,
      bio: json['bio'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      isMock: json['isMock'] as bool? ?? false,
      role: json['role'] as String? ?? 'user',
    );
  }

  static MockUser? findById(String? id, {Iterable<MockUser> extra = const []}) {
    if (id == null || id.isEmpty) {
      return null;
    }
    for (final user in extra) {
      if (user.id == id) {
        return user;
      }
    }
    for (final user in all) {
      if (user.id == id) {
        return user;
      }
    }
    return null;
  }
}
