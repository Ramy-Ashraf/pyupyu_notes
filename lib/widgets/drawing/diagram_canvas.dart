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
  bool _filled = false;
  bool _showGrid = true;

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

  String? _selectedId;
  StrokeItem? _moving;
  StrokeItem? _movedCurrent;
  Offset _moveStart = Offset.zero;

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

  StrokeItem? get _selected =>
      _selectedId == null ? null : _byId(_selectedId!);

  StrokeItem? _topStrokeAt(Offset world) {
    for (final s in widget.note.strokes.reversed) {
      if (strokeHitTest(s, world, 4 / _scale)) return s;
    }
    return null;
  }

  void _setTool(CanvasTool t) {
    setState(() {
      _tool = t;
      _moving = null;
      _movedCurrent = null;
      if (t != CanvasTool.select) _selectedId = null;
    });
  }

  // ---- pointer handling ---------------------------------------------------

  void _onPointerDown(PointerDownEvent e) {
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
        final hit = _topStrokeAt(w);
        if (hit == null) {
          _selectedId = null;
        } else {
          _selectedId = hit.id;
          _moving = hit;
          _movedCurrent = null;
          _moveStart = w;
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
        );
      case CanvasTool.eraser:
        _erased.clear();
        _eraseAt(w);
      case CanvasTool.line:
      case CanvasTool.rectangle:
      case CanvasTool.ellipse:
      case CanvasTool.arrow:
        _active = StrokeItem(
          id: _newId(),
          type: switch (tool) {
            CanvasTool.line => StrokeType.line,
            CanvasTool.rectangle => StrokeType.rectangle,
            CanvasTool.ellipse => StrokeType.ellipse,
            _ => StrokeType.arrow,
          },
          points: [w, w],
          colorValue: _ink.toARGB32(),
          width: _width,
          filled: _filled,
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

    if (_moving != null && _tool == CanvasTool.select) {
      final w = _toWorld(local);
      final delta = w - _moveStart;
      final moved = _translated(_moving!, delta);
      _movedCurrent = moved;
      _replaceStroke(_moving!, moved);
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
    if (type == StrokeType.rectangle || type == StrokeType.ellipse) {
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
    if (_moving != null) {
      final before = _moving!;
      final after = _movedCurrent;
      _moving = null;
      _movedCurrent = null;
      if (after != null) _commitReplace(before, after);
      setState(() {});
      return;
    }
    if (_tool == CanvasTool.text &&
        (e.localPosition - _downLocal).distance < 5) {
      _openTextLabel(at: _toWorld(e.localPosition));
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
    _moving = null;
    _movedCurrent = null;
    _active = null;
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

  StrokeItem _translated(StrokeItem s, Offset delta) => StrokeItem(
        id: s.id,
        type: s.type,
        points: [for (final p in s.points) p + delta],
        colorValue: s.colorValue,
        width: s.width,
        filled: s.filled,
        text: s.text,
      );

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
    final list = List<StrokeItem>.of(widget.note.strokes);
    _pushOp(list, [
      for (final s in list) s.id == before.id ? after : s,
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
    _selectedId = null;
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
    if (_selectedId == null) return;
    setState(() => _selectedId = null);
  }

  void _deleteSelected() {
    final s = _selected;
    if (s == null) return;
    _selectedId = null;
    _commitRemoved([s]);
    setState(() {});
  }

  void _duplicateSelected() {
    final s = _selected;
    if (s == null) return;
    final moved = _translated(s, const Offset(20, 20));
    final copy = StrokeItem(
      id: _newId(),
      type: moved.type,
      points: moved.points,
      colorValue: moved.colorValue,
      width: moved.width,
      filled: moved.filled,
      text: moved.text,
    );
    _commitAdded(copy);
    _selectedId = copy.id;
    setState(() {});
  }

  void _reorderSelected(bool front) {
    final s = _selected;
    if (s == null) return;
    final list = List<StrokeItem>.of(widget.note.strokes)
      ..removeWhere((x) => x.id == s.id);
    front ? list.add(s) : list.insert(0, s);
    final before = List<StrokeItem>.of(widget.note.strokes);
    _pushOp(before, list);
    setState(() {});
  }

  void _nudge(int dx, int dy) {
    final s = _selected;
    if (s == null) return;
    final step = _shiftHeld ? 10.0 : 1.0;
    _commitReplace(s, _translated(s, Offset(dx * step, dy * step)));
    setState(() {});
  }

  Future<void> _openTextLabel({StrokeItem? existing, Offset? at}) async {
    final result = await showLabelDialog(
      context,
      initialText: existing?.text ?? '',
      initialSize: existing?.width ?? 18,
    );
    if (result == null) return;
    if (existing != null) {
      if (result.text.trim().isEmpty) {
        _selectedId = null;
        _commitRemoved([existing]);
      } else {
        final updated = StrokeItem(
          id: existing.id,
          type: StrokeType.text,
          points: existing.points,
          colorValue: existing.colorValue,
          width: result.size,
          text: result.text,
        );
        _commitReplace(existing, updated);
        _selectedId = updated.id;
      }
    } else {
      if (result.text.trim().isEmpty || at == null) return;
      final stroke = StrokeItem(
        id: _newId(),
        type: StrokeType.text,
        points: [at],
        colorValue: _ink.toARGB32(),
        width: result.size,
        text: result.text,
      );
      _commitAdded(stroke);
      _selectedId = stroke.id;
    }
    setState(() {});
  }

  void _onSecondaryTapUp(TapUpDetails d) {
    final hit = _topStrokeAt(_toWorld(d.localPosition));
    if (hit == null) {
      _deselect();
      return;
    }
    setState(() => _selectedId = hit.id);
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
          _openTextLabel(existing: hit);
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

  // ---- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pal = paletteFor(widget.note.colorIndex, dark);
    final note = widget.note;
    final selected = _selected;
    final scheme = Theme.of(context).colorScheme;

    return CallbackShortcuts(
      bindings: {
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
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onSecondaryTapUp: _onSecondaryTapUp,
                    onDoubleTapDown: (d) {
                      final hit = _topStrokeAt(_toWorld(d.localPosition));
                      if (hit != null && hit.type == StrokeType.text) {
                        _openTextLabel(existing: hit);
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
                        cursor: _cursorFor(_tool),
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
                              selected: selected,
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
                              'Draw here — pick a tool below',
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
                  top: 10,
                  right: 14,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh.withValues(
                            alpha: 0.85),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${(_scale * 100).round()}%',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
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
                      tool: _tool,
                      onToolSelected: _setTool,
                      ink: _ink,
                      onInkSelected: (c) => setState(() => _ink = c),
                      strokeWidth: _width,
                      onStrokeWidthSelected: (w) =>
                          setState(() => _width = w),
                      filled: _filled,
                      onFilledChanged: (f) => setState(() => _filled = f),
                      canUndo: _undoStack.isNotEmpty,
                      onUndo: _undo,
                      canRedo: _redoStack.isNotEmpty,
                      onRedo: _redo,
                      showGrid: _showGrid,
                      onToggleGrid: () =>
                          setState(() => _showGrid = !_showGrid),
                      hasSelection: selected != null,
                      onDuplicateSelection: _duplicateSelected,
                      onDeleteSelection: _deleteSelected,
                      onZoomIn: () => _zoomAt(_center, 1.25),
                      onZoomFit: _zoomToFit,
                      canFit: note.strokes.isNotEmpty,
                      onZoomOut: () => _zoomAt(_center, 0.8),
                      onResetView: _resetView,
                      canClear: note.strokes.isNotEmpty,
                      onClear: _clear,
                      dark: dark,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  SystemMouseCursor _cursorFor(CanvasTool t) => switch (t) {
        CanvasTool.pan => SystemMouseCursors.move,
        CanvasTool.text => SystemMouseCursors.text,
        CanvasTool.select || CanvasTool.eraser => SystemMouseCursors.basic,
        _ => SystemMouseCursors.precise,
      };
}
