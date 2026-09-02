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
  final _focusNode = FocusNode();

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
