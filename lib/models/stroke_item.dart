import 'dart:ui' show Color, Offset;

/// The kind of drawn item on a note's diagram canvas.
enum StrokeType { pen, marker, line, rectangle, ellipse, arrow, text }

/// A single drawn item on the diagram canvas, stored in world coordinates.
/// For [StrokeType.text] the first point is the top-left anchor and [width]
/// holds the font size.
class StrokeItem {
  StrokeItem({
    required this.id,
    required this.type,
    required this.points,
    required this.colorValue,
    required this.width,
    this.filled = false,
    this.text,
  });

  final String id;
  final StrokeType type;

  /// Freehand tools have many points; shapes have exactly [start, end].
  final List<Offset> points;

  final int colorValue;
  final double width;
  final bool filled;

  /// Label content for [StrokeType.text].
  final String? text;

  Color get color => Color(colorValue);

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'points': [
          for (final p in points) [p.dx, p.dy],
        ],
        'color': colorValue,
        'width': width,
        'filled': filled,
        if (text != null) 'text': text,
      };

  factory StrokeItem.fromJson(Map<String, dynamic> json) => StrokeItem(
        id: json['id'] as String,
        type: StrokeType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => StrokeType.pen,
        ),
        points: [
          for (final p in (json['points'] as List? ?? []))
            Offset(
              ((p as List)[0] as num).toDouble(),
              (p[1] as num).toDouble(),
            ),
        ],
        colorValue: (json['color'] as num?)?.toInt() ?? 0xFF000000,
        width: (json['width'] as num?)?.toDouble() ?? 3,
        filled: json['filled'] as bool? ?? false,
        text: json['text'] as String?,
      );
}
