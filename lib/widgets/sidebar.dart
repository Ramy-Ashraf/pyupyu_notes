import 'package:flutter/material.dart';

import '../controllers/notes_controller.dart';
import '../models/note.dart';
import '../utils/note_templates.dart';
import 'note_card.dart';

/// Left pane: app header, search, view filters, tags, note list and actions.
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
    setState(() {});
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
                  tooltip: 'Display & accent',
                  icon: const Icon(Icons.palette_outlined, size: 20),
                  onPressed: () => _showDisplaySettings(context),
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
                hintText: 'Search notes, tags, diagrams',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _search.text.isNotEmpty
                    ? IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _search.clear();
                          controller.setSearch('');
                        },
                      )
                    : null,
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
          _viewBar(context),
          _filterRow(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 16, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    controller.searchQuery.trim().isEmpty
                        ? '${notes.length} notes'
                        : '${notes.length} matching',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                PopupMenuButton<NotesSort>(
                  tooltip: 'Sort',
                  initialValue: controller.sort,
                  onSelected: controller.setSort,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: NotesSort.updated,
                        height: 36,
                        child: Text('Sort: Updated')),
                    PopupMenuItem(
                        value: NotesSort.created,
                        height: 36,
                        child: Text('Sort: Created')),
                    PopupMenuItem(
                        value: NotesSort.title,
                        height: 36,
                        child: Text('Sort: Title')),
                    PopupMenuItem(
                        value: NotesSort.color,
                        height: 36,
                        child: Text('Sort: Color')),
                  ],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sort,
                          size: 14, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        switch (controller.sort) {
                          NotesSort.updated => 'Updated',
                          NotesSort.created => 'Created',
                          NotesSort.title => 'Title',
                          NotesSort.color => 'Color',
                        },
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (controller.tagCounts.isNotEmpty) _tagChips(context),
          Expanded(
            child: notes.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _emptyText(),
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (controller.view == NotesView.trash &&
                            controller.trashCount > 0)
                          TextButton(
                            onPressed: controller.emptyTrash,
                            child: const Text('Empty trash'),
                          ),
                      ],
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
                        searchQuery: controller.searchQuery,
                        onTap: () => controller.selectNote(note.id),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: controller.createNote,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New note'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Calendar',
                  icon: const Icon(Icons.calendar_month_outlined),
                  onPressed: () => _showCalendar(context),
                ),
                IconButton(
                  tooltip: 'New from template',
                  icon: const Icon(Icons.dashboard_customize_outlined),
                  onPressed: () => _showTemplates(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _emptyText() {
    final c = widget.controller;
    if (c.searchQuery.trim().isNotEmpty ||
        c.tagFilter != null ||
        c.colorFilter != null) {
      return 'No matches — clear filters';
    }
    return switch (c.view) {
      NotesView.all => 'No notes yet',
      NotesView.favorites => 'No favorites yet',
      NotesView.due => 'No reminders',
      NotesView.archived => 'Nothing archived',
      NotesView.trash => 'Trash is empty',
    };
  }

  Widget _viewBar(BuildContext context) {
    final c = widget.controller;
    Widget chip(NotesView v, String label, int count) {
      final selected = c.view == v;
      return ChoiceChip(
        label: Text('$label${count > 0 ? ' $count' : ''}'),
        selected: selected,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => c.setView(v),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            chip(NotesView.all, 'All', c.totalCount),
            const SizedBox(width: 6),
            chip(NotesView.favorites, '★', c.favoritesCount),
            const SizedBox(width: 6),
            chip(NotesView.due, 'Due', c.dueCount),
            const SizedBox(width: 6),
            chip(NotesView.archived, 'Archived', c.archivedCount),
            const SizedBox(width: 6),
            chip(NotesView.trash, 'Trash', c.trashCount),
          ],
        ),
      ),
    );
  }

  Widget _filterRow(BuildContext context) {
    final c = widget.controller;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Row(
        children: [
          if (c.tagFilter != null)
            InputChip(
              label: Text('#${c.tagFilter}',
                  style: const TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
              onDeleted: () => c.setTagFilter(null),
            ),
          if (c.colorFilter != null)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: InputChip(
                label: const Text('Color',
                    style: TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                onDeleted: () => c.setColorFilter(null),
              ),
            ),
          const Spacer(),
          if (c.tagFilter != null ||
              c.colorFilter != null ||
              c.searchQuery.isNotEmpty)
            TextButton(
              onPressed: c.clearFilters,
              child: const Text('Clear',
                  style: TextStyle(fontSize: 12)),
            )
          else
            Text(
              'Filters',
              style: TextStyle(
                  fontSize: 11, color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  Widget _tagChips(BuildContext context) {
    final c = widget.controller;
    final tags = c.tagCounts.take(12).toList();
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tags.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final e = tags[i];
          final selected = c.tagFilter == e.key;
          return ChoiceChip(
            label: Text('#${e.key} ${e.value}',
                style: const TextStyle(fontSize: 11)),
            selected: selected,
            visualDensity: VisualDensity.compact,
            onSelected: (_) =>
                c.setTagFilter(selected ? null : e.key),
          );
        },
      ),
    );
  }

  IconData _themeIcon(ThemeMode mode) => switch (mode) {
        ThemeMode.system => Icons.brightness_auto,
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
      };

  void _showDisplaySettings(BuildContext context) {
    final c = widget.controller;
    const accents = [
      0xFF0078D4,
      0xFF8B5CF6,
      0xFF10B981,
      0xFFE11D48,
      0xFFF59E0B,
      0xFF0EA5E9,
    ];
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Display'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Accent color'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final a in accents)
                  InkWell(
                    onTap: () {
                      c.setAccent(a);
                      Navigator.of(context).pop();
                    },
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Color(a),
                        shape: BoxShape.circle,
                        border: c.accentValue == a
                            ? Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary,
                                width: 3)
                            : null,
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: () {
                    c.setAccent(null);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Default'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(child: Text('Compact density')),
                Switch(
                  value: c.compact,
                  onChanged: (_) {
                    c.toggleCompact();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
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

  void _showTemplates(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New from template'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final t in noteTemplates)
                ListTile(
                  dense: true,
                  title: Text(t.name),
                  subtitle: Text(
                    t.body.split('\n').first,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    final note = widget.controller.createFromTemplate(t);
                    widget.controller.selectNote(note.id);
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showCalendar(BuildContext context) {
    final c = widget.controller;
    final dated = [
      for (final n in c.allNotes)
        if (n.dueAt != null && !n.trashed) n,
    ]..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reminders & calendar'),
        content: SizedBox(
          width: 380,
          height: 380,
          child: dated.isEmpty
              ? const Center(child: Text('No reminders set'))
              : ListView.builder(
                  itemCount: dated.length,
                  itemBuilder: (context, i) {
                    final Note n = dated[i];
                    return ListTile(
                      dense: true,
                      title: Text(n.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text(_dueLabel(n.dueAt!)),
                      trailing: n.isOverdue
                          ? const Icon(Icons.warning_amber,
                              color: Colors.orange, size: 18)
                          : null,
                      onTap: () {
                        c.selectNote(n.id);
                        if (c.view == NotesView.trash ||
                            c.view == NotesView.archived) {
                          c.setView(NotesView.all);
                        }
                        Navigator.of(context).pop();
                      },
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
  }

  String _dueLabel(DateTime d) {
    final now = DateTime.now();
    final sameDay =
        d.year == now.year && d.month == now.month && d.day == now.day;
    String two(int v) => v.toString().padLeft(2, '0');
    final hm = '${two(d.hour)}:${two(d.minute)}';
    if (sameDay) return 'Today $hm';
    return '${d.day}/${d.month}/${d.year} $hm';
  }

  void _showShortcuts(BuildContext context) {
    const rows = [
      ('Ctrl+N', 'New note'),
      ('Ctrl+F / Ctrl+Shift+F', 'Search notes'),
      ('Ctrl+B / I / U', 'Bold / italic / underline'),
      ('Enter', 'Continue (or exit) a list'),
      ('Tab / Shift+Tab', 'Next / previous table cell'),
      ('Enter (in table)', 'Row below (empty row exits)'),
      ('Ctrl+Z / Y', 'Undo / redo (text & canvas)'),
      ('Ctrl+D', 'Duplicate selected stroke'),
      ('Delete', 'Delete selected stroke'),
      ('Drag empty canvas', 'Marquee-select shapes'),
      ('Handles', 'Resize / rotate selection'),
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
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (key, desc) in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 150,
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
