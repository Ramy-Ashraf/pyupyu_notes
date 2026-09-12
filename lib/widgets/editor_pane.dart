import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/notes_controller.dart';
import '../models/format_span.dart' show FormatFlags;
import '../models/note.dart';
import '../theme/note_palette.dart';
import '../utils/export.dart';
import '../utils/format.dart';
import '../utils/markdown_table.dart';
import 'body_editor.dart' show BodyEditor, BodyEditorState, TableOp;
import 'drawing/diagram_canvas.dart';

enum EditorView { text, canvas }

/// The right pane: colored note surface with a top bar (view toggle, palette,
/// pin, exports, delete), the block-based text editor (rich text + Excel
/// tables), or the diagram canvas.
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
/// lists, tables) above the block-based body editor. Toolbar actions keep
/// the caret where it was.
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
  final GlobalKey<BodyEditorState> _editorKey = GlobalKey<BodyEditorState>();

  BodyEditorState? get _editor => _editorKey.currentState;

  /// Runs a toolbar action and hands focus straight back to the editor so
  /// typing continues without clicking into the field again.
  void _act(VoidCallback action) {
    action();
    _editor?.refocus();
  }

  @override
  Widget build(BuildContext context) {
    final body = _editor?.text ?? widget.note.body;
    final words = body
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
    return Column(
      children: [
        _formatBar(context, words, body.length),
        Expanded(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.keyB,
                        control: true): () =>
                    _editor?.toggleFormat(FormatFlags.bold),
                const SingleActivator(LogicalKeyboardKey.keyI,
                        control: true): () =>
                    _editor?.toggleFormat(FormatFlags.italic),
                const SingleActivator(LogicalKeyboardKey.keyU,
                        control: true): () =>
                    _editor?.toggleFormat(FormatFlags.underline),
              },
              child: BodyEditor(
                key: _editorKey,
                noteId: widget.note.id,
                initialBody: widget.note.body,
                initialFormats: widget.note.formats,
                textColor: widget.textColor,
                onChanged: (text, formats) => widget.controller.setContent(
                  widget.note,
                  text,
                  formats,
                ),
                onFocusChanged: () => setState(() {}),
                onRequestInsertTable: _showInsertTableDialog,
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
    final active = _editor?.isActive(flag) ?? false;
    return IconButton(
      tooltip: tip,
      isSelected: active,
      icon: Icon(icon, size: 20),
      onPressed: () => _act(() => _editor?.toggleFormat(flag)),
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
    final active = _editor?.isActive(flag) ?? false;
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _act(() => _editor?.toggleFormat(flag)),
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
    _editor?.insertText(stamp);
  }

  Widget _formatBar(BuildContext context, int words, int chars) {
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
              () => _editor?.toggleChecklist()),
          _barButton(Icons.format_list_bulleted, 'Bulleted list',
              () => _editor?.toggleBulletList()),
          _barButton(Icons.format_list_numbered, 'Numbered list',
              () => _editor?.toggleNumberedList()),
          _tableButton(),
          _barButton(Icons.today_outlined, 'Insert date & time',
              _insertDateTime),
          _barButton(Icons.format_clear, 'Clear formatting',
              () => _editor?.clearFormats()),
          const Spacer(),
          Text(
            '$words words · $chars chars',
            style: TextStyle(
              fontSize: 11,
              color: widget.textColor.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }

  // ---- tables (Excel-style) ----------------------------------------------

  /// Outside a table the button inserts one (grid picker + custom dialog);
  /// with a table focused it becomes the Table menu (rows, columns, delete).
  Widget _tableButton() {
    if (!(_editor?.isTableFocused ?? false)) {
      return _barButton(
        Icons.table_chart_outlined,
        'Insert table',
        _showInsertTableDialog,
      );
    }
    return PopupMenuButton<TableOp>(
      tooltip: 'Table',
      icon: Icon(
        Icons.table_chart_outlined,
        size: 20,
        color: widget.textColor.withValues(alpha: 0.55),
      ),
      onSelected: (op) => _editor?.applyTableOp(op),
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: TableOp.rowAbove,
          height: 40,
          child: Text('Insert row above'),
        ),
        PopupMenuItem(
          value: TableOp.rowBelow,
          height: 40,
          child: Text('Insert row below'),
        ),
        PopupMenuItem(
          value: TableOp.columnLeft,
          height: 40,
          child: Text('Insert column left'),
        ),
        PopupMenuItem(
          value: TableOp.columnRight,
          height: 40,
          child: Text('Insert column right'),
        ),
        PopupMenuDivider(height: 8),
        PopupMenuItem(
          value: TableOp.deleteRow,
          height: 40,
          child: Text('Delete row'),
        ),
        PopupMenuItem(
          value: TableOp.deleteColumn,
          height: 40,
          child: Text('Delete column'),
        ),
        PopupMenuItem(
          value: TableOp.deleteTable,
          height: 40,
          child: Text('Delete table'),
        ),
      ],
    );
  }

  Future<void> _showInsertTableDialog() async {
    final size = await showDialog<_TableSize>(
      context: context,
      builder: (_) => const _InsertTableDialog(),
    );
    if (size == null || !mounted) return;
    _editor?.insertTable(size.columns, size.rows);
  }
}

/// Grid-picker result: [columns] text columns, [rows] body rows (the header
/// row is always added automatically).
class _TableSize {
  const _TableSize({required this.columns, required this.rows});

  final int columns;
  final int rows;
}

/// Insert dialog: hover a grid for a quick size, or type exact columns/rows
/// and press Insert.
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
    final r = rows < 1
        ? 1
        : (rows > kMaxTableRows ? kMaxTableRows : rows);
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
