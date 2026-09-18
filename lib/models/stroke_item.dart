import 'dart:ui' show Color, Offset;

/// The kind of drawn item on a note's diagram canvas.
enum StrokeType {
  pen,
  marker,
  line,
  rectangle,
  ellipse,
  diamond,
  arrow,
  text,
  sticky,
}

/// Fill looks for closed shapes (Excalidraw-style).
class FillStyles {
  static const int hachure = 0;
  static const int solid = 1;
  static const int crossHatch = 2;
}

/// Outline styles for shapes.
class DashStyles {
  static const int solid = 0;
  static const int dashed = 1;
  static const int dotted = 2;
}

/// A single drawn item on the diagram canvas, stored in world coordinates.
/// For [StrokeType.text] the first point is the top-left anchor and [width]
/// holds the font size. For [StrokeType.sticky] points are [topLeft,
/// bottomRight] like a rectangle and [text] is the sticky content.
class StrokeItem {
  StrokeItem({
    required this.id,
    required this.type,
    required this.points,
    required this.colorValue,
    required this.width,
    this.filled = false,
    this.fillStyle = FillStyles.hachure,
    this.dash = DashStyles.solid,
    this.seed = 0,
    this.angle = 0,
    this.text,
    this.locked = false,
  });

  final String id;
  final StrokeType type;

  /// Freehand tools have many points; shapes have exactly [start, end].
  final List<Offset> points;

  final int colorValue;
  final double width;

  /// Whether a closed shape has a fill at all.
  final bool filled;

  /// Fill look when [filled]: hachure, solid or cross-hatch.
  final int fillStyle;

  /// Outline style for shapes: solid, dashed or dotted.
  final int dash;

  /// Stable seed for the sketchy rendering, so the wobble doesn't change
  /// between frames. Old notes fall back to a value derived from the id.
  final int seed;

  /// Rotation in radians about the stroke's bounds center
  /// (Excalidraw-style transform).
  final double angle;

  /// Label content for [StrokeType.text] and [StrokeType.sticky].
  final String? text;

  /// Locked strokes cannot be moved, resized or erased until unlocked.
  final bool locked;

  Color get color => Color(colorValue);

  StrokeItem copyWith({
    String? id,
    StrokeType? type,
    List<Offset>? points,
    int? colorValue,
    double? width,
    bool? filled,
    int? fillStyle,
    int? dash,
    int? seed,
    double? angle,
    String? Function()? text,
    bool? locked,
  }) {
    return StrokeItem(
      id: id ?? this.id,
      type: type ?? this.type,
      points: points ?? List<Offset>.of(this.points),
      colorValue: colorValue ?? this.colorValue,
      width: width ?? this.width,
      filled: filled ?? this.filled,
      fillStyle: fillStyle ?? this.fillStyle,
      dash: dash ?? this.dash,
      seed: seed ?? this.seed,
      angle: angle ?? this.angle,
      text: text != null ? text() : this.text,
      locked: locked ?? this.locked,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'points': [
          for (final p in points) [p.dx, p.dy],
        ],
        'color': colorValue,
        'width': width,
        'filled': filled,
        'fillStyle': fillStyle,
        'dash': dash,
        'seed': seed,
        'angle': angle,
        if (text != null) 'text': text,
        if (locked) 'locked': true,
      };

  factory StrokeItem.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final filled = json['filled'] as bool? ?? false;
    return StrokeItem(
      id: id,
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
      filled: filled,
      // Notes saved before fill styles existed drew solid fills.
      fillStyle: (json['fillStyle'] as num?)?.toInt() ??
          (filled ? FillStyles.solid : FillStyles.hachure),
      dash: (json['dash'] as num?)?.toInt() ?? DashStyles.solid,
      seed: (json['seed'] as num?)?.toInt() ?? (id.hashCode & 0x7fffffff),
      angle: (json['angle'] as num?)?.toDouble() ?? 0,
      text: json['text'] as String?,
      locked: json['locked'] as bool? ?? false,
    );
  }
}
