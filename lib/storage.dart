import 'dart:io';

import 'package:path_provider/path_provider.dart';

abstract interface class GiriStorage {
  Future<String?> read();
  Future<void> write(String contents);
}

/// Local documents storage. A failed load is handled by GiriStore; malformed
/// contents are deliberately returned intact rather than silently replaced.
class FileGiriStorage implements GiriStorage {
  FileGiriStorage({Directory? directory}) : _directory = directory;

  final Directory? _directory;

  Future<Directory> _resolveDirectory() async =>
      _directory ?? await getApplicationDocumentsDirectory();

  File _file(Directory directory, String suffix) =>
      File('${directory.path}${Platform.pathSeparator}giristair.json$suffix');

  @override
  Future<String?> read() async {
    final directory = await _resolveDirectory();
    final file = _file(directory, '');
    if (await file.exists()) return file.readAsString();
    final backup = _file(directory, '.bak');
    if (await backup.exists()) return backup.readAsString();
    return null;
  }

  @override
  Future<void> write(String contents) async {
    final directory = await _resolveDirectory();
    await directory.create(recursive: true);
    final file = _file(directory, '');
    final temporary = _file(directory, '.tmp');
    final backup = _file(directory, '.bak');
    await temporary.writeAsString(contents, flush: true);
    // iOS and Android replace the same-directory destination on rename. Keep
    // the previous complete document as a separate recovery copy first.
    if (await file.exists()) await file.copy(backup.path);
    await temporary.rename(file.path);
  }
}

class MemoryGiriStorage implements GiriStorage {
  MemoryGiriStorage([this.contents]);

  String? contents;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> write(String contents) async {
    this.contents = contents;
  }
}
