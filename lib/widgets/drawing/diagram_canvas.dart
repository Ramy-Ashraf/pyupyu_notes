import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/notes_controller.dart';
import '../../models/note.dart';
import '../../models/stroke_item.dart';
import '../../theme/note_palette.dart';
import 'diagram_painter.dart';
import 'diagram_toolbar.dart';
import 'stroke_render.dart';

/// A recorded undo/redo step: full stroke-list snapshots before/after.
class _Op {
  _Op(this.before, this.after);
  final List<StrokeItem> before;
  final List<StrokeItem> after;
}

/// What a select-tool drag is currently doing.
enum _SelectDrag { none, move, resize, rotate, marquee }

/// Interactive diagram canvas for a note. Select/move/nudge, text labels,
/// freehand pen/highlighter, line/rectangle/ellipse/arrow shapes
/// (Shift-snapped), stroke eraser, pan + zoom (wheel, buttons or trackpad),
/// undo/redo, z-order controls via right-click. Strokes live on the note and
/// save automatically.
class DiagramCanvas extends StatefulWidget {
  const DiagramCanvas({
    super.key,
    required this.note,
    required this.controller,
  });

  final Note note;
  final NotesController controller;

  @override
  State<DiagramCanvas> createState() => _DiagramCanvasState();
}

class _DiagramCanvasState extends State<DiagramCanvas> {
  CanvasTool _tool = CanvasTool.pen;
  late Color _ink = WidgetsBinding
              .instance.platformDispatcher.platformBrightness ==
          Brightness.dark
      ? const Color(0xFFF5F5F5)
      : const Color(0xFF1F1F1F);
  double _width = 4;
  int _fillStyle = FillStyles.hachure;
  int _dashStyle = DashStyles.solid;
  bool _showGrid = true;

  // In-place text label editing (Excalidraw-style): a borderless field sits
  // right on the canvas; Esc or a click elsewhere commits it.
  double _labelSize = 18;
  TextEditingController? _labelField;
  FocusNode? _labelFocus;
  Offset _labelWorld = Offset.zero;
  String? _editingId;

  Offset _offset = Offset.zero;
  double _scale = 1;
  Size _viewSize = Size.zero;

  StrokeItem? _active;
  bool _panning = false;
  Offset _panStart = Offset.zero;
  Offset _panOffsetStart = Offset.zero;
  Offset _lastLocal = Offset.zero;
  Offset _downLocal = Offset.zero;
  final List<StrokeItem> _erased = [];

  // Trackpad pan/zoom gesture state.
  Offset _pzBaseOffset = Offset.zero;
  double _pzLastScale = 1;

  Set<String> _selectedIds = {};

  // Select-tool drag state: move / resize / rotate / marquee.
  _SelectDrag _drag = _SelectDrag.none;
  List<StrokeItem> _dragStartList = const [];
  Map<String, StrokeItem> _dragOrigMap = const {};
  Offset _dragStartWorld = Offset.zero;
  bool _dragMoved = false;
  StrokeItem? _resizeOriginal;
  int _resizeHandle = 0;
  StrokeItem? _rotateOriginal;
  Rect? _marquee;
  Offset _marqueeStart = Offset.zero;
  SystemMouseCursor? _hoverCursor;

  final List<_Op> _undoStack = [];
  final List<_Op> _redoStack = [];
  static const int _maxUndo = 200;

  Offset _toWorld(Offset local) => (local - _offset) / _scale;
  Offset get _center => _viewSize.center(Offset.zero);

  /// Whether a canvas-local pointer position is still over the canvas. The
  /// down-time hit test keeps delivering moves while the button is held,
  /// even after the cursor has left the canvas for another pane.
  bool _inCanvas(Offset local) =>
      _viewSize == Size.zero ||
      (local.dx >= 0 &&
          local.dy >= 0 &&
          local.dx <= _viewSize.width &&
          local.dy <= _viewSize.height);

  Offset _clampToView(Offset local) {
    if (_viewSize == Size.zero) return local;
    return Offset(
      local.dx.clamp(0.0, _viewSize.width).toDouble(),
      local.dy.clamp(0.0, _viewSize.height).toDouble(),
    );
  }

  bool get _shiftHeld =>
      HardwareKeyboard.instance.isLogicalKeyPressed(
          LogicalKeyboardKey.shiftLeft) ||
      HardwareKeyboard.instance.isLogicalKeyPressed(
          LogicalKeyboardKey.shiftRight);

  StrokeItem? _byId(String id) {
    for (final s in widget.note.strokes) {
      if (s.id == id) return s;
    }
    return null;
  }

  List<StrokeItem> get _selectedStrokes => [
        for (final s in widget.note.strokes)
          if (_selectedIds.contains(s.id)) s,
      ];

  StrokeItem? _topStrokeAt(Offset world) {
    for (final s in widget.note.strokes.reversed) {
      if (strokeHitTest(s, world, 4 / _scale)) return s;
    }
    return null;
  }

  void _setTool(CanvasTool t) {
    if (_labelField != null) _commitLabelEdit();
    setState(() {
      _tool = t;
      _drag = _SelectDrag.none;
      _marquee = null;
      if (t != CanvasTool.select) _selectedIds = {};
    });
  }

  // ---- pointer handling ---------------------------------------------------

  void _onPointerDown(PointerDownEvent e) {
    // The click that ends label editing does nothing else (like Excalidraw).
    if (_labelField != null) {
      _commitLabelEdit();
      return;
    }
    final local = e.localPosition;
    final tool = e.kind == PointerDeviceKind.invertedStylus
        ? CanvasTool.eraser
        : _tool;
    _lastLocal = local;
    _downLocal = local;

    if (tool == CanvasTool.pan || e.buttons == kMiddleMouseButton) {
      _panning = true;
      _panStart = local;
      _panOffsetStart = _offset;
      return;
    }

    final w = _toWorld(local);
    switch (tool) {
      case CanvasTool.select:
        _dragStartList = List<StrokeItem>.of(widget.note.strokes);
        _dragMoved = false;
        _resizeOriginal = null;
        _rotateOriginal = null;
        final single =
            _selectedStrokes.length == 1 ? _selectedStrokes.first : null;
        var handled = false;
        if (single != null) {
          final box = selectionBoxFor(single);
          final pl = box.toLocal(w);
          final tol = 7 / _scale;
          final rotLocal = Offset(
              box.localRect.center.dx, box.localRect.top - 22 / _scale);
          if ((pl - rotLocal).distance <= tol) {
            _drag = _SelectDrag.rotate;
            _rotateOriginal = single;
            handled = true;
          } else {
            final h = _handleAt(pl, box.localRect, tol);
            if (h != null) {
              _drag = _SelectDrag.resize;
              _resizeOriginal = single;
              _resizeHandle = h;
              handled = true;
            }
          }
        }
        if (!handled) {
          final hit = _topStrokeAt(w);
          if (hit != null && _shiftHeld && _selectedIds.contains(hit.id)) {
            // Shift-click removes from the selection; no drag starts.
            _selectedIds = {..._selectedIds}..remove(hit.id);
            _drag = _SelectDrag.none;
          } else if (hit != null) {
            if (_shiftHeld) {
              _selectedIds = {..._selectedIds, hit.id};
            } else if (!_selectedIds.contains(hit.id)) {
              _selectedIds = {hit.id};
            }
            _startMoveDrag(w);
          } else if (single != null &&
              selectionBoxFor(single).localRect
                  .contains(selectionBoxFor(single).toLocal(w))) {
            // Dragging anywhere inside the single-selection box moves it.
            _startMoveDrag(w);
          } else {
            // Empty space: rubber-band marquee (clears the selection).
            _drag = _SelectDrag.marquee;
            _marqueeStart = w;
            _marquee = Rect.fromPoints(w, w);
            _selectedIds = {};
          }
        }
      case CanvasTool.pan:
        break;
      case CanvasTool.text:
        break; // handled on pointer-up (a click, not a drag, opens the dialog)
      case CanvasTool.pen:
      case CanvasTool.marker:
        _active = StrokeItem(
          id: _newId(),
          type: tool == CanvasTool.pen ? StrokeType.pen : StrokeType.marker,
          points: [w],
          colorValue: _ink.toARGB32(),
          width: _width,
          seed: _newSeed(),
        );
      case CanvasTool.eraser:
        _erased.clear();
        _eraseAt(w);
      case CanvasTool.line:
      case CanvasTool.rectangle:
      case CanvasTool.ellipse:
      case CanvasTool.diamond:
      case CanvasTool.arrow:
        _active = StrokeItem(
          id: _newId(),
          type: switch (tool) {
            CanvasTool.line => StrokeType.line,
            CanvasTool.rectangle => StrokeType.rectangle,
            CanvasTool.ellipse => StrokeType.ellipse,
            CanvasTool.diamond => StrokeType.diamond,
            _ => StrokeType.arrow,
          },
          points: [w, w],
          colorValue: _ink.toARGB32(),
          width: _width,
          filled: _fillStyle >= 0 &&
              tool != CanvasTool.line &&
              tool != CanvasTool.arrow,
          fillStyle: math.max(_fillStyle, 0),
          dash: _dashStyle,
          seed: _newSeed(),
        );
    }
    setState(() {});
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_panning) {
      setState(
          () => _offset = _panOffsetStart + (e.localPosition - _panStart));
      return;
    }
    final local = e.localPosition;

    if (_tool == CanvasTool.select && _drag != _SelectDrag.none) {
      final w = _toWorld(local);
      switch (_drag) {
        case _SelectDrag.move:
          final delta = w - _dragStartWorld;
          if (delta.distance > 2 / _scale) _dragMoved = true;
          widget.controller.setStrokes(widget.note, [
            for (final s in _dragStartList)
              _dragOrigMap[s.id] != null
                  ? _translated(_dragOrigMap[s.id]!, delta)
                  : s,
          ]);
        case _SelectDrag.resize:
          _applyResize(w);
        case _SelectDrag.rotate:
          _applyRotate(w);
        case _SelectDrag.marquee:
          _marquee = Rect.fromPoints(_marqueeStart, w);
          _selectedIds = {
            for (final s in widget.note.strokes)
              if (strokeBounds(s).overlaps(_marquee!)) s.id,
          };
        case _SelectDrag.none:
          break;
      }
      setState(() {});
      return;
    }

    final t = _active?.type;
    if (_active != null && (t == StrokeType.pen || t == StrokeType.marker)) {
      // Don't ink outside the canvas while the pointer stays captured.
      if (!_inCanvas(local)) {
        _lastLocal = local;
        return;
      }
      if ((local - _lastLocal).distance < 1.5) return;
      _lastLocal = local;
      final w = _toWorld(local);
      setState(() => _active!.points.add(w));
      return;
    }
    if (_active != null && t != null) {
      // Shapes end at the canvas edge instead of spilling past it.
      final w = _toWorld(_clampToView(local));
      setState(() => _active!.points[1] = _snapShape(w));
      return;
    }
    if ((e.kind == PointerDeviceKind.invertedStylus ||
            _tool == CanvasTool.eraser) &&
        _inCanvas(local)) {
      _eraseAt(_toWorld(local));
    }
  }

  /// Constrain a shape's end point when Shift is held: 45° lines/arrows,
  /// squares and circles.
  Offset _snapShape(Offset w) {
    final active = _active!;
    final s0 = active.points[0];
    if (!_shiftHeld) return w;
    final type = active.type;
    if (type == StrokeType.line || type == StrokeType.arrow) {
      final dx = w.dx - s0.dx;
      final dy = w.dy - s0.dy;
      if (dx == 0 && dy == 0) return w;
      final len = math.sqrt(dx * dx + dy * dy);
      const step = math.pi / 4;
      final angle = (math.atan2(dy, dx) / step).roundToDouble() * step;
      return s0 +
          Offset(math.cos(angle) * len, math.sin(angle) * len);
    }
    if (type == StrokeType.rectangle ||
        type == StrokeType.ellipse ||
        type == StrokeType.diamond) {
      final dx = w.dx - s0.dx;
      final dy = w.dy - s0.dy;
      final m = math.max(dx.abs(), dy.abs());
      return s0 + Offset(dx.sign * m, dy.sign * m);
    }
    return w;
  }

  void _onPointerUp(PointerUpEvent e) {
    if (_panning) {
      _panning = false;
      return;
    }
    if (_tool == CanvasTool.select && _drag != _SelectDrag.none) {
      // Commit one undo step from the drag-start snapshot. This covers
      // moves, resizes and rotations (which were applied live) and also
      // fixes undo for plain moves.
      if (_drag != _SelectDrag.marquee && _dragMoved) {
        _pushOp(_dragStartList, List.of(widget.note.strokes));
      }
      _drag = _SelectDrag.none;
      _marquee = null;
      _resizeOriginal = null;
      _rotateOriginal = null;
      setState(() {});
      return;
    }
    if (_tool == CanvasTool.text &&
        (e.localPosition - _downLocal).distance < 5) {
      _startLabelEdit(at: _toWorld(e.localPosition));
      return;
    }
    final active = _active;
    _active = null;
    if (active != null) {
      final keep = switch (active.type) {
        StrokeType.pen || StrokeType.marker => true,
        _ => (active.points[0] - active.points[1]).distance > 6,
      };
      if (keep) _commitAdded(active);
    }
    if (_erased.isNotEmpty) {
      _commitRemoved(List.of(_erased));
      _erased.clear();
    }
    setState(() {});
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _panning = false;
    _active = null;
    if (_drag != _SelectDrag.none &&
        _drag != _SelectDrag.marquee &&
        _dragMoved) {
      // Keep what was applied live, but make it undoable.
      _pushOp(_dragStartList, List.of(widget.note.strokes));
    }
    _drag = _SelectDrag.none;
    _marquee = null;
    _resizeOriginal = null;
    _rotateOriginal = null;
    if (_erased.isNotEmpty) {
      _commitRemoved(List.of(_erased));
      _erased.clear();
    }
    setState(() {});
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    _zoomAt(e.localPosition, 1 + (-e.scrollDelta.dy / 600));
  }

  // ---- trackpad pan/zoom --------------------------------------------------

  void _onPanZoomStart(PointerPanZoomStartEvent e) {
    _pzBaseOffset = _offset;
    _pzLastScale = 1;
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent e) {
    if ((e.scale - 1).abs() > 0.01) {
      final factor = e.scale / _pzLastScale;
      _pzLastScale = e.scale;
      _zoomAt(e.position, factor, local: false);
      // Pinch also drags the content under the fingers.
      setState(() => _offset += e.delta);
    } else {
      setState(() => _offset = _pzBaseOffset + e.pan);
    }
  }

  // ---- view ---------------------------------------------------------------

  void _zoomAt(Offset anchor, double factor, {bool local = true}) {
    final next = (_scale * factor).clamp(0.25, 5.0).toDouble();
    final anchorLocal = local ? anchor : anchor - _windowOrigin;
    final world = (anchorLocal - _offset) / _scale;
    setState(() {
      _scale = next;
      _offset = anchorLocal - world * _scale;
    });
  }

  Offset get _windowOrigin {
    final box = context.findRenderObject() as RenderBox?;
    return box?.localToGlobal(Offset.zero) ?? Offset.zero;
  }

  // ---- editing ------------------------------------------------------------

  /// Copy of a stroke, optionally with a new id, translation and angle.
  /// Carries every style field so transforms never reset looks.
  StrokeItem _clone(StrokeItem s, {String? id, Offset? delta, double? angle}) =>
      StrokeItem(
        id: id ?? s.id,
        type: s.type,
        points: [
          for (final p in s.points) delta == null ? p : p + delta,
        ],
        colorValue: s.colorValue,
        width: s.width,
        filled: s.filled,
        fillStyle: s.fillStyle,
        dash: s.dash,
        seed: s.seed,
        angle: angle ?? s.angle,
        text: s.text,
      );

  StrokeItem _translated(StrokeItem s, Offset delta) =>
      _clone(s, delta: delta);

  void _startMoveDrag(Offset w) {
    _drag = _SelectDrag.move;
    _dragStartWorld = w;
    _dragOrigMap = {
      for (final s in _dragStartList)
        if (_selectedIds.contains(s.id)) s.id: s,
    };
  }

  /// Resize handle indices: 0..3 corners (TL, TR, BR, BL), 4..7 edges
  /// (top, right, bottom, left). Returns the handle under local point
  /// [pl] within [tol], or null.
  int? _handleAt(Offset pl, Rect r, double tol) {
    int? best;
    var bestD = tol;
    final candidates = <int, Offset>{
      0: r.topLeft,
      1: r.topRight,
      2: r.bottomRight,
      3: r.bottomLeft,
      4: r.topCenter,
      5: r.centerRight,
      6: r.bottomCenter,
      7: r.centerLeft,
    };
    for (final e in candidates.entries) {
      final d = (pl - e.value).distance;
      if (d <= bestD) {
        bestD = d;
        best = e.key;
      }
    }
    return best;
  }

  /// Resizes the stroke being transformed: maps its local frame from the
  /// original rect to a new rect following the dragged handle. Handles are
  /// hit-tested in the stroke's rotated frame, so resizing a rotated
  /// element scales along its own axes (like Excalidraw). Shift keeps the
  /// aspect ratio on corner handles.
  void _applyResize(Offset w) {
    final orig = _resizeOriginal;
    if (orig == null) return;
    final box = selectionBoxFor(orig);
    final r = box.localRect;
    final pl = box.toLocal(w);
    final h = _resizeHandle;
    Rect to;
    if (h <= 3) {
      final anchors = [r.bottomRight, r.bottomLeft, r.topLeft, r.topRight];
      final anchor = anchors[h];
      to = Rect.fromPoints(anchor, pl);
      if (_shiftHeld && r.width > 0 && r.height > 0) {
        final sx = to.width / r.width;
        final sy = to.height / r.height;
        final s = math.max(sx, sy);
        final dx = pl.dx >= anchor.dx ? 1.0 : -1.0;
        final dy = pl.dy >= anchor.dy ? 1.0 : -1.0;
        to = Rect.fromLTWH(
          dx > 0 ? anchor.dx : anchor.dx - r.width * s,
          dy > 0 ? anchor.dy : anchor.dy - r.height * s,
          r.width * s,
          r.height * s,
        );
      }
    } else {
      to = switch (h) {
        4 => Rect.fromLTRB(r.left, pl.dy, r.right, r.bottom),
        5 => Rect.fromLTRB(r.left, r.top, pl.dx, r.bottom),
        6 => Rect.fromLTRB(r.left, r.top, r.right, pl.dy),
        _ => Rect.fromLTRB(pl.dx, r.top, r.right, r.bottom),
      };
    }
    if (to.width.abs() < 1e-3 || to.height.abs() < 1e-3) return;
    _dragMoved = true;
    _replaceStroke(orig, _scaledStroke(orig, r, to));
  }

  /// Rotates the stroke being transformed; Shift snaps to 15° steps.
  void _applyRotate(Offset w) {
    final orig = _rotateOriginal;
    if (orig == null) return;
    final c = strokeLocalBounds(orig).center;
    var angle = math.atan2(w.dy - c.dy, w.dx - c.dx) + math.pi / 2;
    if (_shiftHeld) {
      final step = math.pi / 12;
      angle = (angle / step).roundToDouble() * step;
    }
    while (angle > math.pi) {
      angle -= 2 * math.pi;
    }
    while (angle <= -math.pi) {
      angle += 2 * math.pi;
    }
    if ((angle - orig.angle).abs() < 0.001) return;
    _dragMoved = true;
    _replaceStroke(orig, _clone(orig, angle: angle));
  }

  /// Maps a stroke's geometry from local frame [from] to [to] (both in the
  /// stroke's unrotated frame). Negative extents flip the geometry. Stroke
  /// width scales with the average axis; text scales its font size instead.
  StrokeItem _scaledStroke(StrokeItem s, Rect from, Rect to) {
    final sx = to.width / math.max(from.width, 1e-6);
    final sy = to.height / math.max(from.height, 1e-6);
    final isText = s.type == StrokeType.text;
    final newWidth = isText
        ? (s.width * sy.abs()).clamp(8.0, 128.0).toDouble()
        : (s.width * (sx.abs() + sy.abs()) / 2).clamp(0.5, 64.0).toDouble();
    return StrokeItem(
      id: s.id,
      type: s.type,
      points: [
        for (final p in s.points)
          Offset(
            to.left + (p.dx - from.left) * sx,
            to.top + (p.dy - from.top) * sy,
          ),
      ],
      colorValue: s.colorValue,
      width: newWidth,
      filled: s.filled,
      fillStyle: s.fillStyle,
      dash: s.dash,
      seed: s.seed,
      angle: s.angle,
      text: s.text,
    );
  }

  /// Resize/rotate cursors when hovering over transform handles.
  void _onHover(PointerEvent e) {
    SystemMouseCursor? c;
    if (_tool == CanvasTool.select &&
        _drag == _SelectDrag.none &&
        _labelField == null &&
        _selectedStrokes.length == 1) {
      final single = _selectedStrokes.first;
      final box = selectionBoxFor(single);
      final pl = box.toLocal(_toWorld(e.localPosition));
      final tol = 7 / _scale;
      final rotLocal = Offset(
          box.localRect.center.dx, box.localRect.top - 22 / _scale);
      if ((pl - rotLocal).distance <= tol) {
        c = SystemMouseCursors.grab;
      } else {
        c = switch (_handleAt(pl, box.localRect, tol)) {
          0 || 2 => SystemMouseCursors.resizeUpLeftDownRight,
          1 || 3 => SystemMouseCursors.resizeUpRightDownLeft,
          4 || 6 => SystemMouseCursors.resizeUpDown,
          5 || 7 => SystemMouseCursors.resizeLeftRight,
          _ => null,
        };
      }
    }
    if (c != _hoverCursor) setState(() => _hoverCursor = c);
  }

  /// Restyles every selected stroke in one undo step (like Excalidraw's
  /// selection style panel).
  void _applyToSelection({
    int? colorValue,
    double? width,
    int? dash,
    int? fillStyle,
    double? fontSize,
  }) {
    if (_selectedIds.isEmpty) return;
    final before = List<StrokeItem>.of(widget.note.strokes);
    var changed = false;
    final after = <StrokeItem>[];
    for (final s in before) {
      if (!_selectedIds.contains(s.id)) {
        after.add(s);
        continue;
      }
      final updated = _restyled(
        s,
        colorValue: colorValue,
        width: width,
        dash: dash,
        fillStyle: fillStyle,
        fontSize: fontSize,
      );
      if (!identical(updated, s)) changed = true;
      after.add(updated);
    }
    if (!changed) return;
    _pushOp(before, after);
    setState(() {});
  }

  StrokeItem _restyled(
    StrokeItem s, {
    int? colorValue,
    double? width,
    int? dash,
    int? fillStyle,
    double? fontSize,
  }) {
    final isShape = s.type != StrokeType.pen &&
        s.type != StrokeType.marker &&
        s.type != StrokeType.text;
    final closedShape = s.type == StrokeType.rectangle ||
        s.type == StrokeType.ellipse ||
        s.type == StrokeType.diamond;
    // For text labels [width]/[fontSize] is the font size.
    final newWidth = s.type == StrokeType.text
        ? (fontSize ?? s.width)
        : (width ?? s.width);
    final updated = StrokeItem(
      id: s.id,
      type: s.type,
      points: List.of(s.points),
      width: newWidth,
      colorValue: colorValue ?? s.colorValue,
      filled: fillStyle == null || !closedShape ? s.filled : fillStyle >= 0,
      fillStyle: fillStyle == null || !closedShape
          ? s.fillStyle
          : math.max(fillStyle, 0),
      dash: dash == null || !isShape ? s.dash : dash,
      seed: s.seed,
      angle: s.angle,
      text: s.text,
    );
    if (updated.colorValue == s.colorValue &&
        updated.width == s.width &&
        updated.filled == s.filled &&
        updated.fillStyle == s.fillStyle &&
        updated.dash == s.dash) {
      return s;
    }
    return updated;
  }

  void _replaceStroke(StrokeItem before, StrokeItem after) {
    final list = [
      for (final s in widget.note.strokes) s.id == before.id ? after : s,
    ];
    widget.controller.setStrokes(widget.note, list);
  }

  void _eraseAt(Offset world) {
    final radius = 10 / _scale;
    final hits = widget.note.strokes
        .where((s) => strokeHitTest(s, world, radius))
        .toList();
    if (hits.isEmpty) return;
    final list = List<StrokeItem>.of(widget.note.strokes)
      ..removeWhere((s) => hits.any((h) => h.id == s.id));
    _erased.addAll(hits);
    widget.controller.setStrokes(widget.note, list);
    setState(() {});
  }

  void _pushOp(List<StrokeItem> before, List<StrokeItem> after) {
    _undoStack.add(_Op(before, after));
    if (_undoStack.length > _maxUndo) _undoStack.removeAt(0);
    _redoStack.clear();
    widget.controller.setStrokes(widget.note, after);
  }

  void _commitAdded(StrokeItem stroke) {
    final before = List<StrokeItem>.of(widget.note.strokes);
    _pushOp(before, [...before, stroke]);
  }

  void _commitRemoved(List<StrokeItem> removed) {
    final before = List<StrokeItem>.of(widget.note.strokes);
    final after = [
      for (final s in before)
        if (!removed.any((r) => r.id == s.id)) s,
    ];
    if (after.length == before.length) return;
    _pushOp(before, after);
  }

  void _commitReplace(StrokeItem before, StrokeItem after) {
    final current = List<StrokeItem>.of(widget.note.strokes);
    if (current.any((s) => identical(s, after))) {
      // [after] was applied live during a drag; reconstruct the pre-change
      // state so undo restores the original stroke.
      final beforeList = [
        for (final s in current) identical(s, after) ? before : s,
      ];
      _pushOp(beforeList, current);
      return;
    }
    _pushOp(current, [
      for (final s in current) s.id == before.id ? after : s,
    ]);
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final op = _undoStack.removeLast();
    _redoStack.add(op);
    widget.controller.setStrokes(widget.note, op.before);
    setState(() {});
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final op = _redoStack.removeLast();
    _undoStack.add(op);
    widget.controller.setStrokes(widget.note, op.after);
    setState(() {});
  }

  void _clear() {
    if (widget.note.strokes.isEmpty) return;
    _selectedIds = {};
    _commitRemoved(List.of(widget.note.strokes));
    setState(() {});
  }

  void _resetView() => setState(() {
        _offset = Offset.zero;
        _scale = 1;
      });

  /// Fits all strokes into view.
  void _zoomToFit() {
    final strokes = widget.note.strokes;
    if (strokes.isEmpty || _viewSize == Size.zero) return;
    var bounds = strokeBounds(strokes.first);
    for (final s in strokes.skip(1)) {
      bounds = bounds.expandToInclude(strokeBounds(s));
    }
    const pad = 48.0;
    final availW = math.max(_viewSize.width - pad * 2, 60);
    final availH = math.max(_viewSize.height - pad * 2, 60);
    final fit = math.min(
      availW / math.max(bounds.width, 1),
      availH / math.max(bounds.height, 1),
    );
    final next = fit.clamp(0.25, 5.0).toDouble();
    setState(() {
      _scale = next;
      _offset = _viewSize.center(Offset.zero) - bounds.center * next;
    });
  }

  void _deselect() {
    if (_selectedIds.isEmpty && _marquee == null) return;
    setState(() {
      _selectedIds = {};
      _marquee = null;
    });
  }

  void _deleteSelected() {
    final victims = _selectedStrokes;
    if (victims.isEmpty) return;
    _selectedIds = {};
    _commitRemoved(victims);
    setState(() {});
  }

  void _duplicateSelected() {
    final sel = _selectedStrokes;
    if (sel.isEmpty) return;
    final before = List<StrokeItem>.of(widget.note.strokes);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final copies = <StrokeItem>[];
    for (var i = 0; i < sel.length; i++) {
      copies.add(_clone(
        _translated(sel[i], const Offset(20, 20)),
        id: 's${stamp}_$i',
      ));
    }
    _pushOp(before, [...before, ...copies]);
    _selectedIds = {for (final c in copies) c.id};
    setState(() {});
  }

  void _reorderSelected(bool front) {
    final ids = _selectedIds;
    if (ids.isEmpty) return;
    final before = List<StrokeItem>.of(widget.note.strokes);
    final moving = [for (final s in before) if (ids.contains(s.id)) s];
    final rest = [for (final s in before) if (!ids.contains(s.id)) s];
    _pushOp(before, front ? [...rest, ...moving] : [...moving, ...rest]);
    setState(() {});
  }

  void _nudge(int dx, int dy) {
    if (_selectedIds.isEmpty) return;
    final step = _shiftHeld ? 10.0 : 1.0;
    final delta = Offset(dx * step, dy * step);
    final before = List<StrokeItem>.of(widget.note.strokes);
    _pushOp(before, [
      for (final s in before)
        _selectedIds.contains(s.id) ? _translated(s, delta) : s,
    ]);
    setState(() {});
  }

  // ---- in-place text labels -----------------------------------------------

  /// Opens a borderless text field on the canvas at [at] (new label) or over
  /// [existing] (editing). Committing writes a [StrokeType.text] stroke.
  void _startLabelEdit({StrokeItem? existing, Offset? at}) {
    if (_labelField != null) _commitLabelEdit();
    setState(() {
      _editingId = existing?.id;
      _labelWorld = existing?.points.first ?? at ?? Offset.zero;
      _labelSize = existing?.width ?? _labelSize;
      _labelFocus = FocusNode();
      _labelField = TextEditingController(text: existing?.text ?? '')
        ..addListener(_onLabelEdited);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _labelFocus?.requestFocus();
    });
  }

  void _onLabelEdited() {
    if (mounted) setState(() {}); // re-measure the field's width
  }

  /// Writes the edited label back (empty text discards, or deletes when
  /// editing an existing label) and closes the in-place field.
  void _commitLabelEdit() {
    final field = _labelField;
    if (field == null) return;
    final text = field.text;
    final editingId = _editingId;
    final size = _labelSize;
    field.removeListener(_onLabelEdited);
    field.dispose();
    _labelFocus?.dispose();
    _labelField = null;
    _labelFocus = null;
    _editingId = null;

    final existing = editingId == null ? null : _byId(editingId);
    if (text.trim().isEmpty) {
      if (existing != null) {
        _selectedIds = {};
        _commitRemoved([existing]);
      }
      setState(() {});
      return;
    }
    if (existing != null) {
      final updated = StrokeItem(
        id: existing.id,
        type: StrokeType.text,
        points: existing.points,
        colorValue: existing.colorValue,
        width: size,
        text: text,
      );
      _commitReplace(existing, updated);
      _selectedIds = {updated.id};
    } else {
      final stroke = StrokeItem(
        id: _newId(),
        type: StrokeType.text,
        points: [_labelWorld],
        colorValue: _ink.toARGB32(),
        width: size,
        text: text,
      );
      _commitAdded(stroke);
      _selectedIds = {stroke.id};
    }
    setState(() {});
  }

  /// Runs a toolbar action, committing any in-place label edit first.
  void _withCommit(VoidCallback action) {
    if (_labelField != null) _commitLabelEdit();
    action();
  }

  /// Screen-space width of the in-place field so it hugs the typed text.
  double get _labelFieldWidth {
    final field = _labelField;
    if (field == null) return 40;
    final tp = TextPainter(
      text: TextSpan(
        text: field.text.isEmpty ? ' ' : field.text,
        style: TextStyle(
          fontSize: _labelSize * _scale,
          height: 1.25,
          fontFamily: 'Segoe Print',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return math.max(tp.width, 24 * _scale) + 10;
  }

  /// Sets the font size used for new labels and restyles the selected
  /// text labels, if any.
  void _changeLabelSize(double size) {
    setState(() => _labelSize = size);
    _applyToSelection(fontSize: size);
  }

  void _onSecondaryTapUp(TapUpDetails d) {
    final hit = _topStrokeAt(_toWorld(d.localPosition));
    if (hit == null) {
      _deselect();
      return;
    }
    if (!_selectedIds.contains(hit.id)) {
      _selectedIds = {hit.id};
    }
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        d.globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        if (hit.type == StrokeType.text)
          const PopupMenuItem(
            value: 'edit',
            height: 40,
            child: Text('Edit label'),
          ),
        const PopupMenuItem(
          value: 'duplicate',
          height: 40,
          child: Text('Duplicate'),
        ),
        const PopupMenuItem(
          value: 'front',
          height: 40,
          child: Text('Bring to front'),
        ),
        const PopupMenuItem(
          value: 'back',
          height: 40,
          child: Text('Send to back'),
        ),
        PopupMenuItem(
          value: 'delete',
          height: 40,
          child: Text('Delete', style: TextStyle(color: Colors.red[400])),
        ),
      ],
    ).then((value) {
      switch (value) {
        case 'edit':
          _startLabelEdit(existing: hit);
        case 'duplicate':
          _duplicateSelected();
        case 'front':
          _reorderSelected(true);
        case 'back':
          _reorderSelected(false);
        case 'delete':
          _deleteSelected();
      }
    });
  }

  String _newId() =>
      's${DateTime.now().microsecondsSinceEpoch}${_undoStack.length}';

  /// Seed for the sketchy rendering; stable once the stroke is created.
  int _newSeed() => math.Random().nextInt(1 << 30);

  // ---- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pal = paletteFor(widget.note.colorIndex, dark);
    final note = widget.note;
    final selectedStrokes = _selectedStrokes;
    final scheme = Theme.of(context).colorScheme;

    final editing = _labelField != null;
    return CallbackShortcuts(
      // While a text label is being edited, typing keys (Ctrl+Z, Delete…)
      // must reach the text field, not the canvas shortcuts.
      bindings: editing
          ? const <ShortcutActivator, VoidCallback>{}
          : {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true,
            shift: true): _redo,
        const SingleActivator(LogicalKeyboardKey.keyD, control: true):
            _duplicateSelected,
        const SingleActivator(LogicalKeyboardKey.delete): _deleteSelected,
        const SingleActivator(LogicalKeyboardKey.backspace): _deleteSelected,
        const SingleActivator(LogicalKeyboardKey.escape): _deselect,
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _nudge(0, -1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _nudge(0, 1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _nudge(-1, 0),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _nudge(1, 0),
        },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _viewSize = constraints.biggest;
            return ClipRect(
              child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onSecondaryTapUp: _onSecondaryTapUp,
                    onDoubleTapDown: (d) {
                      final hit = _topStrokeAt(_toWorld(d.localPosition));
                      if (hit != null && hit.type == StrokeType.text) {
                        _startLabelEdit(existing: hit);
                      } else if (hit == null) {
                        // Excalidraw-style: double-click empty space to add text.
                        _startLabelEdit(at: _toWorld(d.localPosition));
                      }
                    },
                    onDoubleTap: () {},
                    child: Listener(
                      onPointerDown: _onPointerDown,
                      onPointerMove: _onPointerMove,
                      onPointerUp: _onPointerUp,
                      onPointerCancel: _onPointerCancel,
                      onPointerSignal: _onPointerSignal,
                      onPointerPanZoomStart: _onPanZoomStart,
                      onPointerPanZoomUpdate: _onPanZoomUpdate,
                      child: MouseRegion(
                        cursor: _hoverCursor ?? _cursorFor(_tool),
                        onHover: _onHover,
                        // Clip so strokes never paint over neighboring panes.
                        child: ClipRect(
                          child: CustomPaint(
                            painter: DiagramPainter(
                              strokes: note.strokes,
                              active: _active,
                              activePointCount: _active?.points.length ?? 0,
                              activeEnd: _active != null &&
                                      _active!.points.length == 2
                                  ? _active!.points.last
                                  : null,
                              offset: _offset,
                              scale: _scale,
                              background: pal.body,
                              gridColor:
                                  scheme.onSurface.withValues(alpha: 0.15),
                              showGrid: _showGrid,
                              selected: selectedStrokes,
                              showHandles: selectedStrokes.length == 1 &&
                                  _drag != _SelectDrag.marquee,
                              marquee: _marquee,
                              selectionColor: scheme.primary,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (note.strokes.isEmpty && _active == null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.gesture,
                                size: 44,
                                color: noteTextColor(dark)
                                    .withValues(alpha: 0.25)),
                            const SizedBox(height: 8),
                            Text(
                              'Draw here — pick a tool on the left',
                              style: TextStyle(
                                fontSize: 13,
                                color: noteTextColor(dark)
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 12,
                  top: 12,
                  child: DiagramToolPalette(
                    tool: _tool,
                    onToolSelected: _setTool,
                    dark: dark,
                  ),
                ),
                if (_labelField != null)
                  Positioned(
                    left: _offset.dx + _labelWorld.dx * _scale,
                    top: _offset.dy + _labelWorld.dy * _scale,
                    child: Material(
                      type: MaterialType.transparency,
                      child: Focus(
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent &&
                              event.logicalKey == LogicalKeyboardKey.escape) {
                            _commitLabelEdit();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: SizedBox(
                          width: _labelFieldWidth,
                          child: TextField(
                            controller: _labelField,
                            focusNode: _labelFocus,
                            maxLines: null,
                            minLines: 1,
                            style: TextStyle(
                              fontSize: _labelSize * _scale,
                              height: 1.25,
                              color: _ink,
                              fontFamily: 'Segoe Print',
                            ),
                            cursorColor: _ink,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              hintText: 'Type…',
                              hintStyle: TextStyle(
                                fontSize: _labelSize * _scale,
                                color: _ink.withValues(alpha: 0.4),
                                fontFamily: 'Segoe Print',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: DiagramToolbar(
                      zoom: _scale,
                      canUndo: _undoStack.isNotEmpty,
                      onUndo: () => _withCommit(_undo),
                      canRedo: _redoStack.isNotEmpty,
                      onRedo: () => _withCommit(_redo),
                      hasSelection: selectedStrokes.isNotEmpty,
                      onDuplicateSelection: () =>
                          _withCommit(_duplicateSelected),
                      onDeleteSelection: () => _withCommit(_deleteSelected),
                      ink: _ink,
                      onInkSelected: (c) {
                        setState(() => _ink = c);
                        _applyToSelection(colorValue: c.toARGB32());
                      },
                      strokeWidth: _width,
                      onStrokeWidthSelected: (w) {
                        setState(() => _width = w);
                        _applyToSelection(width: w);
                      },
                      fillStyle: _fillStyle,
                      onFillStyleSelected: (f) {
                        setState(() => _fillStyle = f);
                        _applyToSelection(fillStyle: f);
                      },
                      dashStyle: _dashStyle,
                      onDashStyleSelected: (d) {
                        setState(() => _dashStyle = d);
                        _applyToSelection(dash: d);
                      },
                      labelSize:
                          selectedStrokes.length == 1 &&
                                  selectedStrokes.first.type ==
                                      StrokeType.text
                              ? selectedStrokes.first.width
                              : _labelSize,
                      onLabelSizeSelected: _changeLabelSize,
                      showGrid: _showGrid,
                      onToggleGrid: () =>
                          setState(() => _showGrid = !_showGrid),
                      onZoomIn: () => _zoomAt(_center, 1.25),
                      onZoomFit: _zoomToFit,
                      canFit: note.strokes.isNotEmpty,
                      onZoomOut: () => _zoomAt(_center, 0.8),
                      onResetView: _resetView,
                      canClear: note.strokes.isNotEmpty,
                      onClear: () => _withCommit(_clear),
                      dark: dark,
                    ),
                  ),
                ),
              ],
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _labelField?.removeListener(_onLabelEdited);
    _labelField?.dispose();
    _labelFocus?.dispose();
    super.dispose();
  }

  SystemMouseCursor _cursorFor(CanvasTool t) => switch (t) {
        CanvasTool.pan => SystemMouseCursors.move,
        CanvasTool.text => SystemMouseCursors.text,
        CanvasTool.select || CanvasTool.eraser => SystemMouseCursors.basic,
        _ => SystemMouseCursors.precise,
      };
}
