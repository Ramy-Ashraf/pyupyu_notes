import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../models/format_span.dart';
import '../models/note.dart';
import '../models/stroke_item.dart';
import '../services/notes_store.dart';

/// Central app state: the list of notes, selection, search and theme.
/// Persists everything through [NotesStore] (debounced, plus flushed on
/// minimize/exit so nothing is lost).
class NotesController extends ChangeNotifier {
  NotesController({NotesStore? store}) : _store = store ?? NotesStore() {
    _lifecycle = AppLifecycleListener(
      onHide: _flushSave,
      onExitRequested: () async {
        _flushSave();
        return AppExitResponse.exit;
      },
    );
  }

  final NotesStore _store;
  late final AppLifecycleListener _lifecycle;
  final List<Note> _notes = [];
  Timer? _saveTimer;
  Note? _lastDeleted;

  String? selectedId;
  String searchQuery = '';
  ThemeMode themeMode = ThemeMode.system;

  /// Sidebar width, persisted across launches.
  double sidebarWidth = 300;

  List<Note> get notes {
    Iterable<Note> result = _notes;
    final q = searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      bool matches(Note n) {
        if (n.body.toLowerCase().contains(q)) return true;
        for (final s in n.strokes) {
          final label = s.text;
          if (label != null && label.toLowerCase().contains(q)) return true;
        }
        return false;
      }

      result = result.where(matches);
    }
    return result.toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
  }

  int get totalCount => _notes.length;

  Note? get selected {
    for (final n in _notes) {
      if (n.id == selectedId) return n;
    }
    return null;
  }

  Future<void> load() async {
    await _store.init();
    final data = _store.loadSync();
    _notes
      ..clear()
      ..addAll(data.notes);
    themeMode = switch (data.themeMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    final savedWidth = data.sidebarWidth;
    if (savedWidth != null) {
      sidebarWidth = savedWidth.clamp(220.0, 520.0).toDouble();
    }
    if (!data.fileExists && _notes.isEmpty) _seedWelcomeNotes();
    selectedId ??= notes.isNotEmpty ? notes.first.id : null;
    notifyListeners();
  }

  void _seedWelcomeNotes() {
    final now = DateTime.now();
    _notes.add(Note(
      id: 'welcome',
      body: 'Welcome to Notes! 📝\n\n'
          '• Type your thoughts here — the first line becomes the title.\n'
          '• Switch to Draw in the top bar to sketch diagrams with pen, '
          'shapes and arrows.\n'
          '• Right-click a note in the list to pin, duplicate or delete it.\n'
          '• Use the palette button to change this note\'s color.\n'
          '• Ctrl+N creates a new note, Ctrl+F focuses search.\n\n'
          'Everything saves automatically on this PC.',
      colorIndex: 0,
      pinned: true,
      createdAt: now,
      updatedAt: now,
    ));
    _notes.add(Note(
      id: 'sample-diagram',
      body: 'Sample diagram 🖊️\n\n'
          'Boxes, ellipses and arrows — scroll to zoom, '
          'or pick the hand tool to pan around.',
      colorIndex: 3,
      pinned: false,
      createdAt: now,
      updatedAt: now,
      strokes: [
        StrokeItem(
            id: 'demo1',
            type: StrokeType.rectangle,
            points: const [Offset(70, 70), Offset(230, 150)],
            colorValue: 0xFF3B82F6,
            width: 3),
        StrokeItem(
            id: 'demo2',
            type: StrokeType.rectangle,
            points: const [Offset(400, 70), Offset(560, 150)],
            colorValue: 0xFF3B82F6,
            width: 3),
        StrokeItem(
            id: 'demo3',
            type: StrokeType.arrow,
            points: const [Offset(230, 110), Offset(400, 110)],
            colorValue: 0xFF374151,
            width: 3),
        StrokeItem(
            id: 'demo4',
            type: StrokeType.arrow,
            points: const [Offset(315, 150), Offset(315, 260)],
            colorValue: 0xFF374151,
            width: 3),
        StrokeItem(
            id: 'demo5',
            type: StrokeType.ellipse,
            points: const [Offset(215, 260), Offset(415, 360)],
            colorValue: 0xFF10B981,
            width: 3),
      ],
    ));
    selectedId = 'welcome';
  }

  // ---- mutations ----------------------------------------------------------

  Note createNote() {
    final now = DateTime.now();
    final note = Note(
      id: 'n${now.microsecondsSinceEpoch}',
      body: '',
      colorIndex: 0,
      pinned: false,
      createdAt: now,
      updatedAt: now,
    );
    _notes.add(note);
    selectedId = note.id;
    searchQuery = '';
    _scheduleSave();
    notifyListeners();
    return note;
  }

  void selectNote(String? id) {
    if (selectedId == id) return;
    selectedId = id;
    notifyListeners();
  }

  void updateNote(Note note) {
    note.updatedAt = DateTime.now();
    _scheduleSave();
    notifyListeners();
  }

  void setBody(Note note, String body) {
    if (note.body == body) return;
    note.body = body;
    updateNote(note);
  }

  /// Persists the note's text and its formatting ranges together.
  void setContent(Note note, String body, List<FormatSpan> formats) {
    if (note.body == body && listEquals(note.formats, formats)) return;
    note.body = body;
    note.formats = formats;
    updateNote(note);
  }

  void setStrokes(Note note, List<StrokeItem> strokes) {
    note.strokes = strokes;
    updateNote(note);
  }

  void setColor(Note note, int index) {
    note.colorIndex = index;
    updateNote(note);
  }

  void togglePin(Note note) {
    note.pinned = !note.pinned;
    updateNote(note);
  }

  void deleteNote(Note note) {
    _notes.remove(note);
    if (selectedId == note.id) {
      selectedId = notes.isNotEmpty ? notes.first.id : null;
    }
    _lastDeleted = note;
    _scheduleSave();
    notifyListeners();
  }

  void undoDelete() {
    final n = _lastDeleted;
    if (n == null) return;
    _notes.add(n);
    selectedId = n.id;
    _lastDeleted = null;
    _scheduleSave();
    notifyListeners();
  }

  void duplicateNote(Note note) {
    final now = DateTime.now();
    final copy = Note(
      id: 'n${now.microsecondsSinceEpoch}',
      body: note.body,
      colorIndex: note.colorIndex,
      pinned: note.pinned,
      createdAt: now,
      updatedAt: now,
      strokes: [
        for (final s in note.strokes)
          StrokeItem(
            id: 's${now.microsecondsSinceEpoch}_${s.id}',
            type: s.type,
            points: List.of(s.points),
            colorValue: s.colorValue,
            width: s.width,
            filled: s.filled,
            text: s.text,
          ),
      ],
      formats: List.of(note.formats),
    );
    _notes.add(copy);
    selectedId = copy.id;
    _scheduleSave();
    notifyListeners();
  }

  void setSearch(String q) {
    searchQuery = q;
    notifyListeners();
  }

  void setSidebarWidth(double width) {
    final v = width.clamp(220.0, 520.0).toDouble();
    if (v == sidebarWidth) return;
    sidebarWidth = v;
    _scheduleSave();
    notifyListeners();
  }

  void cycleTheme() {
    themeMode = switch (themeMode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    _scheduleSave();
    notifyListeners();
  }

  // ---- persistence --------------------------------------------------------

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _flushSave);
  }

  void _flushSave() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _store.saveSync(_notes, themeMode.name, sidebarWidth: sidebarWidth);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _flushSave();
    super.dispose();
  }
}
