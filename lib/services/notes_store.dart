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
    this.accentValue,
    this.compact,
    this.sortMode,
  });

  final List<Note> notes;
  final bool fileExists;
  final String? themeMode;
  final double? sidebarWidth;
  final int? accentValue;
  final bool? compact;
  final String? sortMode;
}

/// Loads and saves all notes as a single JSON file in the app's support
/// directory. Saves are atomic (write temp, then swap) and keep the previous
/// version in a `.bak` file that is used for recovery if the main file is
/// ever corrupt. Writes are synchronous so a save triggered just before the
/// window closes cannot be lost.
///
/// Also keeps timestamped daily backups (`notes-YYYYMMDD-HHmmss.json`,
/// last 7 kept) for restore, and can mirror the file into a OneDrive-style
/// sync folder when one exists.
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

  Directory get _backupDir =>
      Directory('$_dirPath${Platform.pathSeparator}backups');

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
          accentValue: (data['accentValue'] as num?)?.toInt(),
          compact: data['compact'] as bool?,
          sortMode: data['sortMode'] as String?,
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

  void saveSync(
    List<Note> notes,
    String themeMode, {
    double? sidebarWidth,
    int? accentValue,
    bool? compact,
    String? sortMode,
  }) {
    if (_dir == null) return;
    try {
      final map = <String, dynamic>{
        'themeMode': themeMode,
        'notes': [for (final n in notes) n.toJson()],
      };
      if (sidebarWidth != null) map['sidebarWidth'] = sidebarWidth;
      if (accentValue != null) map['accentValue'] = accentValue;
      if (compact != null) map['compact'] = compact;
      if (sortMode != null) map['sortMode'] = sortMode;
      final payload = jsonEncode(map);
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
      _maybeDailyBackup(payload);
      _maybeMirrorToSyncFolder(payload);
    } catch (_) {
      // Never let a failed write crash the app.
    }
  }

  void _maybeDailyBackup(String payload) {
    try {
      if (!_backupDir.existsSync()) _backupDir.createSync(recursive: true);
      final now = DateTime.now();
      final today = '${now.year}${_two(now.month)}${_two(now.day)}';
      final existing = _backupDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains(today))
          .toList();
      if (existing.isNotEmpty) return;
      final stamp =
          '$today-${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
      File('${_backupDir.path}${Platform.pathSeparator}notes-$stamp.json')
          .writeAsStringSync(payload, flush: true);
      final all = _backupDir.listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      while (all.length > 7) {
        all.removeAt(0).deleteSync();
      }
    } catch (_) {}
  }

  void _maybeMirrorToSyncFolder(String payload) {
    try {
      // Best-effort OneDrive/Dropbox-style sync: if a well-known sync folder
      // exists, mirror the latest file there so another device can pick it up.
      final home = Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'];
      if (home == null) return;
      const candidates = ['OneDrive', 'Dropbox', 'Google Drive'];
      for (final c in candidates) {
        final dir = Directory('$home${Platform.pathSeparator}$c'
            '${Platform.pathSeparator}NotesApp');
        if (!dir.existsSync()) continue;
        File('${dir.path}${Platform.pathSeparator}notes.json')
            .writeAsStringSync(payload, flush: true);
        break;
      }
    } catch (_) {}
  }

  List<File> listBackups() {
    try {
      if (!_backupDir.existsSync()) return const [];
      final files = _backupDir.listSync().whereType<File>().toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      return files;
    } catch (_) {
      return const [];
    }
  }

  /// Restores notes from a backup file. Returns decoded notes or null.
  List<Note>? restoreBackup(File backup) {
    try {
      final data =
          jsonDecode(backup.readAsStringSync()) as Map<String, dynamic>;
      return [
        for (final n in (data['notes'] as List? ?? []))
          Note.fromJson(n as Map<String, dynamic>),
      ];
    } catch (_) {
      return null;
    }
  }

  String _two(int v) => v.toString().padLeft(2, '0');
}
