import 'dart:convert';
import 'dart:io';

import '../models/watchlist_item.dart';
import 'app_storage_directory.dart';

class WatchlistStore {
  WatchlistStore({this.filePath, this.fileName = 'watchlist.json'});

  final String? filePath;
  final String fileName;

  Future<List<WatchlistItem>> read() async {
    final file = await _file();
    if (!await file.exists()) {
      return const [];
    }

    final text = await file.readAsString();
    if (text.trim().isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(text);
    if (decoded is! List) {
      return const [];
    }

    return decoded
        .whereType<Map>()
        .map((item) => WatchlistItem.fromJson(Map<String, Object?>.from(item)))
        .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
        .toList();
  }

  Future<void> write(List<WatchlistItem> items) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert(items.map((item) => item.toJson()).toList()),
      flush: true,
    );
  }

  Future<File> _file() async {
    final explicitPath = filePath;
    if (explicitPath != null && explicitPath.isNotEmpty) {
      return File(explicitPath);
    }

    final directory = await AppStorageDirectory.resolve();
    return File('${directory.path}${Platform.pathSeparator}$fileName');
  }
}
