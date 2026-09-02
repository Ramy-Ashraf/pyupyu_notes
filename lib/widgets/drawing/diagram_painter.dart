import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/stroke_item.dart';
import 'stroke_render.dart';

/// Paints the note's diagram: a subtle dot grid plus all strokes, the
/// in-progress stroke on top, and corner brackets around the selected stroke.
/// Supports pan ([offset]) and zoom ([scale]).
class DiagramPainter extends CustomPainter {
  DiagramPainter({
    required this.strokes,
    required this.active,
    required this.activePointCount,
    required this.activeEnd,
    required this.offset,
    required this.scale,
    required this.background,
    required this.gridColor,
    required this.showGrid,
    this.selected,
    required this.selectionColor,
  });

  final List<StrokeItem> strokes;
  final StrokeItem? active;

  // Tracks in-place mutations of [active] so shouldRepaint stays correct.
  final int activePointCount;
  final Offset? activeEnd;

  final Offset offset;
  final double scale;
  final Color background;
  final Color gridColor;
  final bool showGrid;
  final StrokeItem? selected;
  final Color selectionColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);

    if (showGrid && scale > 0.3) {
      const spacing = 32.0;
      final tlX = -offset.dx / scale;
      final tlY = -offset.dy / scale;
      final brX = (size.width - offset.dx) / scale;
      final brY = (size.height - offset.dy) / scale;
      final dot = Paint()..color = gridColor;
      final r = 1.1 / scale;
      final startX = (tlX / spacing).floorToDouble() * spacing;
      final startY = (tlY / spacing).floorToDouble() * spacing;
      for (var x = startX; x <= brX; x += spacing) {
        for (var y = startY; y <= brY; y += spacing) {
          canvas.drawCircle(Offset(x, y), r, dot);
        }
      }
    }

    for (final s in strokes) {
      paintStroke(canvas, s);
    }
    final a = active;
    if (a != null) paintStroke(canvas, a);
    final sel = selected;
    if (sel != null && sel.points.isNotEmpty) {
      _drawBrackets(canvas, strokeBounds(sel), scale, selectionColor);
    }
    canvas.restore();
  }

  void _drawBrackets(Canvas canvas, Rect bounds, double scale, Color color) {
    final r = bounds.inflate(5 / scale);
    final arm = 10 / scale;
    final path = Path();
    void corner(double x, double y, double dx, double dy) {
      path
        ..moveTo(x + dx * arm, y)
        ..lineTo(x, y)
        ..lineTo(x, y + dy * arm);
    }

    corner(r.left, r.top, 1, 1);
    corner(r.right, r.top, -1, 1);
    corner(r.left, r.bottom, 1, -1);
    corner(r.right, r.bottom, -1, -1);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 / scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant DiagramPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.active != active ||
        oldDelegate.activePointCount != activePointCount ||
        oldDelegate.activeEnd != activeEnd ||
        oldDelegate.offset != offset ||
        oldDelegate.scale != scale ||
        oldDelegate.background != background ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.selected != selected ||
        oldDelegate.selectionColor != selectionColor;
  }
}

/// Tiny monochrome preview of a note's diagram, fitted into a sidebar card.
class StrokeThumbPainter extends CustomPainter {
  StrokeThumbPainter({required this.strokes, required this.color});

  final List<StrokeItem> strokes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isEmpty) return;
    Rect? bounds;
    for (final s in strokes) {
      if (s.points.isEmpty) continue;
      // strokeBounds accounts for text labels, whose extent is not in points.
      final b = strokeBounds(s);
      bounds = bounds == null ? b : bounds.expandToInclude(b);
    }
    final b = bounds;
    if (b == null) return;
    var fit = math.min(size.width / math.max(b.width, 1),
        size.height / math.max(b.height, 1));
    fit = math.min(fit * 0.92, 4.0);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(fit);
    canvas.translate(-b.center.dx, -b.center.dy);
    for (final s in strokes) {
      paintStroke(canvas, s, colorOverride: color, widthScale: 0.8);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant StrokeThumbPainter oldDelegate) {
    return oldDelegate.strokes != strokes || oldDelegate.color != color;
  }
}
