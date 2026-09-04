import 'format_span.dart';
import 'stroke_item.dart';

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
  })  : strokes = strokes ?? [],
        formats = formats ?? [];

  final String id;
  String body;
  int colorIndex;
  bool pinned;
  final DateTime createdAt;
  DateTime updatedAt;
  List<StrokeItem> strokes;

  /// Rich-text formatting ranges over [body].
  List<FormatSpan> formats;

  static final _listPrefix =
      RegExp(r'^(☐|☒|\[[ xX]\]|[-•*]|\d+[.)])\s*');

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'body': body,
        'colorIndex': colorIndex,
        'pinned': pinned,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'strokes': [for (final s in strokes) s.toJson()],
        'formats': [for (final f in formats) f.toJson()],
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
      );
}
