import 'dart:math' as math;
import 'dart:ui' show Canvas, Color, Offset, Paint, PaintingStyle, Path, Rect, StrokeCap, StrokeJoin;

import 'package:flutter/painting.dart' show TextDirection, TextPainter, TextSpan, TextStyle;

import '../../models/stroke_item.dart';

/// Lays out a text-label stroke at its stored font size ([StrokeItem.width]).
TextPainter layoutTextLabel(StrokeItem s, {Color? color}) {
  final tp = TextPainter(
    text: TextSpan(
      text: s.text ?? '',
      style: TextStyle(
        color: color ?? const Color(0xFF000000),
        fontSize: s.width.clamp(8.0, 128.0).toDouble(),
        fontFamily: 'Segoe UI',
        height: 1.25,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 900);
  return tp;
}

/// Bounding box of a stroke as rendered, used for selection and hit-testing.
Rect strokeBounds(StrokeItem s) {
  if (s.points.isEmpty) return Rect.zero;
  if (s.type == StrokeType.text && (s.text?.isNotEmpty ?? false)) {
    final tp = layoutTextLabel(s);
    return Rect.fromLTWH(
      s.points.first.dx,
      s.points.first.dy,
      tp.width,
      tp.height,
    ).inflate(3);
  }
  var r = Rect.fromPoints(s.points.first, s.points.first);
  for (final p in s.points) {
    r = r.expandToInclude(Rect.fromPoints(p, p));
  }
  return r.inflate(s.width / 2 + 2);
}

/// Draws one stroke onto [canvas]. Used by the main canvas painter and the
/// sidebar thumbnails.
void paintStroke(
  Canvas canvas,
  StrokeItem s, {
  Color? colorOverride,
  double widthScale = 1,
}) {
  final isMarker = s.type == StrokeType.marker;
  final paint = Paint()
    ..color = colorOverride ??
        (isMarker ? s.color.withValues(alpha: 0.38) : s.color)
    ..style = PaintingStyle.stroke
    ..strokeWidth = (isMarker ? s.width * 3.2 : s.width) * widthScale
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  switch (s.type) {
    case StrokeType.pen:
    case StrokeType.marker:
      _paintFreehand(canvas, s, paint);
    case StrokeType.line:
      if (s.points.length < 2) return;
      canvas.drawLine(s.points[0], s.points[1], paint);
    case StrokeType.rectangle:
      if (s.points.length < 2) return;
      paint.style =
          s.filled ? PaintingStyle.fill : PaintingStyle.stroke;
      canvas.drawRect(Rect.fromPoints(s.points[0], s.points[1]), paint);
    case StrokeType.ellipse:
      if (s.points.length < 2) return;
      paint.style =
          s.filled ? PaintingStyle.fill : PaintingStyle.stroke;
      canvas.drawOval(Rect.fromPoints(s.points[0], s.points[1]), paint);
    case StrokeType.arrow:
      _paintArrow(canvas, s, paint);
    case StrokeType.text:
      if (s.points.isEmpty || (s.text?.isEmpty ?? true)) return;
      layoutTextLabel(s, color: paint.color).paint(canvas, s.points.first);
  }
}

void _paintFreehand(Canvas canvas, StrokeItem s, Paint paint) {
  final pts = s.points;
  if (pts.isEmpty) return;
  if (pts.length == 1) {
    canvas.drawCircle(
      pts.first,
      paint.strokeWidth / 2,
      Paint()
        ..color = paint.color
        ..style = PaintingStyle.fill,
    );
    return;
  }
  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (var i = 1; i < pts.length - 1; i++) {
    final mid = Offset(
      (pts[i].dx + pts[i + 1].dx) / 2,
      (pts[i].dy + pts[i + 1].dy) / 2,
    );
    path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
  }
  path.lineTo(pts.last.dx, pts.last.dy);
  canvas.drawPath(path, paint);
}

void _paintArrow(Canvas canvas, StrokeItem s, Paint paint) {
  if (s.points.length < 2) return;
  final a = s.points[0];
  final b = s.points[1];
  canvas.drawLine(a, b, paint);
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < 1) return;
  final head = math.max(12.0, paint.strokeWidth * 3);
  final angle = math.atan2(dy, dx);
  Offset tip(double spread) => Offset(
        b.dx - head * math.cos(angle - spread),
        b.dy - head * math.sin(angle - spread),
      );
  canvas.drawLine(b, tip(0.42), paint);
  canvas.drawLine(b, tip(-0.42), paint);
}

/// True when [p] (with eraser [radius]) touches the rendered stroke.
bool strokeHitTest(StrokeItem s, Offset p, double radius) {
  final pad = radius + s.width / 2;
  switch (s.type) {
    case StrokeType.text:
      if (s.text?.isEmpty ?? true) return false;
      return strokeBounds(s).contains(p);
    case StrokeType.pen:
    case StrokeType.marker:
    case StrokeType.line:
    case StrokeType.arrow:
      final pts = s.points;
      if (pts.isEmpty) return false;
      if (pts.length == 1) return (pts.first - p).distance <= pad;
      for (var i = 0; i < pts.length - 1; i++) {
        if (_distanceToSegment(p, pts[i], pts[i + 1]) <= pad) return true;
      }
      return false;
    case StrokeType.rectangle:
      if (s.points.length < 2) return false;
      final r = Rect.fromPoints(s.points[0], s.points[1]);
      if (s.filled) return r.contains(p);
      if (!r.inflate(radius).contains(p)) return false;
      final dEdge = math.min(
        math.min(p.dx - r.left, r.right - p.dx),
        math.min(p.dy - r.top, r.bottom - p.dy),
      );
      return dEdge <= pad;
    case StrokeType.ellipse:
      if (s.points.length < 2) return false;
      final r = Rect.fromPoints(s.points[0], s.points[1]);
      final rx = r.width / 2;
      final ry = r.height / 2;
      if (rx <= 0 || ry <= 0) return (r.center - p).distance <= pad;
      if (s.filled) {
        final nx = (p.dx - r.center.dx) / rx;
        final ny = (p.dy - r.center.dy) / ry;
        return nx * nx + ny * ny <= 1;
      }
      for (var i = 0; i < 48; i++) {
        final t = i * 2 * math.pi / 48;
        final q = Offset(
          r.center.dx + rx * math.cos(t),
          r.center.dy + ry * math.sin(t),
        );
        if ((q - p).distance <= pad) return true;
      }
      return false;
  }
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ap = p - a;
  final ab = b - a;
  final len2 = ab.distanceSquared;
  if (len2 == 0) return ap.distance;
  var t = (ap.dx * ab.dx + ap.dy * ab.dy) / len2;
  t = t.clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}
