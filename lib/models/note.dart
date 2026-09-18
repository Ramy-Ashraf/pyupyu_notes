import 'format_span.dart';
import 'stroke_item.dart';

/// A snapshot of a note body for version history.
class NoteSnapshot {
  NoteSnapshot({required this.body, required this.savedAt});

  final String body;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
        'body': body,
        'savedAt': savedAt.millisecondsSinceEpoch,
      };

  factory NoteSnapshot.fromJson(Map<String, dynamic> json) => NoteSnapshot(
        body: json['body'] as String? ?? '',
        savedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['savedAt'] as num?)?.toInt() ?? 0,
        ),
      );
}

/// A file attached to a note (stored as a path under app data).
class NoteAttachment {
  NoteAttachment({
    required this.name,
    required this.path,
    required this.addedAt,
  });

  final String name;
  final String path;
  final DateTime addedAt;

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'addedAt': addedAt.millisecondsSinceEpoch,
      };

  factory NoteAttachment.fromJson(Map<String, dynamic> json) =>
      NoteAttachment(
        name: json['name'] as String? ?? 'file',
        path: json['path'] as String? ?? '',
        addedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['addedAt'] as num?)?.toInt() ?? 0,
        ),
      );
}

/// A single note: richly formatted text body (first non-empty line acts as
/// the title, like Windows Sticky Notes) plus an optional diagram.
class Note {
  Note({
    required this.id,
    required this.body,
    required this.colorIndex,
    required this.pinned,
    required this.createdAt,
    required this.updatedAt,
    List<StrokeItem>? strokes,
    List<FormatSpan>? formats,
    List<String>? tags,
    this.favorite = false,
    this.archived = false,
    this.trashed = false,
    this.trashedAt,
    this.dueAt,
    this.pinHash,
    List<NoteSnapshot>? history,
    this.wordGoal = 0,
    List<NoteAttachment>? attachments,
  })  : strokes = strokes ?? [],
        formats = formats ?? [],
        tags = tags ?? [],
        history = history ?? [],
        attachments = attachments ?? [];

  final String id;
  String body;
  int colorIndex;
  bool pinned;
  final DateTime createdAt;
  DateTime updatedAt;
  List<StrokeItem> strokes;

  /// Rich-text formatting ranges over [body].
  List<FormatSpan> formats;

  /// User tags (without the leading `#`).
  List<String> tags;

  /// Favorites are separate from pins: pins sort first, favorites filter.
  bool favorite;

  /// Archived notes are hidden from the main list but not deleted.
  bool archived;

  /// Trashed notes are hidden from the main list and auto-purged after 30d.
  bool trashed;
  DateTime? trashedAt;

  /// Reminder / due date. Null means no reminder.
  DateTime? dueAt;

  /// Simple UI lock: hash of the PIN. Null means unlocked note.
  int? pinHash;

  /// Version history (capped by the controller, newest last).
  List<NoteSnapshot> history;

  /// Daily word goal for this note. 0 means no goal.
  int wordGoal;

  /// Attached files.
  List<NoteAttachment> attachments;

  static final _listPrefix =
      RegExp(r'^(☐|☒|\[[ xX]\]|[-•*]|\d+[.)])\s*');

  static final _tagRe = RegExp(r'#([A-Za-z0-9_\-]+)');

  String get title {
    for (final line in body.split('\n')) {
      final t = line.trim().replaceFirst(_listPrefix, '').trim();
      if (t.isNotEmpty) return t;
    }
    return 'New note';
  }

  String get snippet {
    final lines =
        body.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.length <= 1) return '';
    return lines.skip(1).join(' ').trim();
  }

  bool get hasDiagram => strokes.isNotEmpty;
  bool get isLocked => pinHash != null;
  bool get isOverdue =>
      dueAt != null && dueAt!.isBefore(DateTime.now()) && !trashed;

  bool get isTrashExpired {
    if (!trashed || trashedAt == null) return false;
    return DateTime.now().difference(trashedAt!).inDays >= 30;
  }

  int get wordCount {
    final t = body.trim();
    if (t.isEmpty) return 0;
    return t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  double get goalProgress {
    if (wordGoal <= 0) return 0;
    return (wordCount / wordGoal).clamp(0.0, 1.0).toDouble();
  }

  /// (done, total) checklist counts.
  (int, int) checklistCounts() {
    var done = 0;
    var total = 0;
    for (final line in body.split('\n')) {
      final t = line.trimLeft();
      if (t.startsWith('☐ ')) {
        total++;
      } else if (t.startsWith('☒ ')) {
        total++;
        done++;
      }
    }
    return (done, total);
  }

  double checklistProgress() {
    final (done, total) = checklistCounts();
    if (total == 0) return 0;
    return done / total;
  }

  /// Tags mentioned inline as `#tag` plus explicit [tags].
  List<String> effectiveTags() {
    final out = <String>{...tags};
    for (final m in _tagRe.allMatches(body)) {
      out.add(m.group(1)!.toLowerCase());
    }
    return out.toList()..sort();
  }

  static List<String> extractTags(String body) {
    final out = <String>{};
    for (final m in _tagRe.allMatches(body)) {
      out.add(m.group(1)!.toLowerCase());
    }
    return out.toList()..sort();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'body': body,
        'colorIndex': colorIndex,
        'pinned': pinned,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'strokes': [for (final s in strokes) s.toJson()],
        'formats': [for (final f in formats) f.toJson()],
        'tags': tags,
        'favorite': favorite,
        'archived': archived,
        'trashed': trashed,
        'trashedAt': trashedAt?.millisecondsSinceEpoch,
        'dueAt': dueAt?.millisecondsSinceEpoch,
        'pinHash': pinHash,
        'history': [for (final h in history) h.toJson()],
        'wordGoal': wordGoal,
        'attachments': [for (final a in attachments) a.toJson()],
      };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as String,
        body: json['body'] as String? ?? '',
        colorIndex: (json['colorIndex'] as num?)?.toInt() ?? 0,
        pinned: json['pinned'] as bool? ?? false,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (json['createdAt'] as num?)?.toInt() ?? 0,
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['updatedAt'] as num?)?.toInt() ?? 0,
        ),
        strokes: [
          for (final s in (json['strokes'] as List? ?? []))
            StrokeItem.fromJson(s as Map<String, dynamic>),
        ],
        formats: [
          for (final f in (json['formats'] as List? ?? []))
            FormatSpan.fromJson(f as Map<String, dynamic>),
        ],
        tags: [
          for (final t in (json['tags'] as List? ?? [])) t.toString(),
        ],
        favorite: json['favorite'] as bool? ?? false,
        archived: json['archived'] as bool? ?? false,
        trashed: json['trashed'] as bool? ?? false,
        trashedAt: (json['trashedAt'] as num?) == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (json['trashedAt'] as num).toInt()),
        dueAt: (json['dueAt'] as num?) == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (json['dueAt'] as num).toInt()),
        pinHash: (json['pinHash'] as num?)?.toInt(),
        history: [
          for (final h in (json['history'] as List? ?? []))
            NoteSnapshot.fromJson(h as Map<String, dynamic>),
        ],
        wordGoal: (json['wordGoal'] as num?)?.toInt() ?? 0,
        attachments: [
          for (final a in (json['attachments'] as List? ?? []))
            NoteAttachment.fromJson(a as Map<String, dynamic>),
        ],
      );
}

/// Very small non-cryptographic PIN hash (UI lock, not encryption).
int pinHashOf(String pin) {
  var h = 5381;
  for (final c in pin.codeUnits) {
    h = ((h << 5) + h + c) & 0x7fffffff;
  }
  return h;
}
