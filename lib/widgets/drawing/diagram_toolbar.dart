import 'package:flutter/material.dart';

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

/// The floating toolbar under the diagram canvas. Pure presentation: every
/// interaction is reported through callbacks.
class DiagramToolbar extends StatelessWidget {
  const DiagramToolbar({
    super.key,
    required this.tool,
    required this.onToolSelected,
    required this.ink,
    required this.onInkSelected,
    required this.strokeWidth,
    required this.onStrokeWidthSelected,
    required this.filled,
    required this.onFilledChanged,
    required this.canUndo,
    required this.onUndo,
    required this.canRedo,
    required this.onRedo,
    required this.showGrid,
    required this.onToggleGrid,
    required this.hasSelection,
    required this.onDuplicateSelection,
    required this.onDeleteSelection,
    required this.onZoomIn,
    required this.onZoomFit,
    required this.canFit,
    required this.onZoomOut,
    required this.onResetView,
    required this.canClear,
    required this.onClear,
    required this.dark,
  });

  final CanvasTool tool;
  final ValueChanged<CanvasTool> onToolSelected;
  final Color ink;
  final ValueChanged<Color> onInkSelected;
  final double strokeWidth;
  final ValueChanged<double> onStrokeWidthSelected;
  final bool filled;
  final ValueChanged<bool> onFilledChanged;
  final bool canUndo;
  final VoidCallback onUndo;
  final bool canRedo;
  final VoidCallback onRedo;
  final bool showGrid;
  final VoidCallback onToggleGrid;
  final bool hasSelection;
  final VoidCallback onDuplicateSelection;
  final VoidCallback onDeleteSelection;
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

    Widget toolBtn(CanvasTool t, IconData icon, String tip) => IconButton(
          tooltip: tip,
          isSelected: tool == t,
          icon: Icon(icon),
          onPressed: () => onToolSelected(t),
          style: selectStyle,
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
              toolBtn(CanvasTool.select, Icons.highlight_alt, 'Select & move'),
              toolBtn(CanvasTool.pan, Icons.pan_tool_outlined, 'Pan'),
              _divider(fg),
              toolBtn(CanvasTool.pen, Icons.edit_outlined, 'Pen'),
              toolBtn(CanvasTool.marker, Icons.highlight, 'Highlighter'),
              toolBtn(CanvasTool.text, Icons.text_fields,
                  'Text label (double-click one to edit)'),
              toolBtn(CanvasTool.eraser, Icons.cleaning_services, 'Eraser'),
              _divider(fg),
              toolBtn(CanvasTool.line, Icons.horizontal_rule,
                  'Line (hold Shift to snap to 45°)'),
              toolBtn(CanvasTool.rectangle, Icons.crop_square,
                  'Rectangle (hold Shift for square)'),
              toolBtn(CanvasTool.ellipse, Icons.circle_outlined,
                  'Ellipse (hold Shift for circle)'),
              toolBtn(CanvasTool.arrow, Icons.north_east,
                  'Arrow (hold Shift to snap to 45°)'),
              _divider(fg),
              IconButton(
                tooltip: 'Filled shapes',
                isSelected: filled,
                icon: const Icon(Icons.format_color_fill),
                onPressed: () => onFilledChanged(!filled),
                style: selectStyle,
              ),
              PopupMenuButton<Color>(
                tooltip: 'Ink color',
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
              _divider(fg),
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
              IconButton(
                tooltip: 'Zoom to fit',
                icon: Icon(Icons.fit_screen, color: fg),
                onPressed: canFit ? onZoomFit : null,
              ),
              IconButton(
                tooltip: 'Reset view',
                icon: Icon(Icons.center_focus_strong, color: fg),
                onPressed: onResetView,
              ),
              IconButton(
                tooltip: 'Zoom in',
                icon: Icon(Icons.zoom_in, color: fg),
                onPressed: onZoomIn,
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

class LabelDialogInput {
  const LabelDialogInput(this.text, this.size);
  final String text;
  final double size;
}

/// Dialog for creating or editing a canvas text label.
Future<LabelDialogInput?> showLabelDialog(
  BuildContext context, {
  required String initialText,
  required double initialSize,
}) {
  return showDialog<LabelDialogInput>(
    context: context,
    builder: (_) => _LabelDialog(
      initialText: initialText,
      initialSize: initialSize,
    ),
  );
}

class _LabelDialog extends StatefulWidget {
  const _LabelDialog({
    required this.initialText,
    required this.initialSize,
  });

  final String initialText;
  final double initialSize;

  @override
  State<_LabelDialog> createState() => _LabelDialogState();
}

class _LabelDialogState extends State<_LabelDialog> {
  late final TextEditingController _field =
      TextEditingController(text: widget.initialText);
  late double _size = widget.initialSize;

  void _save() => Navigator.of(context).pop(LabelDialogInput(_field.text, _size));

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Text label'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _field,
            autofocus: true,
            maxLines: 3,
            minLines: 1,
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(
              hintText: 'Type a label…',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final s in canvasLabelSizes)
                ChoiceChip(
                  label: Text('${s.toInt()}'),
                  selected: _size == s,
                  onSelected: (_) => setState(() => _size = s),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
