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
  });

  final Note note;
  final NotesController controller;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pal = paletteFor(note.colorIndex, dark);
    final textColor = noteTextColor(dark);

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
                          Expanded(
                            child: Text(
                              note.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: textColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (note.snippet.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            note.snippet,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: textColor.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      const SizedBox(height: 6),
                      Text(
                        formatNoteDate(note.updatedAt),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: textColor.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                if (note.hasDiagram)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 2),
                    child: SizedBox(
                      width: 44,
                      height: 34,
                      child: CustomPaint(
                        painter: StrokeThumbPainter(
                          strokes: note.strokes,
                          color: textColor.withValues(alpha: 0.85),
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
        const PopupMenuItem(
          value: 'duplicate',
          height: 40,
          child: Text('Duplicate'),
        ),
        PopupMenuItem(
          value: 'delete',
          height: 40,
          child: Text('Delete', style: TextStyle(color: Colors.red[400])),
        ),
      ],
    ).then((value) {
      switch (value) {
        case 'pin':
          controller.togglePin(note);
        case 'duplicate':
          controller.duplicateNote(note);
        case 'delete':
          controller.deleteNote(note);
      }
    });
  }
}
