typedef JsonMap = Map<String, dynamic>;

JsonMap? asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

List<dynamic> asList(Object? value) {
  if (value is List) {
    return value;
  }
  return const [];
}

String? asString(Object? value) {
  if (value is String) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
  if (value is num || value is bool) {
    return value.toString();
  }
  return null;
}

int? asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

double? asDouble(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim());
  }
  return null;
}

bool? asBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true') {
      return true;
    }
    if (normalized == 'false') {
      return false;
    }
  }
  return null;
}

Object? readPath(Object? source, List<String> path) {
  Object? current = source;
  for (final segment in path) {
    final map = asMap(current);
    if (map == null) {
      return null;
    }
    current = map[segment];
  }
  return current;
}

String? readText(Object? source) {
  final direct = asString(source);
  if (direct != null) {
    return direct;
  }

  for (final path in const [
    ['text'],
    ['plainText'],
    ['value', 'plainText'],
    ['displayableProperty', 'value', 'plainText'],
    ['plotText', 'plainText'],
    ['genre', 'text'],
  ]) {
    final text = asString(readPath(source, path));
    if (text != null) {
      return text;
    }
  }
  return null;
}

String? readTitleText(Object? source) {
  for (final path in const [
    ['titleText', 'text'],
    ['originalTitleText', 'text'],
    ['l'],
    ['title'],
    ['name'],
    ['text'],
  ]) {
    final text = asString(readPath(source, path));
    if (text != null) {
      return text;
    }
  }
  return readText(source);
}

String? readImageUrl(Object? source) {
  for (final path in const [
    ['primaryImage', 'url'],
    ['primaryImage', 'imageUrl'],
    ['primaryImage', 'urlWithSize'],
    ['item', 'primaryImage', 'url'],
    ['item', 'title', 'primaryImage', 'url'],
    ['title', 'primaryImage', 'url'],
    ['node', 'item', 'primaryImage', 'url'],
    ['node', 'item', 'title', 'primaryImage', 'url'],
    ['node', 'title', 'primaryImage', 'url'],
    ['i', 'imageUrl'],
    ['image', 'url'],
    ['image', 'imageUrl'],
    ['imageUrl'],
    ['url'],
  ]) {
    final url = asString(readPath(source, path));
    if (url != null) {
      return _normalizeImageUrl(url);
    }
  }
  for (final path in const [
    ['primaryImage'],
    ['image'],
    ['i'],
  ]) {
    final url = asString(readPath(source, path));
    if (url != null) {
      return _normalizeImageUrl(url);
    }
  }
  return null;
}

String? _normalizeImageUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (trimmed.startsWith('//')) {
    return 'https:$trimmed';
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return null;
  }
  if (uri.scheme == 'http') {
    return uri.replace(scheme: 'https').toString();
  }
  return uri.toString();
}

String? formatDateParts({Object? day, Object? month, Object? year}) {
  final parsedYear = asInt(year);
  if (parsedYear == null) {
    return null;
  }

  final parsedMonth = asInt(month);
  final parsedDay = asInt(day);
  if (parsedMonth == null || parsedDay == null) {
    return parsedYear.toString();
  }

  final monthText = parsedMonth.toString().padLeft(2, '0');
  final dayText = parsedDay.toString().padLeft(2, '0');
  return '$parsedYear-$monthText-$dayText';
}

String? readReleaseDate(Object? source) {
  final display = readText(readPath(source, ['displayableProperty']));
  if (display != null) {
    return display;
  }

  final map = asMap(source);
  if (map == null) {
    return null;
  }

  return formatDateParts(
    day: map['day'],
    month: map['month'],
    year: map['year'],
  );
}
