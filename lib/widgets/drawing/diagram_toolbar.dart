import 'package:flutter/material.dart';

import '../../models/stroke_item.dart';

/// Tools available on the diagram canvas.
enum CanvasTool {
  select,
  pan,
  pen,
  marker,
  text,
  eraser,
  line,
  rectangle,
  ellipse,
  diamond,
  arrow,
}

const List<Color> canvasInkColors = [
  Color(0xFF1F1F1F),
  Color(0xFF6B7280),
  Color(0xFFF8FAFC),
  Color(0xFFE11D48),
  Color(0xFFF59E0B),
  Color(0xFF10B981),
  Color(0xFF3B82F6),
  Color(0xFF8B5CF6),
  Color(0xFF78350F),
  Color(0xFF0EA5E9),
];

const List<double> canvasStrokeWidths = [2, 4, 6, 10, 16];

const List<double> canvasLabelSizes = [14, 18, 24, 32];

/// Excalidraw-style vertical tool palette: a floating island on the canvas'
/// top-left edge with the active tool highlighted.
class DiagramToolPalette extends StatelessWidget {
  const DiagramToolPalette({
    super.key,
    required this.tool,
    required this.onToolSelected,
    required this.dark,
  });

  final CanvasTool tool;
  final ValueChanged<CanvasTool> onToolSelected;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final bg = dark ? const Color(0xFF2C2C2C) : Colors.white;
    final fg = dark ? const Color(0xFFE6E6E6) : const Color(0xFF333333);
    final accent = Theme.of(context).colorScheme.primary;
    final selectStyle = ButtonStyle(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? accent
            : Colors.transparent,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? Colors.white : fg,
      ),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );

    Widget toolBtn(CanvasTool t, IconData icon, String tip) => IconButton(
          tooltip: tip,
          isSelected: tool == t,
          icon: Icon(icon),
          onPressed: () => onToolSelected(t),
          style: selectStyle,
        );

    Widget divider() => Container(
          height: 1,
          width: 26,
          margin: const EdgeInsets.symmetric(vertical: 3),
          color: fg.withValues(alpha: 0.25),
        );

    return Material(
      elevation: 4,
      shadowColor: Colors.black45,
      borderRadius: BorderRadius.circular(14),
      color: bg,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 540),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                toolBtn(CanvasTool.select, Icons.highlight_alt,
                    'Select & move'),
                toolBtn(CanvasTool.pan, Icons.pan_tool_outlined,
                    'Pan (or middle-mouse drag)'),
                divider(),
                toolBtn(CanvasTool.pen, Icons.edit_outlined, 'Pen'),
                toolBtn(CanvasTool.marker, Icons.highlight, 'Highlighter'),
                toolBtn(CanvasTool.text, Icons.text_fields,
                    'Text — or double-click the canvas'),
                toolBtn(CanvasTool.eraser, Icons.cleaning_services, 'Eraser'),
                divider(),
                toolBtn(CanvasTool.rectangle, Icons.crop_square,
                    'Rectangle (hold Shift for square)'),
                toolBtn(CanvasTool.diamond, Icons.diamond_outlined,
                    'Diamond (hold Shift for a regular one)'),
                toolBtn(CanvasTool.ellipse, Icons.circle_outlined,
                    'Ellipse (hold Shift for circle)'),
                toolBtn(CanvasTool.arrow, Icons.north_east,
                    'Arrow (hold Shift to snap to 45°)'),
                toolBtn(CanvasTool.line, Icons.horizontal_rule,
                    'Line (hold Shift to snap to 45°)'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The floating properties bar under the diagram canvas: undo/redo, actions
/// on the selection, style pickers, and view controls. Pure presentation:
/// every interaction is reported through callbacks.
class DiagramToolbar extends StatelessWidget {
  const DiagramToolbar({
    super.key,
    required this.zoom,
    required this.canUndo,
    required this.onUndo,
    required this.canRedo,
    required this.onRedo,
    required this.hasSelection,
    required this.onDuplicateSelection,
    required this.onDeleteSelection,
    required this.ink,
    required this.onInkSelected,
    required this.strokeWidth,
    required this.onStrokeWidthSelected,
    required this.fillStyle,
    required this.onFillStyleSelected,
    required this.dashStyle,
    required this.onDashStyleSelected,
    required this.labelSize,
    required this.onLabelSizeSelected,
    required this.showGrid,
    required this.onToggleGrid,
    required this.onZoomIn,
    required this.onZoomFit,
    required this.canFit,
    required this.onZoomOut,
    required this.onResetView,
    required this.canClear,
    required this.onClear,
    required this.dark,
  });

  final double zoom;
  final bool canUndo;
  final VoidCallback onUndo;
  final bool canRedo;
  final VoidCallback onRedo;
  final bool hasSelection;
  final VoidCallback onDuplicateSelection;
  final VoidCallback onDeleteSelection;
  final Color ink;
  final ValueChanged<Color> onInkSelected;
  final double strokeWidth;
  final ValueChanged<double> onStrokeWidthSelected;
  final int fillStyle;
  final ValueChanged<int> onFillStyleSelected;
  final int dashStyle;
  final ValueChanged<int> onDashStyleSelected;
  final double labelSize;
  final ValueChanged<double> onLabelSizeSelected;
  final bool showGrid;
  final VoidCallback onToggleGrid;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomFit;
  final bool canFit;
  final VoidCallback onZoomOut;
  final VoidCallback onResetView;
  final bool canClear;
  final VoidCallback onClear;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final bg = dark ? const Color(0xFF2C2C2C) : Colors.white;
    final fg = dark ? const Color(0xFFE6E6E6) : const Color(0xFF333333);
    final accent = Theme.of(context).colorScheme.primary;
    final selectStyle = ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? accent : fg,
      ),
    );

    return Material(
      elevation: 4,
      shadowColor: Colors.black45,
      borderRadius: BorderRadius.circular(14),
      color: bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Undo (Ctrl+Z)',
                icon: Icon(Icons.undo, color: fg),
                onPressed: canUndo ? onUndo : null,
              ),
              IconButton(
                tooltip: 'Redo (Ctrl+Y)',
                icon: Icon(Icons.redo, color: fg),
                onPressed: canRedo ? onRedo : null,
              ),
              _divider(fg),
              IconButton(
                tooltip: 'Duplicate selected (Ctrl+D)',
                icon: Icon(Icons.copy, color: fg),
                onPressed: hasSelection ? onDuplicateSelection : null,
              ),
              IconButton(
                tooltip: 'Delete selected (Delete)',
                icon: Icon(Icons.delete_outline, color: fg),
                onPressed: hasSelection ? onDeleteSelection : null,
              ),
              _divider(fg),
              PopupMenuButton<Color>(
                tooltip: 'Stroke color',
                onSelected: onInkSelected,
                itemBuilder: (popupContext) => [
                  PopupMenuItem<Color>(
                    enabled: false,
                    padding: EdgeInsets.zero,
                    child: _swatchGrid(popupContext, fg),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: ink,
                      shape: BoxShape.circle,
                      border: Border.all(color: fg.withValues(alpha: 0.4)),
                    ),
                  ),
                ),
              ),
              PopupMenuButton<double>(
                tooltip: 'Stroke width',
                onSelected: onStrokeWidthSelected,
                itemBuilder: (_) => [
                  for (final w in canvasStrokeWidths)
                    PopupMenuItem<double>(
                      value: w,
                      height: 40,
                      child: Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: w.clamp(4, 18).toDouble(),
                            color: strokeWidth == w ? accent : fg,
                          ),
                          const SizedBox(width: 10),
                          Text('$w'),
                        ],
                      ),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(Icons.line_weight, size: 22, color: fg),
                ),
              ),
              PopupMenuButton<int>(
                tooltip: 'Fill style',
                initialValue: fillStyle,
                onSelected: onFillStyleSelected,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: -1,
                    height: 40,
                    child: Row(children: [
                      Icon(Icons.format_color_reset, size: 18),
                      SizedBox(width: 10),
                      Text('None'),
                    ]),
                  ),
                  PopupMenuItem(
                    value: FillStyles.hachure,
                    height: 40,
                    child: Row(children: [
                      Icon(Icons.texture, size: 18),
                      SizedBox(width: 10),
                      Text('Hachure'),
                    ]),
                  ),
                  PopupMenuItem(
                    value: FillStyles.solid,
                    height: 40,
                    child: Row(children: [
                      Icon(Icons.format_color_fill, size: 18),
                      SizedBox(width: 10),
                      Text('Solid'),
                    ]),
                  ),
                  PopupMenuItem(
                    value: FillStyles.crossHatch,
                    height: 40,
                    child: Row(children: [
                      Icon(Icons.grid_4x4, size: 18),
                      SizedBox(width: 10),
                      Text('Cross-hatch'),
                    ]),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(_fillIcon(fillStyle), size: 22, color: fg),
                ),
              ),
              PopupMenuButton<int>(
                tooltip: 'Stroke style',
                initialValue: dashStyle,
                onSelected: onDashStyleSelected,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: DashStyles.solid,
                    height: 40,
                    child: Row(children: [
                      Icon(Icons.remove, size: 18),
                      SizedBox(width: 10),
                      Text('Solid'),
                    ]),
                  ),
                  PopupMenuItem(
                    value: DashStyles.dashed,
                    height: 40,
                    child: Row(children: [
                      Icon(Icons.more_horiz, size: 18),
                      SizedBox(width: 10),
                      Text('Dashed'),
                    ]),
                  ),
                  PopupMenuItem(
                    value: DashStyles.dotted,
                    height: 40,
                    child: Row(children: [
                      Icon(Icons.scatter_plot, size: 18),
                      SizedBox(width: 10),
                      Text('Dotted'),
                    ]),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(_dashIcon(dashStyle), size: 22, color: fg),
                ),
              ),
              PopupMenuButton<double>(
                tooltip: 'Text size',
                initialValue: labelSize,
                onSelected: onLabelSizeSelected,
                itemBuilder: (_) => [
                  for (final s in canvasLabelSizes)
                    PopupMenuItem<double>(
                      value: s,
                      height: 40,
                      child: Row(
                        children: [
                          Icon(Icons.text_fields,
                              size: 16, color: labelSize == s ? accent : fg),
                          const SizedBox(width: 10),
                          Text('${s.toInt()}'),
                        ],
                      ),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.format_size, size: 20, color: fg),
                      const SizedBox(width: 4),
                      Text(
                        '${labelSize.toInt()}',
                        style: TextStyle(fontSize: 11, color: fg),
                      ),
                    ],
                  ),
                ),
              ),
              _divider(fg),
              IconButton(
                tooltip: showGrid ? 'Hide grid' : 'Show grid',
                isSelected: showGrid,
                icon: const Icon(Icons.grid_on),
                onPressed: onToggleGrid,
                style: selectStyle,
              ),
              IconButton(
                tooltip: 'Zoom out',
                icon: Icon(Icons.zoom_out, color: fg),
                onPressed: onZoomOut,
              ),
              Tooltip(
                message: 'Zoom (click to reset view)',
                child: InkWell(
                  onTap: onResetView,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    child: Text(
                      '${(zoom * 100).round()}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Zoom in',
                icon: Icon(Icons.zoom_in, color: fg),
                onPressed: onZoomIn,
              ),
              IconButton(
                tooltip: 'Zoom to fit',
                icon: Icon(Icons.fit_screen, color: fg),
                onPressed: canFit ? onZoomFit : null,
              ),
              IconButton(
                tooltip: 'Clear canvas',
                icon: Icon(Icons.delete_sweep, color: fg),
                onPressed: canClear ? onClear : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider(Color fg) => Container(
        width: 1,
        height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: fg.withValues(alpha: 0.35),
      );

  static IconData _fillIcon(int f) => switch (f) {
        -1 => Icons.format_color_reset,
        FillStyles.solid => Icons.format_color_fill,
        FillStyles.crossHatch => Icons.grid_4x4,
        _ => Icons.texture,
      };

  static IconData _dashIcon(int d) => switch (d) {
        DashStyles.dashed => Icons.more_horiz,
        DashStyles.dotted => Icons.scatter_plot,
        _ => Icons.remove,
      };

  Widget _swatchGrid(BuildContext popupContext, Color fg) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: 5 * 30 + 4 * 8,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in canvasInkColors)
              InkWell(
                onTap: () {
                  onInkSelected(c);
                  Navigator.of(popupContext).pop();
                },
                customBorder: const CircleBorder(),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(color: fg.withValues(alpha: 0.3)),
                  ),
                  child: ink == c
                      ? Icon(
                          Icons.check,
                          size: 15,
                          color: c.computeLuminance() > 0.5
                              ? Colors.black87
                              : Colors.white,
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
