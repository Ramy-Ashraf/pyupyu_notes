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

    final locked = note.isLocked && !widget.controller.isUnlocked(note);
    if (locked) return _lockedView(note, pal.body, onBar);

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatEdited(note.updatedAt),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: onBar),
                      ),
                      if (note.dueAt != null)
                        InkWell(
                          onTap: () => _showReminderDialog(note),
                          child: Text(
                            'Due ${_dueLabel(note.dueAt!)} · tap to change',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: onBar,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                _moreMenu(note, onBar),
                _colorMenu(note, onBar),
                IconButton(
                  tooltip: note.favorite ? 'Unfavorite' : 'Favorite',
                  icon: Icon(
                    note.favorite ? Icons.star : Icons.star_border,
                    size: 20,
                    color: onBar,
                  ),
                  onPressed: () => widget.controller.toggleFavorite(note),
                ),
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
                  tooltip: note.archived ? 'Unarchive' : 'Archive',
                  icon: Icon(
                    note.archived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                    size: 20,
                    color: onBar,
                  ),
                  onPressed: () => widget.controller.toggleArchive(note),
                ),
                IconButton(
                  tooltip: 'Reminder',
                  icon: Icon(
                    note.dueAt == null
                        ? Icons.alarm_add_outlined
                        : Icons.alarm_on,
                    size: 20,
                    color: onBar,
                  ),
                  onPressed: () => _showReminderDialog(note),
                ),
                IconButton(
                  tooltip: note.isLocked ? 'Locked' : 'Lock note',
                  icon: Icon(
                    note.isLocked ? Icons.lock : Icons.lock_open,
                    size: 20,
                    color: onBar,
                  ),
                  onPressed: () => _showLockDialog(note),
                ),
                IconButton(
                  tooltip: 'Move to trash',
                  icon: Icon(Icons.delete_outline, size: 20, color: onBar),
                  onPressed: () => _delete(note),
                ),
              ],
            ),
          ),
          _metaStrip(note),
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

  Widget _lockedView(Note note, Color body, Color onBar) {
    return Container(
      color: body,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: _UnlockCard(note: note, controller: widget.controller),
        ),
      ),
    );
  }

  Widget _metaStrip(Note note) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final textColor = noteTextColor(dark);
    final (done, total) = note.checklistCounts();
    if (note.tags.isEmpty &&
        total == 0 &&
        note.wordGoal <= 0 &&
        note.attachments.isEmpty &&
        note.history.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: textColor.withValues(alpha: 0.12)),
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final t in note.tags)
            InkWell(
              onTap: () => _showTagsDialog(note),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: textColor.withValues(alpha: 0.1),
                ),
                child: Text('#$t',
                    style: TextStyle(
                        fontSize: 11,
                        color: textColor.withValues(alpha: 0.8))),
              ),
            ),
          if (total > 0)
            Text('$done/$total done',
                style: TextStyle(
                    fontSize: 11,
                    color: textColor.withValues(alpha: 0.6))),
          if (note.wordGoal > 0)
            Text('${note.wordCount}/${note.wordGoal} words',
                style: TextStyle(
                    fontSize: 11,
                    color: textColor.withValues(alpha: 0.6))),
          if (note.attachments.isNotEmpty)
            Text('${note.attachments.length} file(s)',
                style: TextStyle(
                    fontSize: 11,
                    color: textColor.withValues(alpha: 0.6))),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => _showTagsDialog(note),
            child: Text('Tags',
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.primary)),
          ),
          InkWell(
            onTap: () => _showHistoryDialog(note),
            child: Text(
                'History (${note.history.length})',
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.primary)),
          ),
          InkWell(
            onTap: () => _showGoalDialog(note),
            child: Text('Goal',
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.primary)),
          ),
          InkWell(
            onTap: () => _showAttachmentsDialog(note),
            child: Text('Files',
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.primary)),
          ),
        ],
      ),
    );
  }

  String _dueLabel(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.day}/${d.month}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  void _delete(Note note) {
    widget.controller.trashNote(note);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Note moved to trash'),
        behavior: SnackBarBehavior.floating,
        width: 320,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: widget.controller.undoDelete,
        ),
      ),
    );
  }

  Future<void> _showReminderDialog(Note note) async {
    if (note.dueAt != null) {
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reminder'),
          content: Text('Currently set to ${_dueLabel(note.dueAt!)}.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('remove'),
              child: const Text('Remove'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('change'),
              child: const Text('Change'),
            ),
          ],
        ),
      );
      if (action == 'remove') {
        widget.controller.clearDue(note);
        setState(() {});
        return;
      }
      if (action != 'change') return;
      if (!mounted) return;
    }
    var date = note.dueAt ?? DateTime.now().add(const Duration(hours: 1));
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(date),
    );
    if (pickedTime == null || !mounted) return;
    date = DateTime(pickedDate.year, pickedDate.month, pickedDate.day,
        pickedTime.hour, pickedTime.minute);
    widget.controller.setDue(note, date);
    setState(() {});
  }

  Future<void> _showLockDialog(Note note) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(note.isLocked ? 'Note locked' : 'Lock note'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(note.isLocked
                ? 'Enter PIN to unlock, or remove the lock.'
                : 'Set a PIN to lock this note on this device.'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'PIN',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          if (note.isLocked)
            TextButton(
              onPressed: () => Navigator.of(context).pop('__remove__'),
              child: const Text('Remove lock'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text),
            child: Text(note.isLocked ? 'Unlock' : 'Lock'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null) return;
    if (result == '__remove__') {
      widget.controller.removeLock(note);
      setState(() {});
      return;
    }
    if (result.trim().isEmpty) return;
    if (note.isLocked) {
      final ok = widget.controller.unlock(note, result.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Unlocked' : 'Wrong PIN'),
        behavior: SnackBarBehavior.floating,
        width: 280,
      ));
      setState(() {});
    } else {
      widget.controller.lockNote(note, result.trim());
      setState(() {});
    }
  }

  Future<void> _showTagsDialog(Note note) async {
    final ctrl = TextEditingController(text: note.tags.join(', '));
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tags'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'work, ideas, todo (comma separated)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            if (widget.controller.suggestTags(note).isNotEmpty)
              Wrap(
                spacing: 6,
                children: [
                  for (final s in widget.controller.suggestTags(note))
                    ActionChip(
                      label: Text('#$s'),
                      onPressed: () {
                        final cur = ctrl.text.trim();
                        ctrl.text =
                            cur.isEmpty ? s : '$cur, $s';
                      },
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
          FilledButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null) return;
    widget.controller.setTags(
        note,
        result
            .split(RegExp(r'[,\s]+'))
            .where((t) => t.trim().isNotEmpty)
            .toList());
    setState(() {});
  }

  Future<void> _showHistoryDialog(Note note) async {
    if (note.history.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No history yet — edit the note first'),
        behavior: SnackBarBehavior.floating,
        width: 320,
      ));
      return;
    }
    final history = note.history.reversed.toList();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Version history'),
        content: SizedBox(
          width: 420,
          height: 360,
          child: ListView.builder(
            itemCount: history.length,
            itemBuilder: (context, i) {
              final h = history[i];
              return ListTile(
                dense: true,
                title: Text(
                  h.body.split('\n').firstWhere(
                      (l) => l.trim().isNotEmpty,
                      orElse: () => '(empty)'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(formatEdited(h.savedAt)),
                trailing: TextButton(
                  onPressed: () {
                    widget.controller.restoreSnapshot(note, h);
                    Navigator.of(context).pop();
                    setState(() {});
                  },
                  child: const Text('Restore'),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    setState(() {});
  }

  Future<void> _showGoalDialog(Note note) async {
    final ctrl =
        TextEditingController(text: note.wordGoal > 0 ? '${note.wordGoal}' : '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Word goal'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'e.g. 500 (empty = none)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null) return;
    widget.controller.setWordGoal(note, int.tryParse(result.trim()) ?? 0);
    setState(() {});
  }

  Future<void> _showAttachmentsDialog(Note note) async {
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Attachments'),
          content: SizedBox(
            width: 380,
            height: 300,
            child: Column(
              children: [
                Expanded(
                  child: note.attachments.isEmpty
                      ? const Center(child: Text('No files attached'))
                      : ListView.builder(
                          itemCount: note.attachments.length,
                          itemBuilder: (context, i) {
                            final a = note.attachments[i];
                            return ListTile(
                              dense: true,
                              leading: const Icon(
                                  Icons.insert_drive_file_outlined,
                                  size: 20),
                              title: Text(a.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(a.path,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              trailing: IconButton(
                                tooltip: 'Remove',
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () {
                                  widget.controller
                                      .removeAttachment(note, a);
                                  setDialog(() {});
                                  setState(() {});
                                },
                              ),
                            );
                          },
                        ),
                ),
                const Divider(),
                _AddAttachmentRow(
                  onAdd: (name, path) {
                    widget.controller.addAttachment(note, name, path);
                    setDialog(() {});
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moreMenu(Note note, Color onBar) {
    return PopupMenuButton<String>(
      tooltip: 'More actions',
      icon: Icon(Icons.more_horiz, size: 22, color: onBar),
      onSelected: (v) async {
        final dark = Theme.of(context).brightness == Brightness.dark;
        final bg = paletteFor(note.colorIndex, dark).body;
        String? path;
        var message = '';
        switch (v) {
          case 'export-txt':
            path = await exportNoteText(note);
            message = path == null ? 'Nothing to export' : 'Saved to $path';
          case 'export-md':
            path = await exportNoteMarkdown(note);
            message = path == null ? 'Nothing to export' : 'Saved to $path';
          case 'export-html':
            path = await exportNoteHtml(note, background: bg);
            message = path == null
                ? 'Nothing to export'
                : 'Saved printable HTML to $path';
          case 'export-csv':
            path = await exportTablesCsv(note);
            message =
                path == null ? 'No tables in note' : 'Saved CSV to $path';
          case 'export-png':
            path = await exportDiagramPng(note, background: bg);
            message =
                path == null ? 'Canvas is empty' : 'Saved diagram to $path';
          case 'export-svg':
            path = await exportDiagramSvg(note, background: bg);
            message =
                path == null ? 'Canvas is empty' : 'Saved SVG to $path';
          case 'copy-svg':
            final ok =
                await copyDiagramSvg(note, background: bg);
            message = ok ? 'SVG copied to clipboard' : 'Canvas is empty';
          case 'clear-due':
            widget.controller.clearDue(note);
            setState(() {});
            return;
          case 'history':
            await _showHistoryDialog(note);
            return;
          case 'stats':
            _showStats(note);
            return;
          default:
            return;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
            width: 460,
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
          value: 'export-md',
          height: 40,
          child: Text('Export note as .md'),
        ),
        PopupMenuItem(
          value: 'export-html',
          height: 40,
          child: Text('Export printable .html (→ PDF)'),
        ),
        PopupMenuItem(
          value: 'export-csv',
          height: 40,
          child: Text('Export tables as .csv'),
        ),
        PopupMenuItem(
          value: 'export-png',
          height: 40,
          child: Text('Export diagram as .png'),
        ),
        PopupMenuItem(
          value: 'export-svg',
          height: 40,
          child: Text('Export diagram as .svg'),
        ),
        PopupMenuItem(
          value: 'copy-svg',
          height: 40,
          child: Text('Copy diagram SVG'),
        ),
        PopupMenuDivider(height: 8),
        PopupMenuItem(
          value: 'clear-due',
          height: 40,
          child: Text('Clear reminder'),
        ),
        PopupMenuItem(
          value: 'history',
          height: 40,
          child: Text('Version history…'),
        ),
        PopupMenuItem(
          value: 'stats',
          height: 40,
          child: Text('Writing stats…'),
        ),
      ],
    );
  }

  void _showStats(Note note) {
    final (done, total) = note.checklistCounts();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Writing stats'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${note.wordCount} words · ${note.body.length} chars'),
            const SizedBox(height: 4),
            Text(total > 0
                ? 'Checklist: $done of $total done (${(note.checklistProgress() * 100).round()}%)'
                : 'Checklist: none'),
            const SizedBox(height: 4),
            Text(note.wordGoal > 0
                ? 'Goal: ${note.wordCount}/${note.wordGoal} (${(note.goalProgress * 100).round()}%)'
                : 'Goal: none'),
            const SizedBox(height: 4),
            Text('Diagram: ${note.strokes.length} stroke(s)'),
            Text('History: ${note.history.length} snapshot(s)'),
            Text('Tags: ${note.effectiveTags().join(', ')}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
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
        PopupMenuItem(
          height: 40,
          onTap: () => WidgetsBinding.instance.addPostFrameCallback((_) {
            _showColorFilter(note);
          }),
          child: const Text('Filter list by this color…'),
        ),
      ],
    );
  }

  void _showColorFilter(Note note) {
    widget.controller.setColorFilter(note.colorIndex);
    widget.controller.setView(NotesView.all);
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

class _UnlockCard extends StatefulWidget {
  const _UnlockCard({required this.note, required this.controller});

  final Note note;
  final NotesController controller;

  @override
  State<_UnlockCard> createState() => _UnlockCardState();
}

class _UnlockCardState extends State<_UnlockCard> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock, size: 36),
            const SizedBox(height: 8),
            Text('Locked note',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(widget.note.title,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'PIN',
                errorText: _error,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _tryUnlock(),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _tryUnlock,
              child: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
  }

  void _tryUnlock() {
    final ok = widget.controller.unlock(widget.note, _ctrl.text.trim());
    if (ok) return;
    setState(() => _error = 'Wrong PIN');
  }
}

class _AddAttachmentRow extends StatefulWidget {
  const _AddAttachmentRow({required this.onAdd});

  final void Function(String name, String path) onAdd;

  @override
  State<_AddAttachmentRow> createState() => _AddAttachmentRowState();
}

class _AddAttachmentRowState extends State<_AddAttachmentRow> {
  final _name = TextEditingController();
  final _path = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _path.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _name,
            decoration: const InputDecoration(
              hintText: 'Name',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextField(
            controller: _path,
            decoration: const InputDecoration(
              hintText: 'File path',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Attach',
          icon: const Icon(Icons.attach_file),
          onPressed: () {
            final name = _name.text.trim().isEmpty
                ? _path.text.split(RegExp(r'[\\/]')).last
                : _name.text.trim();
            if (_path.text.trim().isEmpty) return;
            widget.onAdd(name, _path.text.trim());
            _name.clear();
            _path.clear();
          },
        ),
      ],
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
  static final RegExp _whitespace = RegExp(r'\s+');

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
        .split(_whitespace)
        .where((w) => w.isNotEmpty)
        .length;
    final (done, total) = widget.note.checklistCounts();
    return Column(
      children: [
        _formatBar(context, words, body.length, done, total),
        Expanded(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.keyB,
                        control: true): () =>
                    _editor?.toggleFormat(FormatFlags.bold),
                const SingleActivator(LogicalKeyboardKey.keyB, meta: true):
                    () => _editor?.toggleFormat(FormatFlags.bold),
                const SingleActivator(LogicalKeyboardKey.keyI,
                        control: true): () =>
                    _editor?.toggleFormat(FormatFlags.italic),
                const SingleActivator(LogicalKeyboardKey.keyI, meta: true):
                    () => _editor?.toggleFormat(FormatFlags.italic),
                const SingleActivator(LogicalKeyboardKey.keyU,
                        control: true): () =>
                    _editor?.toggleFormat(FormatFlags.underline),
                const SingleActivator(LogicalKeyboardKey.keyU, meta: true):
                    () => _editor?.toggleFormat(FormatFlags.underline),
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

  void _insertLink() {
    _editor?.insertText('[text](https://)');
  }

  void _insertDivider() {
    _editor?.insertText('\n---\n');
  }

  Widget _formatBar(
      BuildContext context, int words, int chars, int done, int total) {
    final goal = widget.note.wordGoal;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: widget.textColor.withValues(alpha: 0.12),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
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
            _formatButton(
                FormatFlags.code, Icons.code, 'Inline code'),
            _formatButton(FormatFlags.quote, Icons.format_quote,
                'Quote'),
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
            _barButton(Icons.link, 'Insert link', _insertLink),
            _barButton(
                Icons.horizontal_rule, 'Divider', _insertDivider),
            _barButton(Icons.today_outlined, 'Insert date & time',
                _insertDateTime),
            _barButton(Icons.format_clear, 'Clear formatting',
                () => _editor?.clearFormats()),
            const SizedBox(width: 12),
            Text(
              total > 0
                  ? '$words words · $chars chars · $done/$total'
                  : goal > 0
                      ? '$words/$goal words'
                      : '$words words · $chars chars',
              style: TextStyle(
                fontSize: 11,
                color: widget.textColor.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
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
