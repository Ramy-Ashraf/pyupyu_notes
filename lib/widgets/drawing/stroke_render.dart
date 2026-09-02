import 'dart:math' as math;
import 'dart:ui' show Canvas, Color, Offset, Paint, PaintingStyle, Path, Rect, StrokeCap, StrokeJoin;

import 'package:flutter/painting.dart' show TextDirection, TextPainter, TextSpan, TextStyle;

import '../../models/stroke_item.dart';

/// How sketchy the Excalidraw-style rendering is (1 = subtle, 2 = cartoon).
const double _roughness = 1.2;

/// Lays out a text-label stroke at its stored font size ([StrokeItem.width]).
/// Labels render in a handwritten font (Windows' Segoe Print) and support
/// multi-line content — lines only break where the text contains `\n`.
TextPainter layoutTextLabel(StrokeItem s, {Color? color}) {
  final tp = TextPainter(
    text: TextSpan(
      text: s.text ?? '',
      style: TextStyle(
        color: color ?? const Color(0xFF000000),
        fontSize: s.width.clamp(8.0, 128.0).toDouble(),
        fontFamily: 'Segoe Print',
        height: 1.25,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  return tp;
}

/// Bounding box of a stroke's unrotated geometry, used as the local frame
/// for selection and transforms.
Rect strokeLocalBounds(StrokeItem s) {
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
  // +4 covers the rough outline's wobble beyond the pure geometry.
  return r.inflate(s.width / 2 + 4);
}

/// Axis-aligned bounding box in world space, accounting for [StrokeItem.angle].
Rect strokeBounds(StrokeItem s) {
  final r = strokeLocalBounds(s);
  if (s.angle == 0) return r;
  final c = r.center;
  final cos = math.cos(s.angle);
  final sin = math.sin(s.angle);
  Offset rot(Offset p) {
    final dx = p.dx - c.dx;
    final dy = p.dy - c.dy;
    return Offset(c.dx + dx * cos - dy * sin, c.dy + dx * sin + dy * cos);
  }

  var out = Rect.fromPoints(rot(r.topLeft), rot(r.topRight));
  out = out.expandToInclude(
      Rect.fromPoints(rot(r.bottomRight), rot(r.bottomLeft)));
  return out;
}

/// The selection frame of a stroke: its unrotated local bounds plus the
/// rotation about the frame center, with local↔world mapping. Handles are
/// placed in the local frame and mapped through [toWorld], and pointer
/// positions are mapped through [toLocal] before hit-testing them.
class SelectionBox {
  const SelectionBox(this.localRect, this.angle);

  final Rect localRect;
  final double angle;

  Offset get center => localRect.center;

  Offset toWorld(Offset p) => _rot(p, angle);

  Offset toLocal(Offset p) => _rot(p, -angle);

  Offset _rot(Offset p, double a) {
    if (a == 0) return p;
    final dx = p.dx - center.dx;
    final dy = p.dy - center.dy;
    final cos = math.cos(a);
    final sin = math.sin(a);
    return Offset(
      center.dx + dx * cos - dy * sin,
      center.dy + dx * sin + dy * cos,
    );
  }

  List<Offset> corners() => [
        toWorld(localRect.topLeft),
        toWorld(localRect.topRight),
        toWorld(localRect.bottomRight),
        toWorld(localRect.bottomLeft),
      ];
}

SelectionBox selectionBoxFor(StrokeItem s) =>
    SelectionBox(strokeLocalBounds(s), s.angle);

/// Draws one stroke onto [canvas]. Used by the main canvas painter and the
/// sidebar thumbnails. Shapes render in a sketchy Excalidraw-like style:
/// two slightly different wobbly outlines per stroke, seeded by the stroke
/// so the look is stable across frames. Strokes with an [StrokeItem.angle]
/// are rotated about their bounds center.
void paintStroke(
  Canvas canvas,
  StrokeItem s, {
  Color? colorOverride,
  double widthScale = 1,
}) {
  if (s.angle != 0) {
    final c = strokeLocalBounds(s).center;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(s.angle);
    canvas.translate(-c.dx, -c.dy);
    _paintStrokeUnrotated(canvas, s,
        colorOverride: colorOverride, widthScale: widthScale);
    canvas.restore();
    return;
  }
  _paintStrokeUnrotated(canvas, s,
      colorOverride: colorOverride, widthScale: widthScale);
}

void _paintStrokeUnrotated(
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
    case StrokeType.arrow:
    case StrokeType.rectangle:
    case StrokeType.diamond:
    case StrokeType.ellipse:
      if (s.points.length < 2) return;
      _paintRoughShape(canvas, s, paint);
    case StrokeType.text:
      if (s.points.isEmpty || (s.text?.isEmpty ?? true)) return;
      layoutTextLabel(s, color: paint.color).paint(canvas, s.points.first);
  }
}

// ---- rough shapes ---------------------------------------------------------

void _paintRoughShape(Canvas canvas, StrokeItem s, Paint paint) {
  final a = s.points[0];
  final b = s.points[1];
  if (s.filled) _paintFill(canvas, s, paint);

  switch (s.type) {
    case StrokeType.line:
      _roughSegment(canvas, a, b, s, paint, 0);
    case StrokeType.arrow:
      _roughSegment(canvas, a, b, s, paint, 0);
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
      _roughSegment(canvas, b, tip(0.42), s, paint, 3);
      _roughSegment(canvas, b, tip(-0.42), s, paint, 4);
    case StrokeType.rectangle:
      _roughPolygon(
        canvas,
        [a, Offset(b.dx, a.dy), b, Offset(a.dx, b.dy)],
        s,
        paint,
      );
    case StrokeType.diamond:
      final c = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      _roughPolygon(
        canvas,
        [
          Offset(c.dx, a.dy),
          Offset(b.dx, c.dy),
          Offset(c.dx, b.dy),
          Offset(a.dx, c.dy),
        ],
        s,
        paint,
      );
    case StrokeType.ellipse:
      for (final pass in const [0, 1]) {
        _drawPolyline(
          canvas,
          _roughEllipsePts(Rect.fromPoints(a, b), s.seed, pass),
          paint,
          s,
        );
      }
    default:
      break;
  }
}

void _roughSegment(
  Canvas canvas,
  Offset a,
  Offset b,
  StrokeItem s,
  Paint paint,
  int passBase,
) {
  for (final pass in const [0, 1]) {
    _drawPolyline(
      canvas,
      _roughPolyline([a, b], closed: false, seed: s.seed + passBase, pass: pass),
      paint,
      s,
    );
  }
}

void _roughPolygon(
  Canvas canvas,
  List<Offset> poly,
  StrokeItem s,
  Paint paint,
) {
  for (final pass in const [0, 1]) {
    _drawPolyline(
      canvas,
      _roughPolyline(poly, closed: true, seed: s.seed, pass: pass),
      paint,
      s,
    );
  }
}

/// Subdivides each edge and jitters interior points perpendicular to the
/// edge; vertices stay pinned so corners remain sharp.
List<Offset> _roughPolyline(
  List<Offset> pts, {
  required bool closed,
  required int seed,
  required int pass,
}) {
  if (pts.length < 2) return pts;
  final rnd = math.Random(seed * 7 + pass * 1013 + 17);
  final out = <Offset>[];
  final edgeCount = closed ? pts.length : pts.length - 1;
  for (var i = 0; i < edgeCount; i++) {
    final a = pts[i];
    final b = pts[(i + 1) % pts.length];
    final len = (b - a).distance;
    if (len <= 0) continue;
    final dir = (b - a) / len;
    final perp = Offset(-dir.dy, dir.dx);
    final amp = math.min(len * 0.08, 3.2) * _roughness;
    final steps = (len / 16).ceil().clamp(1, 8).toInt();
    if (out.isEmpty) out.add(a);
    for (var k = 1; k < steps; k++) {
      final t = k / steps;
      final o = (rnd.nextDouble() * 2 - 1) * amp;
      out.add(a + (b - a) * t + perp * o);
    }
    out.add(b);
  }
  return out;
}

List<Offset> _roughEllipsePts(Rect r, int seed, int pass) {
  final rnd = math.Random(seed * 7 + pass * 1013 + 91);
  final c = r.center;
  final rx = r.width / 2;
  final ry = r.height / 2;
  final size = math.max(math.max(rx, ry), 1.0);
  const n = 26;
  final amp = math.min(2.8, size * 0.045) * _roughness;
  final offs = [for (var i = 0; i < n; i++) (rnd.nextDouble() * 2 - 1) * amp];
  final pts = <Offset>[];
  for (var i = 0; i <= n; i++) {
    final t = i * 2 * math.pi / n;
    final o = offs[i % n];
    pts.add(Offset(c.dx + (rx + o) * math.cos(t), c.dy + (ry + o) * math.sin(t)));
  }
  return pts;
}

void _drawPolyline(Canvas canvas, List<Offset> pts, Paint paint, StrokeItem s) {
  if (pts.length < 2) return;
  final dash = _dashOf(s);
  if (dash == DashStyles.solid) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(path, paint);
  } else {
    _drawDashed(canvas, pts, paint, dash, paint.strokeWidth);
  }
}

/// Freehand strokes don't support dash styles (like Excalidraw's freedraw).
int _dashOf(StrokeItem s) =>
    s.type == StrokeType.pen || s.type == StrokeType.marker
        ? DashStyles.solid
        : s.dash;

/// Walks the polyline, emitting on/off sub-segments. With round caps, the
/// tiny "on" phases of dotted style render as dots.
void _drawDashed(
  Canvas canvas,
  List<Offset> pts,
  Paint paint,
  int dash,
  double width,
) {
  final on = dash == DashStyles.dotted ? 0.75 : width * 2.0 + 7;
  final off = dash == DashStyles.dotted ? width * 2.4 + 6 : width * 1.5 + 5;
  var inOn = true;
  var phasePos = 0.0;
  for (var i = 0; i < pts.length - 1; i++) {
    final a = pts[i];
    final b = pts[i + 1];
    final segLen = (b - a).distance;
    if (segLen <= 0) continue;
    var t = 0.0;
    while (t < segLen - 1e-6) {
      final phaseLen = inOn ? on : off;
      final t1 = math.min(segLen, t + phaseLen - phasePos);
      if (inOn && t1 > t) {
        canvas.drawLine(a + (b - a) * t, a + (b - a) * t1, paint);
      }
      phasePos += t1 - t;
      if (phasePos >= phaseLen - 1e-6) {
        phasePos = 0;
        inOn = !inOn;
      }
      t = t1;
    }
  }
}

// ---- fills ----------------------------------------------------------------

void _paintFill(Canvas canvas, StrokeItem s, Paint strokePaint) {
  final a = s.points[0];
  final b = s.points[1];
  final rect = Rect.fromPoints(a, b);
  final List<Offset> poly;
  switch (s.type) {
    case StrokeType.diamond:
      final c = rect.center;
      poly = [
        Offset(c.dx, rect.top),
        Offset(rect.right, c.dy),
        Offset(c.dx, rect.bottom),
        Offset(rect.left, c.dy),
      ];
    case StrokeType.ellipse:
      final c = rect.center;
      poly = [
        for (var i = 0; i < 24; i++)
          Offset(
            c.dx + rect.width / 2 * math.cos(i * 2 * math.pi / 24),
            c.dy + rect.height / 2 * math.sin(i * 2 * math.pi / 24),
          ),
      ];
    default:
      poly = [a, Offset(b.dx, a.dy), b, Offset(a.dx, b.dy)];
  }

  if (s.fillStyle == FillStyles.solid) {
    final fillPaint = Paint()
      ..color = strokePaint.color
      ..style = PaintingStyle.fill;
    if (s.type == StrokeType.ellipse) {
      canvas.drawOval(rect, fillPaint);
    } else {
      canvas.drawPath(Path()..addPolygon(poly, true), fillPaint);
    }
    return;
  }

  final hatchPaint = Paint()
    ..color = strokePaint.color
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1.0, strokePaint.strokeWidth * 0.65)
    ..strokeCap = StrokeCap.round;
  final spacing = math.max(6.0, s.width * 1.9);
  final angles =
      s.fillStyle == FillStyles.crossHatch ? const [45.0, -45.0] : const [45.0];
  for (final angle in angles) {
    for (final seg in _hatchPolygon(poly, spacing, angle)) {
      canvas.drawLine(seg.$1, seg.$2, hatchPaint);
    }
  }
}

/// Parallel hatch lines across a convex polygon via scanline at [angleDeg].
List<(Offset, Offset)> _hatchPolygon(
  List<Offset> poly,
  double spacing,
  double angleDeg,
) {
  if (poly.isEmpty) return const [];
  var cx = 0.0;
  var cy = 0.0;
  for (final p in poly) {
    cx += p.dx;
    cy += p.dy;
  }
  cx /= poly.length;
  cy /= poly.length;
  final rad = angleDeg * math.pi / 180;
  final cos = math.cos(-rad);
  final sin = math.sin(-rad);
  Offset fwd(Offset p) {
    final dx = p.dx - cx;
    final dy = p.dy - cy;
    return Offset(cx + dx * cos - dy * sin, cy + dx * sin + dy * cos);
  }

  final bcos = math.cos(rad);
  final bsin = math.sin(rad);
  Offset back(Offset p) {
    final dx = p.dx - cx;
    final dy = p.dy - cy;
    return Offset(cx + dx * bcos - dy * bsin, cy + dx * bsin + dy * bcos);
  }

  final rp = [for (final p in poly) fwd(p)];
  var minY = rp.first.dy;
  var maxY = rp.first.dy;
  for (final p in rp) {
    minY = math.min(minY, p.dy);
    maxY = math.max(maxY, p.dy);
  }
  final out = <(Offset, Offset)>[];
  for (var y = minY + spacing / 2; y < maxY; y += spacing) {
    final xs = <double>[];
    for (var i = 0; i < rp.length; i++) {
      final p = rp[i];
      final q = rp[(i + 1) % rp.length];
      if ((p.dy <= y && q.dy > y) || (q.dy <= y && p.dy > y)) {
        xs.add(p.dx + (q.dx - p.dx) * (y - p.dy) / (q.dy - p.dy));
      }
    }
    if (xs.length < 2) continue;
    xs.sort();
    final x0 = xs.first + 1.0;
    final x1 = xs.last - 1.0;
    if (x1 <= x0) continue;
    out.add((back(Offset(x0, y)), back(Offset(x1, y))));
  }
  return out;
}

// ---- freehand (kept smooth, like Excalidraw's freedraw) --------------------

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

/// True when [p] (with eraser [radius]) touches the rendered stroke.
/// Rotation-aware: [p] is mapped into the stroke's local frame first.
bool strokeHitTest(StrokeItem s, Offset p, double radius) {
  final pad = radius + s.width / 2;
  if (s.angle != 0) {
    final c = strokeLocalBounds(s).center;
    final cos = math.cos(-s.angle);
    final sin = math.sin(-s.angle);
    final dx = p.dx - c.dx;
    final dy = p.dy - c.dy;
    p = Offset(c.dx + dx * cos - dy * sin, c.dy + dx * sin + dy * cos);
  }
  switch (s.type) {
    case StrokeType.text:
      if (s.text?.isEmpty ?? true) return false;
      return strokeLocalBounds(s).contains(p);
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
    case StrokeType.diamond:
      if (s.points.length < 2) return false;
      final poly = _diamondPoly(s.points[0], s.points[1]);
      if (s.filled) return _pointInPolygon(poly, p);
      for (var i = 0; i < poly.length; i++) {
        if (_distanceToSegment(p, poly[i], poly[(i + 1) % poly.length]) <= pad) {
          return true;
        }
      }
      return false;
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

List<Offset> _diamondPoly(Offset a, Offset b) {
  final c = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
  return [
    Offset(c.dx, a.dy),
    Offset(b.dx, c.dy),
    Offset(c.dx, b.dy),
    Offset(a.dx, c.dy),
  ];
}

bool _pointInPolygon(List<Offset> poly, Offset p) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i];
    final b = poly[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
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
