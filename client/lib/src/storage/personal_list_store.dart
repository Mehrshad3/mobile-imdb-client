import 'dart:convert';
import 'dart:io';

import '../models/personal_list.dart';
import 'app_storage_directory.dart';

class PersonalListStore {
  PersonalListStore({this.filePath, this.fileName = 'personal_lists.json'});

  final String? filePath;
  final String fileName;

  Future<List<PersonalList>> read() async {
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
        .map((item) => PersonalList.fromJson(Map<String, Object?>.from(item)))
        .where((list) => list.id.isNotEmpty && list.name.isNotEmpty)
        .toList();
  }

  Future<void> write(List<PersonalList> lists) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert(lists.map((list) => list.toJson()).toList()),
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
