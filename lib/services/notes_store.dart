import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/note.dart';

class SavedData {
  SavedData({
    required this.notes,
    required this.fileExists,
    this.themeMode,
    this.sidebarWidth,
  });

  final List<Note> notes;
  final bool fileExists;
  final String? themeMode;
  final double? sidebarWidth;
}

/// Loads and saves all notes as a single JSON file in the app's support
/// directory. Saves are atomic (write temp, then swap) and keep the previous
/// version in a `.bak` file that is used for recovery if the main file is
/// ever corrupt. Writes are synchronous so a save triggered just before the
/// window closes cannot be lost.
class NotesStore {
  NotesStore({Directory? baseDir}) {
    _baseDir = baseDir;
  }

  Directory? _baseDir;
  Directory? _dir;

  Future<void> init() async {
    final base = _baseDir ?? await getApplicationSupportDirectory();
    _dir = Directory(
      '${base.path}${Platform.pathSeparator}notes_app_data',
    );
    if (!_dir!.existsSync()) {
      _dir!.createSync(recursive: true);
    }
  }

  String get _dirPath => _dir!.path;
  File get _file =>
      File('$_dirPath${Platform.pathSeparator}notes.json');
  File get _tmpFile =>
      File('$_dirPath${Platform.pathSeparator}notes.json.tmp');
  File get _bakFile =>
      File('$_dirPath${Platform.pathSeparator}notes.json.bak');

  SavedData loadSync() {
    for (final f in [_file, _bakFile]) {
      if (!f.existsSync()) continue;
      try {
        final data =
            jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        return SavedData(
          notes: [
            for (final n in (data['notes'] as List? ?? []))
              Note.fromJson(n as Map<String, dynamic>),
          ],
          fileExists: true,
          themeMode: data['themeMode'] as String?,
          sidebarWidth: (data['sidebarWidth'] as num?)?.toDouble(),
        );
      } catch (_) {
        // Try the next candidate file.
      }
    }
    return SavedData(
      notes: const [],
      fileExists: _file.existsSync() || _bakFile.existsSync(),
    );
  }

  void saveSync(List<Note> notes, String themeMode, {double? sidebarWidth}) {
    if (_dir == null) return;
    try {
      final payload = jsonEncode({
        'themeMode': themeMode,
        'sidebarWidth': ?sidebarWidth,
        'notes': [for (final n in notes) n.toJson()],
      });
      _tmpFile.writeAsStringSync(payload, flush: true);
      // Rotate before touching the main file so it is never deleted without
      // a backup in place: main becomes the backup, tmp becomes main.
      if (_file.existsSync()) {
        if (_bakFile.existsSync()) {
          _bakFile.deleteSync();
        }
        _file.renameSync(_bakFile.path);
      }
      _tmpFile.renameSync(_file.path);
    } catch (_) {
      // Never let a failed write crash the app.
    }
  }
}
