import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/format_text_controller.dart';
import '../controllers/notes_controller.dart';
import '../models/format_span.dart';
import '../models/note.dart';
import '../theme/note_palette.dart';
import '../utils/export.dart';
import '../utils/format.dart';
import '../utils/markdown_table.dart';
import 'drawing/diagram_canvas.dart';

enum EditorView { text, canvas }

/// The right pane: colored note surface with a top bar (view toggle, palette,
/// pin, exports, delete), a text editor with rich formatting + lists, or the
/// diagram canvas.
class EditorPane extends StatefulWidget {
  const EditorPane({super.key, required this.controller});

  final NotesController controller;

  @override
  State<EditorPane> createState() => _EditorPaneState();
}

class _EditorPaneState extends State<EditorPane> {
  // Remembered across note switches so a drawing session isn't interrupted
  // by clicking into another note and back.
  static EditorView _lastView = EditorView.text;
  late EditorView _view = _lastView;

  @override
  Widget build(BuildContext context) {
    final note = widget.controller.selected;
    if (note == null) return _EmptyState(controller: widget.controller);

    final dark = Theme.of(context).brightness == Brightness.dark;
    final pal = paletteFor(note.colorIndex, dark);
    final onBar = pal.bar.computeLuminance() > 0.5
        ? Colors.black.withValues(alpha: 0.75)
        : Colors.white.withValues(alpha: 0.85);

    return Container(
      color: pal.body,
      child: Column(
        children: [
          Container(
            color: pal.bar,
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            child: Row(
              children: [
                SegmentedButton<EditorView>(
                  segments: const [
                    ButtonSegment(
                      value: EditorView.text,
                      icon: Icon(Icons.notes, size: 18),
                      label: Text('Text'),
                    ),
                    ButtonSegment(
                      value: EditorView.canvas,
                      icon: Icon(Icons.draw, size: 18),
                      label: Text('Draw'),
                    ),
                  ],
                  selected: {_view},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onSelectionChanged: (s) =>
                      setState(() => _lastView = _view = s.first),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    formatEdited(note.updatedAt),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: onBar),
                  ),
                ),
                _moreMenu(note, onBar),
                _colorMenu(note, onBar),
                IconButton(
                  tooltip: note.pinned ? 'Unpin' : 'Pin',
                  icon: Icon(
                    note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    size: 20,
                    color: onBar,
                  ),
                  onPressed: () => widget.controller.togglePin(note),
                ),
                IconButton(
                  tooltip: 'Delete note',
                  icon: Icon(Icons.delete_outline, size: 20, color: onBar),
                  onPressed: () => _delete(note),
                ),
              ],
            ),
          ),
          Expanded(
            child: _view == EditorView.text
                ? _TextBody(
                    note: note,
                    controller: widget.controller,
                    textColor: noteTextColor(dark),
                  )
                : DiagramCanvas(
                    key: ValueKey('canvas-${note.id}'),
                    note: note,
                    controller: widget.controller,
                  ),
          ),
        ],
      ),
    );
  }

  void _delete(Note note) {
    widget.controller.deleteNote(note);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Note deleted'),
        behavior: SnackBarBehavior.floating,
        width: 320,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: widget.controller.undoDelete,
        ),
      ),
    );
  }

  Widget _moreMenu(Note note, Color onBar) {
    return PopupMenuButton<String>(
      tooltip: 'More actions',
      icon: Icon(Icons.more_horiz, size: 22, color: onBar),
      onSelected: (v) async {
        final String? path;
        switch (v) {
          case 'export-txt':
            path = await exportNoteText(note);
          case 'export-png':
            path = await exportDiagramPng(
              note,
              background: paletteFor(
                note.colorIndex,
                Theme.of(context).brightness == Brightness.dark,
              ).body,
            );
          default:
            return;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              path == null ? 'Nothing to export' : 'Saved to $path',
            ),
            behavior: SnackBarBehavior.floating,
            width: 420,
          ),
        );
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'export-txt',
          height: 40,
          child: Text('Export note as .txt'),
        ),
        PopupMenuItem(
          value: 'export-png',
          height: 40,
          child: Text('Export diagram as .png'),
        ),
      ],
    );
  }

  Widget _colorMenu(Note note, Color onBar) {
    return PopupMenuButton<int>(
      tooltip: 'Note color',
      icon: Icon(Icons.palette_outlined, size: 20, color: onBar),
      onSelected: (i) => widget.controller.setColor(note, i),
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: 4 * 36 + 3 * 10,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < notePalettes.length; i++)
                  _swatch(i, note.colorIndex),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _swatch(int i, int current) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pal = paletteFor(i, dark);
    return InkWell(
      onTap: () => Navigator.of(context).pop(i),
      customBorder: const CircleBorder(),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: pal.body,
          shape: BoxShape.circle,
          border: Border.all(color: pal.bar, width: 3),
        ),
        child: i == current ? Icon(Icons.check, size: 16, color: pal.bar) : null,
      ),
    );
  }
}

/// Text editing surface: a formatting bar (bold/italic/underline/strike,
/// checklists, bullets, clear) above the multiline body field. Toolbar
/// actions keep the caret and selection in the field.
class _TextBody extends StatefulWidget {
  const _TextBody({
    required this.note,
    required this.controller,
    required this.textColor,
  });

  final Note note;
  final NotesController controller;
  final Color textColor;

  @override
  State<_TextBody> createState() => _TextBodyState();
}

class _TextBodyState extends State<_TextBody> {
  late final FocusNode _focusNode =
      FocusNode(onKeyEvent: _handleTableKeys);

  late final FormatTextController _field = FormatTextController(
    text: widget.note.body,
    formats: widget.note.formats,
  )..onEdited = _persist;

  @override
  void initState() {
    super.initState();
    _field.addListener(_onFieldChanged);
    // A brand-new note opens ready for typing.
    if (widget.note.body.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _TextBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Adopt external changes (e.g. a future "insert date" action).
    if (widget.note.body != oldWidget.note.body &&
        widget.note.body != _field.text) {
      _field.replaceAll(widget.note.body, widget.note.formats);
    }
  }

  @override
  void dispose() {
    _field.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  void _persist() {
    widget.controller.setContent(
      widget.note,
      _field.text,
      _field.formats,
    );
  }

  /// Runs a toolbar action and hands focus straight back to the editor so
  /// typing continues without clicking into the field again.
  void _act(VoidCallback action) {
    action();
    _focusNode.requestFocus();
  }

  /// Intercepts Tab / Shift+Tab (cell navigation) and Enter (row below)
  /// while the caret is inside a Markdown table — exactly like Notepad.
  /// Anything else (or any key outside a table) falls through to the field.
  KeyEventResult _handleTableKeys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isTab = key == LogicalKeyboardKey.tab;
    final isEnter = key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    if (!isTab && !isEnter) return KeyEventResult.ignored;
    if (!_field.isInTable) return KeyEventResult.ignored;
    if (isTab) {
      final backwards = HardwareKeyboard.instance.isShiftPressed;
      if (_field.handleTableTab(backwards: backwards)) {
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    return _field.handleTableEnter()
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final words = _field.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
    return Column(
      children: [
        _formatBar(context, words),
        Expanded(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.keyB,
                    control: true): () =>
                    _act(() => _field.toggleFormat(FormatFlags.bold)),
                const SingleActivator(LogicalKeyboardKey.keyI,
                    control: true): () =>
                    _act(() => _field.toggleFormat(FormatFlags.italic)),
                const SingleActivator(LogicalKeyboardKey.keyU,
                    control: true): () =>
                    _act(() => _field.toggleFormat(FormatFlags.underline)),
              },
              child: TextField(
                controller: _field,
                focusNode: _focusNode,
                maxLines: null,
                expands: true,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                contextMenuBuilder: _tableContextMenu,
                style: TextStyle(
                  color: widget.textColor,
                  fontSize: 15,
                  height: 1.5,
                ),
                cursorColor: widget.textColor.withValues(alpha: 0.8),
                decoration: InputDecoration(
                  hintText: 'Take a note…',
                  hintStyle: TextStyle(
                    color: widget.textColor.withValues(alpha: 0.35),
                    fontSize: 15,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sep() => Container(
        width: 1,
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: widget.textColor.withValues(alpha: 0.15),
      );

  Widget _formatButton(int flag, IconData icon, String tip) {
    final active = _field.isActive(flag);
    return IconButton(
      tooltip: tip,
      isSelected: active,
      icon: Icon(icon, size: 20),
      onPressed: () => _act(() => _field.toggleFormat(flag)),
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? widget.textColor
              : widget.textColor.withValues(alpha: 0.55),
        ),
      ),
    );
  }

  Widget _barButton(IconData icon, String tip, VoidCallback action) {
    return IconButton(
      tooltip: tip,
      icon: Icon(icon, size: 20),
      onPressed: () => _act(action),
      color: widget.textColor.withValues(alpha: 0.55),
    );
  }

  /// H1/H2 toggle rendered as a text chip (no matching icon exists).
  Widget _textButton(String label, int flag, String tip) {
    final active = _field.isActive(flag);
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _act(() => _field.toggleFormat(flag)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color:
                active ? widget.textColor.withValues(alpha: 0.14) : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              height: 1.0,
              color: active
                  ? widget.textColor
                  : widget.textColor.withValues(alpha: 0.55),
            ),
          ),
        ),
      ),
    );
  }

  /// Inserts the current date and time at the caret (replaces a selection).
  void _insertDateTime() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${now.day}/${now.month}/${now.year} ${two(now.hour)}:${two(now.minute)}';
    final value = _field.value;
    final sel = value.selection;
    final from = sel.isValid
        ? math.min(sel.baseOffset, sel.extentOffset)
        : value.text.length;
    final to = sel.isValid
        ? math.max(sel.baseOffset, sel.extentOffset)
        : value.text.length;
    _field.value = value.copyWith(
      text: value.text.replaceRange(from, to, stamp),
      selection: TextSelection.collapsed(offset: from + stamp.length),
      composing: TextRange.empty,
    );
  }

  Widget _formatBar(BuildContext context, int words) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: widget.textColor.withValues(alpha: 0.12),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _formatButton(FormatFlags.bold, Icons.format_bold,
              'Bold (Ctrl+B)'),
          _formatButton(FormatFlags.italic, Icons.format_italic,
              'Italic (Ctrl+I)'),
          _formatButton(FormatFlags.underline, Icons.format_underline,
              'Underline (Ctrl+U)'),
          _formatButton(FormatFlags.strike, Icons.strikethrough_s,
              'Strikethrough'),
          _textButton('H1', FormatFlags.h1, 'Heading 1'),
          _textButton('H2', FormatFlags.h2, 'Heading 2'),
          _sep(),
          _barButton(Icons.checklist, 'Checklist',
              _field.toggleChecklist),
          _barButton(Icons.format_list_bulleted, 'Bulleted list',
              _field.toggleBulletList),
          _barButton(Icons.format_list_numbered, 'Numbered list',
              _field.toggleNumberedList),
          _tableButton(),
          _barButton(Icons.today_outlined, 'Insert date & time',
              _insertDateTime),
          _barButton(Icons.format_clear, 'Clear formatting',
              _field.clearFormats),
          const Spacer(),
          Text(
            '$words words · ${_field.text.length} chars',
            style: TextStyle(
              fontSize: 11,
              color: widget.textColor.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }

  // ---- tables (Notepad-style) -------------------------------------------

  /// The Table button mirrors Windows Notepad: outside a table it inserts
  /// one (grid picker + custom dialog); inside a table it opens the Table
  /// editing menu (rows, columns, select, delete, format, preview).
  Widget _tableButton() {
    if (!_field.isInTable) {
      return _barButton(
        Icons.table_chart_outlined,
        'Insert table',
        _showInsertTableDialog,
      );
    }
    return PopupMenuButton<_TableAction>(
      tooltip: 'Table',
      icon: Icon(
        Icons.table_chart_outlined,
        size: 20,
        color: widget.textColor.withValues(alpha: 0.55),
      ),
      onSelected: (a) {
        if (a == _TableAction.preview) {
          _showTablePreview();
        } else {
          _act(() => _applyTableAction(a));
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: _TableAction.rowAbove,
          height: 40,
          child: Text('Insert row above'),
        ),
        PopupMenuItem(
          value: _TableAction.rowBelow,
          height: 40,
          child: Text('Insert row below'),
        ),
        PopupMenuItem(
          value: _TableAction.columnLeft,
          height: 40,
          child: Text('Insert column left'),
        ),
        PopupMenuItem(
          value: _TableAction.columnRight,
          height: 40,
          child: Text('Insert column right'),
        ),
        PopupMenuDivider(height: 8),
        PopupMenuItem(
          value: _TableAction.selectRow,
          height: 40,
          child: Text('Select row'),
        ),
        PopupMenuItem(
          value: _TableAction.selectTable,
          height: 40,
          child: Text('Select table'),
        ),
        PopupMenuDivider(height: 8),
        PopupMenuItem(
          value: _TableAction.deleteRow,
          height: 40,
          child: Text('Delete row'),
        ),
        PopupMenuItem(
          value: _TableAction.deleteColumn,
          height: 40,
          child: Text('Delete column'),
        ),
        PopupMenuItem(
          value: _TableAction.deleteTable,
          height: 40,
          child: Text('Delete table'),
        ),
        PopupMenuDivider(height: 8),
        PopupMenuItem(
          value: _TableAction.format,
          height: 40,
          child: Text('Fit columns to content'),
        ),
        PopupMenuItem(
          value: _TableAction.preview,
          height: 40,
          child: Text('Preview table'),
        ),
      ],
    );
  }

  void _applyTableAction(_TableAction action) {
    switch (action) {
      case _TableAction.rowAbove:
        _field.insertTableRowAbove();
      case _TableAction.rowBelow:
        _field.insertTableRowBelow();
      case _TableAction.columnLeft:
        _field.insertTableColumnLeft();
      case _TableAction.columnRight:
        _field.insertTableColumnRight();
      case _TableAction.selectRow:
        _field.selectTableRow();
      case _TableAction.selectTable:
        _field.selectTable();
      case _TableAction.deleteRow:
        _field.deleteTableRow();
      case _TableAction.deleteColumn:
        _field.deleteTableColumn();
      case _TableAction.deleteTable:
        _field.deleteTable();
      case _TableAction.format:
        _field.formatTable();
      case _TableAction.preview:
        // Handled by the caller (needs a BuildContext for the dialog).
        break;
    }
  }

  /// Right-click menu additions mirroring Notepad: `Insert table` outside a
  /// table, row/column/delete actions inside one.
  Widget _tableContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final items = [...editableTextState.contextMenuButtonItems];
    void add(String label, VoidCallback fn) {
      items.add(
        ContextMenuButtonItem(
          label: label,
          onPressed: () {
            editableTextState.hideToolbar();
            fn();
          },
        ),
      );
    }

    if (_field.isInTable) {
      add('Insert row above', () => _act(_field.insertTableRowAbove));
      add('Insert row below', () => _act(_field.insertTableRowBelow));
      add('Insert column left', () => _act(_field.insertTableColumnLeft));
      add('Insert column right', () => _act(_field.insertTableColumnRight));
      add('Delete row', () => _act(_field.deleteTableRow));
      add('Delete column', () => _act(_field.deleteTableColumn));
      add('Delete table', () => _act(_field.deleteTable));
    } else {
      add('Insert table…', _showInsertTableDialog);
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: items,
    );
  }

  Future<void> _showInsertTableDialog() async {
    final size = await showDialog<_TableSize>(
      context: context,
      builder: (_) => const _InsertTableDialog(),
    );
    if (size == null || !mounted) return;
    _act(() => _field.insertTable(size.columns, size.rows));
  }

  void _showTablePreview() {
    final table = _field.currentTable();
    if (table == null) return;
    showDialog<void>(
      context: context,
      builder: (_) => _TablePreviewDialog(
        table: table,
        textColor: widget.textColor,
      ),
    );
  }
}

/// Table-menu actions (mirrors the Notepad Table submenu).
enum _TableAction {
  rowAbove,
  rowBelow,
  columnLeft,
  columnRight,
  selectRow,
  selectTable,
  deleteRow,
  deleteColumn,
  deleteTable,
  format,
  preview,
}

/// Grid-picker result: [columns] text columns, [rows] body rows (the header
/// row is always added automatically, like Notepad).
class _TableSize {
  const _TableSize({required this.columns, required this.rows});

  final int columns;
  final int rows;
}

/// Notepad-style insert dialog: hover a grid for a quick size, or type exact
/// columns/rows and press Insert.
class _InsertTableDialog extends StatefulWidget {
  const _InsertTableDialog();

  @override
  State<_InsertTableDialog> createState() => _InsertTableDialogState();
}

class _InsertTableDialogState extends State<_InsertTableDialog> {
  static const _maxCols = 10;
  static const _maxRows = 8;

  int _hoverCols = 3;
  int _hoverRows = 3;
  late final _colsController = TextEditingController(text: '3');
  late final _rowsController = TextEditingController(text: '3');

  @override
  void dispose() {
    _colsController.dispose();
    _rowsController.dispose();
    super.dispose();
  }

  void _submit(int columns, int rows) {
    final c = columns < 1
        ? 1
        : (columns > kMaxTableColumns ? kMaxTableColumns : columns);
    final r = rows < 1 ? 1 : (rows > kMaxTableBodyRows ? kMaxTableBodyRows : rows);
    Navigator.of(context).pop(_TableSize(columns: c, rows: r));
  }

  @override
  Widget build(BuildContext context) {
    const cell = 24.0;
    const gap = 3.0;
    return AlertDialog(
      title: const Text('Insert table'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      content: SizedBox(
        width: _maxCols * (cell + gap),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _maxCols,
                mainAxisSpacing: gap,
                crossAxisSpacing: gap,
              ),
              itemCount: _maxCols * _maxRows,
              itemBuilder: (_, i) {
                final c = i % _maxCols + 1;
                final r = i ~/ _maxCols + 1;
                final on = c <= _hoverCols && r <= _hoverRows;
                final scheme = Theme.of(context).colorScheme;
                return MouseRegion(
                  onEnter: (_) => setState(() {
                    _hoverCols = c;
                    _hoverRows = r;
                    _colsController.text = '$c';
                    _rowsController.text = '$r';
                  }),
                  child: GestureDetector(
                    onTap: () => _submit(c, r),
                    child: Container(
                      width: cell,
                      height: cell,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: on
                            ? scheme.primary.withValues(alpha: 0.75)
                            : scheme.surfaceContainerHighest
                                .withValues(alpha: 0.6),
                        border: Border.all(
                          color: scheme.outline.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              '$_hoverCols × $_hoverRows table',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _colsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Columns',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _rowsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Rows',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => _submit(
            int.tryParse(_colsController.text.trim()) ?? _hoverCols,
            int.tryParse(_rowsController.text.trim()) ?? _hoverRows,
          ),
          child: const Text('Insert'),
        ),
      ],
    );
  }
}

/// Read-only rendering of the current table — the formatted counterpart to
/// the Markdown source, like Notepad's formatted table view.
class _TablePreviewDialog extends StatelessWidget {
  const _TablePreviewDialog({required this.table, required this.textColor});

  final MarkdownTable table;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final border = TableBorder.all(
      color: textColor.withValues(alpha: 0.3),
      width: 1,
    );
    Widget cell(String value, {required bool header}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Text(
            value.isEmpty ? ' ' : value,
            style: TextStyle(
              color: textColor,
              fontWeight: header ? FontWeight.w700 : null,
            ),
          ),
        );
    return AlertDialog(
      title: const Text('Table preview'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      content: SizedBox(
        width: 440,
        height: 360,
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              border: border,
              defaultColumnWidth: const IntrinsicColumnWidth(),
              children: [
                for (var r = 0; r < table.rows.length; r++)
                  TableRow(
                    decoration: r == 0
                        ? BoxDecoration(
                            color: textColor.withValues(alpha: 0.08),
                          )
                        : null,
                    children: [
                      for (final value in table.rows[r])
                        cell(value, header: r == 0),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.controller});

  final NotesController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sticky_note_2_outlined,
              size: 56, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            'No note selected',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: controller.createNote,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New note'),
          ),
        ],
      ),
    );
  }
}
