import 'package:flutter/material.dart';

import '../controllers/notes_controller.dart';
import '../models/note.dart';
import '../theme/note_palette.dart';
import '../utils/format.dart';
import 'drawing/diagram_painter.dart';

/// A colored note preview card in the sidebar list.
class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.controller,
    required this.selected,
    required this.onTap,
    this.searchQuery = '',
  });

  final Note note;
  final NotesController controller;
  final bool selected;
  final VoidCallback onTap;
  final String searchQuery;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pal = paletteFor(note.colorIndex, dark);
    final textColor = noteTextColor(dark);
    final locked = note.isLocked && !controller.isUnlocked(note);
    final (done, total) = note.checklistCounts();

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 3, 4, 3),
      child: Material(
        color: pal.body,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          onSecondaryTapUp: (d) => _showMenu(context, d.globalPosition),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (note.pinned)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(
                                Icons.push_pin,
                                size: 12,
                                color: textColor.withValues(alpha: 0.6),
                              ),
                            ),
                          if (note.favorite)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(
                                Icons.star,
                                size: 12,
                                color: textColor.withValues(alpha: 0.6),
                              ),
                            ),
                          if (locked)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(
                                Icons.lock,
                                size: 12,
                                color: textColor.withValues(alpha: 0.6),
                              ),
                            ),
                          Expanded(
                            child: _highlightText(
                              locked ? 'Locked note' : note.title,
                              textColor,
                              bold: true,
                            ),
                          ),
                          if (note.dueAt != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(
                                note.isOverdue
                                    ? Icons.warning_amber
                                    : Icons.alarm_outlined,
                                size: 13,
                                color: note.isOverdue
                                    ? Colors.orange
                                    : textColor.withValues(alpha: 0.6),
                              ),
                            ),
                        ],
                      ),
                      if (!locked && note.snippet.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: _highlightText(
                            note.snippet,
                            textColor.withValues(alpha: 0.7),
                            maxLines: 2,
                          ),
                        ),
                      if (note.tags.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            spacing: 4,
                            children: [
                              for (final t in note.tags.take(3))
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: textColor.withValues(alpha: 0.1),
                                  ),
                                  child: Text(
                                    '#$t',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color:
                                          textColor.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      if (total > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: done / total,
                                    minHeight: 4,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$done/$total',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: textColor.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 6),
                      Text(
                        _dateLabel(),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: textColor.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                if (note.hasDiagram && !locked)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 2),
                    child: SizedBox(
                      width: 44,
                      height: 34,
                      // Isolated so list rebuilds don't repaint thumbnails
                      // whose strokes didn't change (see shouldRepaint).
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: StrokeThumbPainter(
                            strokes: note.strokes,
                            color: textColor.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _dateLabel() {
    if (note.dueAt != null) {
      final d = note.dueAt!;
      String two(int v) => v.toString().padLeft(2, '0');
      return '${formatNoteDate(note.updatedAt)} · due ${d.day}/${d.month} ${two(d.hour)}:${two(d.minute)}';
    }
    return formatNoteDate(note.updatedAt);
  }

  Widget _highlightText(String text, Color color,
      {bool bold = false, int maxLines = 1}) {
    final q = searchQuery.trim().toLowerCase();
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
      fontSize: bold ? 13 : 12,
      color: color,
    );
    if (q.isEmpty || !text.toLowerCase().contains(q)) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    var i = 0;
    while (true) {
      final idx = lower.indexOf(q, i);
      if (idx < 0) {
        spans.add(TextSpan(text: text.substring(i)));
        break;
      }
      if (idx > i) spans.add(TextSpan(text: text.substring(i, idx)));
      spans.add(TextSpan(
        text: text.substring(idx, idx + q.length),
        style: const TextStyle(
            backgroundColor: Colors.yellow, color: Colors.black),
      ));
      i = idx + q.length;
    }
    return Text.rich(
      TextSpan(children: spans, style: style),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }

  void _showMenu(BuildContext context, Offset position) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'pin',
          height: 40,
          child: Text(note.pinned ? 'Unpin' : 'Pin'),
        ),
        PopupMenuItem(
          value: 'favorite',
          height: 40,
          child: Text(note.favorite ? 'Unfavorite' : 'Favorite'),
        ),
        PopupMenuItem(
          value: note.archived ? 'unarchive' : 'archive',
          height: 40,
          child: Text(note.archived ? 'Unarchive' : 'Archive'),
        ),
        const PopupMenuItem(
          value: 'duplicate',
          height: 40,
          child: Text('Duplicate'),
        ),
        if (note.trashed)
          const PopupMenuItem(
            value: 'restore',
            height: 40,
            child: Text('Restore'),
          ),
        if (note.trashed)
          PopupMenuItem(
            value: 'permanent',
            height: 40,
            child:
                Text('Delete forever', style: TextStyle(color: Colors.red[400])),
          )
        else
          PopupMenuItem(
            value: 'delete',
            height: 40,
            child: Text(
                controller.view == NotesView.trash ? 'Delete' : 'Move to trash',
                style: TextStyle(color: Colors.red[400])),
          ),
      ],
    ).then((value) {
      switch (value) {
        case 'pin':
          controller.togglePin(note);
        case 'favorite':
          controller.toggleFavorite(note);
        case 'archive':
          controller.setArchived(note, true);
        case 'unarchive':
          controller.setArchived(note, false);
        case 'duplicate':
          controller.duplicateNote(note);
        case 'restore':
          controller.restoreFromTrash(note);
        case 'permanent':
          controller.permanentDelete(note);
        case 'delete':
          controller.trashNote(note);
      }
    });
  }
}
