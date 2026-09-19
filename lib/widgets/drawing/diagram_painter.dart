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
    required this.selected,
    required this.showHandles,
    required this.marquee,
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
  final List<StrokeItem> selected;

  /// Draw resize/rotate handles for a single selection.
  final bool showHandles;

  /// Rubber-band rectangle (world coords) while marquee-selecting.
  final Rect? marquee;
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
    for (final s in selected) {
      _drawSelectionOutline(canvas, s);
    }
    if (showHandles && selected.length == 1) {
      _drawSelectionHandles(canvas, selected.first);
    }
    final m = marquee;
    if (m != null) _drawMarquee(canvas, m);
    canvas.restore();
  }

  /// Dashed selection frame hugging the shape: one continuous dash rhythm
  /// around the whole perimeter so corners stay crisp. Screen-constant size.
  void _drawSelectionOutline(Canvas canvas, StrokeItem s) {
    final corners = tightSelectionBoxFor(s).corners();
    final paint = Paint()
      ..color = selectionColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 / scale
      ..strokeCap = StrokeCap.butt;
    final on = 5.0 / scale;
    final off = 3.5 / scale;
    final period = on + off;
    final pts = [...corners, corners.first];
    var phase = 0.0;
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i];
      final b = pts[i + 1];
      final len = (b - a).distance;
      if (len <= 0) continue;
      final dir = (b - a) / len;
      var t = 0.0;
      var guard = 0;
      // The epsilon snap + iteration cap guarantee termination: without
      // them a phase landing within one ulp below a boundary would make
      // `t + remaining == t`, freezing the app on that frame.
      while (t < len - 1e-9 && guard++ < 100000) {
        final remaining =
            phase < on ? on - phase : period - phase;
        if (remaining <= 1e-6) {
          phase = phase < on ? on : 0.0;
          continue;
        }
        final t1 = math.min(t + remaining, len);
        if (phase < on && t1 > t) {
          canvas.drawLine(a + dir * t, a + dir * t1, paint);
        }
        phase = (phase + (t1 - t)) % period;
        if (t1 <= t) break;
        t = t1;
      }
    }
  }

  /// Excalidraw-style transform UI: 8 resize handles (corners + edge
  /// midpoints) and a round rotate handle above the top edge. Sizes are
  /// divided by [scale] so they stay constant on screen.
  void _drawSelectionHandles(Canvas canvas, StrokeItem s) {
    final box = tightSelectionBoxFor(s);
    final r = box.localRect;
    final half = 4.5 / scale;
    final fill = Paint()..color = const Color(0xFFFFFFFF);
    final border = Paint()
      ..color = selectionColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 / scale;

    void handle(Offset world) {
      canvas.drawRect(
        Rect.fromCenter(center: world, width: half * 2, height: half * 2),
        fill,
      );
      canvas.drawRect(
        Rect.fromCenter(center: world, width: half * 2, height: half * 2),
        border,
      );
    }

    for (final c in box.corners()) {
      handle(c);
    }
    handle(box.toWorld(Offset(r.center.dx, r.top)));
    handle(box.toWorld(Offset(r.right, r.center.dy)));
    handle(box.toWorld(Offset(r.center.dx, r.bottom)));
    handle(box.toWorld(Offset(r.left, r.center.dy)));

    final top = box.toWorld(Offset(r.center.dx, r.top));
    final rot = box.toWorld(Offset(r.center.dx, r.top - 22 / scale));
    canvas.drawLine(top, rot, border);
    canvas.drawCircle(rot, 5 / scale, fill);
    canvas.drawCircle(rot, 5 / scale, border);
  }

  /// Dashed rubber band with a faint fill, drawn while marquee-selecting.
  void _drawMarquee(Canvas canvas, Rect m) {
    canvas.drawRect(
      m,
      Paint()..color = selectionColor.withValues(alpha: 0.08),
    );
    final paint = Paint()
      ..color = selectionColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / scale;
    const on = 6.0, off = 4.0;
    final pts = [
      m.topLeft,
      m.topRight,
      m.bottomRight,
      m.bottomLeft,
      m.topLeft,
    ];
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i];
      final b = pts[i + 1];
      final len = (b - a).distance;
      if (len == 0) continue;
      var drawing = true;
      var remain = on;
      var t = 0.0;
      while (t < len - 1e-6) {
        final take = math.min(remain, len - t);
        if (drawing) {
          canvas.drawLine(a + (b - a) * t, a + (b - a) * (t + take), paint);
        }
        t += take;
        remain -= take;
        if (remain <= 1e-6) {
          remain = drawing ? off : on;
          drawing = !drawing;
        }
      }
    }
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
        oldDelegate.showHandles != showHandles ||
        oldDelegate.marquee != marquee ||
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
