class MockUser {
  const MockUser({
    required this.id,
    required this.displayName,
    required this.username,
  });

  final String id;
  final String displayName;
  final String username;

  String get storageKey => id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  static const all = [
    MockUser(id: 'sara', displayName: 'سارا احمدی', username: 'sara'),
    MockUser(id: 'amir', displayName: 'امیر رضایی', username: 'amir'),
    MockUser(id: 'niloofar', displayName: 'نیلوفر کریمی', username: 'niloofar'),
  ];

  static MockUser? findById(String? id) {
    if (id == null || id.isEmpty) {
      return null;
    }
    for (final user in all) {
      if (user.id == id) {
        return user;
      }
    }
    return null;
  }
}
