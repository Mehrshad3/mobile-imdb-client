class PersonalList {
  const PersonalList({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String name;
  final DateTime createdAt;

  factory PersonalList.create(String name, {DateTime? now}) {
    final createdAt = now ?? DateTime.now();
    return PersonalList(
      id: 'list_${createdAt.microsecondsSinceEpoch}',
      name: name.trim(),
      createdAt: createdAt,
    );
  }

  factory PersonalList.fromJson(Map<String, Object?> json) {
    return PersonalList(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      createdAt: _readDate(json['createdAt']) ?? DateTime.now(),
    );
  }

  Map<String, Object?> toJson() {
    return {'id': id, 'name': name, 'createdAt': createdAt.toIso8601String()};
  }

  PersonalList copyWith({String? name}) {
    return PersonalList(id: id, name: name ?? this.name, createdAt: createdAt);
  }
}

DateTime? _readDate(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}
