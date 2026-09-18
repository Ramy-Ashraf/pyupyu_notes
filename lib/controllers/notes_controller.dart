import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../models/format_span.dart';
import '../models/note.dart';
import '../models/stroke_item.dart';
import '../services/notes_store.dart';
import '../utils/note_templates.dart';

/// Which subset of notes the sidebar shows.
enum NotesView { all, favorites, due, archived, trash }

/// Sidebar sort order.
enum NotesSort { updated, created, title, color }

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
    _reminderTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _checkDue());
  }

  final NotesStore _store;
  late final AppLifecycleListener _lifecycle;
  final List<Note> _notes = [];
  Timer? _saveTimer;
  Timer? _reminderTimer;
  Note? _lastDeleted;

  String? selectedId;
  String searchQuery = '';
  ThemeMode themeMode = ThemeMode.system;

  /// Sidebar width, persisted across launches.
  double sidebarWidth = 300;

  // ---- new: organization / personalization --------------------------------
  NotesView view = NotesView.all;
  String? tagFilter;
  int? colorFilter;
  NotesSort sort = NotesSort.updated;

  /// Accent color override (null = default Windows blue).
  int? accentValue;
  Color get accent => Color(accentValue ?? 0xFF0078D4);

  /// Compact density toggle.
  bool compact = false;

  /// Notes unlocked in-memory for this session (PIN lock is a UI lock).
  final Set<String> _unlockedIds = {};

  /// Ids of notes whose reminder already fired (so we don't spam).
  final Set<String> _reminderFired = {};

  /// All notes regardless of the current view (for calendar/stats).
  List<Note> get allNotes => List.unmodifiable(_notes);

  List<Note> get notes {
    Iterable<Note> result = _notes;
    // Status filter.
    switch (view) {
      case NotesView.all:
        result = result.where((n) => !n.archived && !n.trashed);
      case NotesView.favorites:
        result = result.where((n) => n.favorite && !n.trashed);
      case NotesView.due:
        result = result.where((n) => n.dueAt != null && !n.trashed);
      case NotesView.archived:
        result = result.where((n) => n.archived && !n.trashed);
      case NotesView.trash:
        result = result.where((n) => n.trashed);
    }
    if (tagFilter != null && tagFilter!.isNotEmpty) {
      final t = tagFilter!.toLowerCase();
      result = result.where(
          (n) => n.tags.map((e) => e.toLowerCase()).contains(t) ||
              n.effectiveTags().contains(t));
    }
    if (colorFilter != null) {
      result = result.where((n) => n.colorIndex == colorFilter);
    }
    final q = searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      bool matches(Note n) {
        if (n.body.toLowerCase().contains(q)) return true;
        if (n.tags.any((t) => t.toLowerCase().contains(q))) return true;
        for (final s in n.strokes) {
          final label = s.text;
          if (label != null && label.toLowerCase().contains(q)) return true;
        }
        return false;
      }

      result = result.where(matches);
    }
    final list = result.toList();
    list.sort((a, b) {
      // Trash sorts by trashedAt desc.
      if (view == NotesView.trash) {
        final at = a.trashedAt ?? a.updatedAt;
        final bt = b.trashedAt ?? b.updatedAt;
        return bt.compareTo(at);
      }
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      switch (sort) {
        case NotesSort.updated:
          return b.updatedAt.compareTo(a.updatedAt);
        case NotesSort.created:
          return b.createdAt.compareTo(a.createdAt);
        case NotesSort.title:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case NotesSort.color:
          final c = a.colorIndex.compareTo(b.colorIndex);
          if (c != 0) return c;
          return b.updatedAt.compareTo(a.updatedAt);
      }
    });
    return list;
  }

  int get totalCount => _notes.where((n) => !n.trashed).length;
  int get trashCount => _notes.where((n) => n.trashed).length;
  int get archivedCount =>
      _notes.where((n) => n.archived && !n.trashed).length;
  int get favoritesCount =>
      _notes.where((n) => n.favorite && !n.trashed).length;
  int get dueCount =>
      _notes.where((n) => n.dueAt != null && !n.trashed).length;

  /// All tags with usage counts, sorted by frequency.
  List<MapEntry<String, int>> get tagCounts {
    final map = <String, int>{};
    for (final n in _notes) {
      if (n.trashed) continue;
      for (final t in {...n.tags, ...Note.extractTags(n.body)}) {
        final k = t.toLowerCase();
        map[k] = (map[k] ?? 0) + 1;
      }
    }
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  List<Note> get dueNotes {
    final now = DateTime.now();
    return _notes
        .where((n) =>
            !n.trashed &&
            n.dueAt != null &&
            !n.dueAt!.isAfter(now) &&
            !_reminderFired.contains(n.id))
        .toList();
  }

  List<Note> get upcomingNotes {
    final now = DateTime.now();
    final list = _notes
        .where((n) => !n.trashed && n.dueAt != null && n.dueAt!.isAfter(now))
        .toList()
      ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
    return list.take(20).toList();
  }

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
    // Auto-purge trash older than 30 days.
    _notes.removeWhere((n) => n.isTrashExpired);
    themeMode = switch (data.themeMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    final savedWidth = data.sidebarWidth;
    if (savedWidth != null) {
      sidebarWidth = savedWidth.clamp(220.0, 520.0).toDouble();
    }
    accentValue = data.accentValue;
    compact = data.compact ?? false;
    sort = switch (data.sortMode) {
      'created' => NotesSort.created,
      'title' => NotesSort.title,
      'color' => NotesSort.color,
      _ => NotesSort.updated,
    };
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
      tags: ['welcome'],
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
    if (view == NotesView.trash || view == NotesView.archived) {
      view = NotesView.all;
    }
    _scheduleSave();
    notifyListeners();
    return note;
  }

  Note createFromTemplate(NoteTemplate template) {
    final note = createNote();
    note.body = template.body;
    note.updatedAt = DateTime.now();
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
    _pushHistory(note);
    note.body = body;
    // Auto-adopt inline #tags into the tag list (keeps filter in sync).
    for (final t in Note.extractTags(body)) {
      if (!note.tags.map((e) => e.toLowerCase()).contains(t)) {
        note.tags.add(t);
      }
    }
    updateNote(note);
  }

  /// Persists the note's text and its formatting ranges together.
  void setContent(Note note, String body, List<FormatSpan> formats) {
    if (note.body == body && listEquals(note.formats, formats)) return;
    if (note.body != body) _pushHistory(note);
    note.body = body;
    note.formats = formats;
    updateNote(note);
  }

  void _pushHistory(Note note) {
    final last = note.history.isEmpty ? null : note.history.last;
    final now = DateTime.now();
    if (last != null &&
        last.body == note.body &&
        now.difference(last.savedAt).inSeconds < 30) {
      return;
    }
    // Don't snapshot empty notes repeatedly.
    if (note.body.trim().isEmpty) return;
    note.history.add(NoteSnapshot(body: note.body, savedAt: note.updatedAt));
    while (note.history.length > 30) {
      note.history.removeAt(0);
    }
  }

  void restoreSnapshot(Note note, NoteSnapshot snapshot) {
    _pushHistory(note);
    note.body = snapshot.body;
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

  void toggleFavorite(Note note) {
    note.favorite = !note.favorite;
    updateNote(note);
  }

  void setArchived(Note note, bool archived) {
    note.archived = archived;
    updateNote(note);
  }

  void toggleArchive(Note note) => setArchived(note, !note.archived);

  void trashNote(Note note) {
    _lastDeleted = note;
    note.trashed = true;
    note.trashedAt = DateTime.now();
    if (selectedId == note.id) {
      selectedId = notes.isNotEmpty ? notes.first.id : null;
    }
    _scheduleSave();
    notifyListeners();
  }

  void deleteNote(Note note) => trashNote(note);

  void restoreFromTrash(Note note) {
    note.trashed = false;
    note.trashedAt = null;
    selectedId = note.id;
    if (view == NotesView.trash) view = NotesView.all;
    _scheduleSave();
    notifyListeners();
  }

  void permanentDelete(Note note) {
    _notes.remove(note);
    _unlockedIds.remove(note.id);
    if (selectedId == note.id) {
      selectedId = notes.isNotEmpty ? notes.first.id : null;
    }
    _scheduleSave();
    notifyListeners();
  }

  void emptyTrash() {
    _notes.removeWhere((n) => n.trashed);
    if (selectedId != null && selected?.trashed == true) {
      selectedId = notes.isNotEmpty ? notes.first.id : null;
    }
    _scheduleSave();
    notifyListeners();
  }

  void undoDelete() {
    final n = _lastDeleted;
    if (n == null) return;
    if (!_notes.contains(n)) _notes.add(n);
    n.trashed = false;
    n.trashedAt = null;
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
            fillStyle: s.fillStyle,
            dash: s.dash,
            seed: s.seed,
            angle: s.angle,
            text: s.text,
            locked: s.locked,
          ),
      ],
      formats: List.of(note.formats),
      tags: List.of(note.tags),
      favorite: note.favorite,
      wordGoal: note.wordGoal,
    );
    _notes.add(copy);
    selectedId = copy.id;
    _scheduleSave();
    notifyListeners();
  }

  // ---- tags / filters / sort ----------------------------------------------

  void setSearch(String q) {
    searchQuery = q;
    notifyListeners();
  }

  void setView(NotesView v) {
    view = v;
    selectedId = notes.isNotEmpty ? notes.first.id : selectedId;
    notifyListeners();
  }

  void setTagFilter(String? tag) {
    tagFilter = tag;
    notifyListeners();
  }

  void setColorFilter(int? index) {
    colorFilter = index;
    notifyListeners();
  }

  void clearFilters() {
    tagFilter = null;
    colorFilter = null;
    searchQuery = '';
    notifyListeners();
  }

  void setSort(NotesSort s) {
    sort = s;
    _scheduleSave();
    notifyListeners();
  }

  void setTags(Note note, List<String> tags) {
    note.tags = [
      for (final t in tags)
        t.trim().toLowerCase().replaceAll(RegExp(r'^#+'), '')
    ].where((t) => t.isNotEmpty).toSet().toList()
      ..sort();
    updateNote(note);
  }

  void addTag(Note note, String tag) {
    final t = tag.trim().toLowerCase().replaceAll(RegExp(r'^#+'), '');
    if (t.isEmpty || note.tags.contains(t)) return;
    note.tags.add(t);
    updateNote(note);
  }

  void removeTag(Note note, String tag) {
    note.tags.remove(tag);
    updateNote(note);
  }

  List<String> suggestTags(Note note, {int max = 5}) {
    final counts = tagCounts;
    final have = {...note.tags, ...Note.extractTags(note.body)};
    return [
      for (final e in counts)
        if (!have.contains(e.key)) e.key
    ].take(max).toList();
  }

  // ---- reminders ------------------------------------------------------------

  void setDue(Note note, DateTime? due) {
    note.dueAt = due;
    _reminderFired.remove(note.id);
    updateNote(note);
  }

  void clearDue(Note note) => setDue(note, null);

  void _checkDue() {
    final due = dueNotes;
    if (due.isEmpty) return;
    for (final n in due) {
      _reminderFired.add(n.id);
    }
    notifyListeners();
  }

  // ---- lock -----------------------------------------------------------------

  bool isUnlocked(Note note) => !note.isLocked || _unlockedIds.contains(note.id);

  bool unlock(Note note, String pin) {
    if (note.pinHash == pinHashOf(pin)) {
      _unlockedIds.add(note.id);
      notifyListeners();
      return true;
    }
    return false;
  }

  void lockNote(Note note, String pin) {
    note.pinHash = pinHashOf(pin);
    _unlockedIds.remove(note.id);
    updateNote(note);
  }

  void removeLock(Note note) {
    note.pinHash = null;
    _unlockedIds.remove(note.id);
    updateNote(note);
  }

  void lockNow(Note note) {
    _unlockedIds.remove(note.id);
    notifyListeners();
  }

  // ---- goals / attachments ----------------------------------------------------

  void setWordGoal(Note note, int goal) {
    note.wordGoal = goal.clamp(0, 100000);
    updateNote(note);
  }

  void addAttachment(Note note, String name, String path) {
    note.attachments.add(NoteAttachment(
      name: name,
      path: path,
      addedAt: DateTime.now(),
    ));
    updateNote(note);
  }

  void removeAttachment(Note note, NoteAttachment attachment) {
    note.attachments.remove(attachment);
    updateNote(note);
  }

  // ---- appearance -------------------------------------------------------------

  void setAccent(int? value) {
    accentValue = value;
    _scheduleSave();
    notifyListeners();
  }

  void toggleCompact() {
    compact = !compact;
    _scheduleSave();
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

  // ---- import / restore -------------------------------------------------------

  void importNotes(List<Note> imported) {
    for (final n in imported) {
      if (_notes.any((e) => e.id == n.id)) {
        _notes.add(Note(
          id: 'n${DateTime.now().microsecondsSinceEpoch}_${n.id}',
          body: n.body,
          colorIndex: n.colorIndex,
          pinned: n.pinned,
          createdAt: n.createdAt,
          updatedAt: n.updatedAt,
          strokes: n.strokes,
          formats: n.formats,
          tags: n.tags,
          favorite: n.favorite,
        ));
      } else {
        _notes.add(n);
      }
    }
    _scheduleSave();
    notifyListeners();
  }

  // ---- persistence ------------------------------------------------------------

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _flushSave);
  }

  void _flushSave() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _store.saveSync(
      _notes,
      themeMode.name,
      sidebarWidth: sidebarWidth,
      accentValue: accentValue,
      compact: compact,
      sortMode: sort.name,
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _reminderTimer?.cancel();
    _flushSave();
    super.dispose();
  }
}
