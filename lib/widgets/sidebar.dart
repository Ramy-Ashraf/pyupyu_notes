import 'package:flutter/material.dart';

import '../controllers/notes_controller.dart';
import 'note_card.dart';

/// Left pane: app header, search, the note list and the "New note" button —
/// modelled on Windows Sticky Notes' list view.
class Sidebar extends StatefulWidget {
  const Sidebar({
    super.key,
    required this.controller,
    required this.searchFocus,
  });

  final NotesController controller;
  final FocusNode searchFocus;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  late final TextEditingController _search =
      TextEditingController(text: widget.controller.searchQuery);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncSearch);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncSearch);
    _search.dispose();
    super.dispose();
  }

  void _syncSearch() {
    if (!mounted) return;
    if (_search.text != widget.controller.searchQuery) {
      _search.text = widget.controller.searchQuery;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final notes = controller.notes;

    return Container(
      color: dark ? const Color(0xFF232323) : const Color(0xFFF3F3F3),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
            child: Row(
              children: [
                Icon(Icons.sticky_note_2_outlined,
                    size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Notes',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: switch (controller.themeMode) {
                    ThemeMode.system => 'Theme: system',
                    ThemeMode.light => 'Theme: light',
                    ThemeMode.dark => 'Theme: dark',
                  },
                  icon: Icon(_themeIcon(controller.themeMode), size: 20),
                  onPressed: controller.cycleTheme,
                ),
                IconButton(
                  tooltip: 'Keyboard shortcuts',
                  icon: const Icon(Icons.keyboard_option_key, size: 20),
                  onPressed: () => _showShortcuts(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              focusNode: widget.searchFocus,
              controller: _search,
              onChanged: controller.setSearch,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search notes',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor:
                    dark ? const Color(0xFF2E2E2E) : Colors.white,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 16, 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                controller.searchQuery.trim().isEmpty
                    ? '${controller.totalCount} notes'
                    : '${notes.length} matching',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: notes.isEmpty
                ? Center(
                    child: Text(
                      controller.searchQuery.trim().isEmpty
                          ? 'No notes yet'
                          : 'No matches',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    itemCount: notes.length,
                    itemBuilder: (context, i) {
                      final note = notes[i];
                      return NoteCard(
                        note: note,
                        controller: controller,
                        selected: note.id == controller.selectedId,
                        onTap: () => controller.selectNote(note.id),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: controller.createNote,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New note'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _themeIcon(ThemeMode mode) => switch (mode) {
        ThemeMode.system => Icons.brightness_auto,
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
      };

  void _showShortcuts(BuildContext context) {
    const rows = [
      ('Ctrl+N', 'New note'),
      ('Ctrl+F', 'Search notes'),
      ('Ctrl+B / I / U', 'Bold / italic / underline'),
      ('Enter', 'Continue (or exit) a list'),
      ('Ctrl+Z / Y', 'Undo / redo (text & canvas)'),
      ('Ctrl+D', 'Duplicate selected stroke'),
      ('Delete', 'Delete selected stroke'),
      ('Arrow keys', 'Nudge selection (Shift = 10 px)'),
      ('Shift+drag', 'Snap shapes to 45° / square'),
      ('Esc', 'Deselect stroke'),
      ('Mouse wheel', 'Zoom canvas'),
      ('Middle-drag / hand', 'Pan canvas'),
      ('Drag divider', 'Resize sidebar'),
    ];
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keyboard shortcuts'),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (key, desc) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(
                          key,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(desc,
                            style: const TextStyle(fontSize: 12.5)),
                      ),
                    ],
                  ),
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
    );
  }
}
