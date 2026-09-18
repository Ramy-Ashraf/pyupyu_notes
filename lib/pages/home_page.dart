import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/notes_controller.dart';
import '../widgets/editor_pane.dart';
import '../widgets/sidebar.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final NotesController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const double _minSidebarWidth = 220;
  static const double _maxSidebarWidth = 520;

  final _searchFocus = FocusNode();
  bool _hoverDivider = false;
  bool _dragDivider = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _searchFocus.dispose();
    super.dispose();
  }

  void _onController() {
    if (mounted) setState(() {});
    _maybeShowDue();
  }

  DateTime? _lastDueNotify;
  void _maybeShowDue() {
    final due = widget.controller.dueNotes;
    if (due.isEmpty) return;
    final now = DateTime.now();
    if (_lastDueNotify != null &&
        now.difference(_lastDueNotify!).inMinutes < 5) {
      return;
    }
    _lastDueNotify = now;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${due.length} reminder${due.length == 1 ? '' : 's'} due: ${due.first.title}'),
          behavior: SnackBarBehavior.floating,
          width: 420,
          action: SnackBarAction(
            label: 'View',
            onPressed: () {
              widget.controller.setView(NotesView.due);
              widget.controller.selectNote(due.first.id);
            },
          ),
        ),
      );
    });
  }

  void _quickCapture() {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quick capture'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Type and press Save…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = ctrl.text.trim();
              Navigator.of(context).pop();
              if (text.isEmpty) return;
              final note = widget.controller.createNote();
              note.body = text;
              widget.controller.updateNote(note);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              controller.createNote,
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
            _searchFocus.requestFocus();
          },
          const SingleActivator(LogicalKeyboardKey.keyF,
              control: true, shift: true): () {
            controller.clearFilters();
            _searchFocus.requestFocus();
          },
          const SingleActivator(LogicalKeyboardKey.keyK, control: true):
              _quickCapture,
        },
        child: Focus(
          autofocus: true,
          child: Column(
            children: [
              if (controller.upcomingNotes.isNotEmpty &&
                  controller.view != NotesView.due)
                _dueStrip(context),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: controller.sidebarWidth
                          .clamp(_minSidebarWidth, _maxSidebarWidth)
                          .toDouble(),
                      child: Sidebar(
                        controller: controller,
                        searchFocus: _searchFocus,
                      ),
                    ),
                    _buildResizeHandle(context),
                    Expanded(
                      child: EditorPane(
                        key: ValueKey('editor-${controller.selected?.id}'),
                        controller: controller,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dueStrip(BuildContext context) {
    final controller = widget.controller;
    final next = controller.upcomingNotes.first;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: InkWell(
        onTap: () {
          controller.setView(NotesView.due);
          controller.selectNote(next.id);
        },
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.alarm,
                  size: 15, color: scheme.onTertiaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Next: ${next.title} — ${_dueLabel(next.dueAt!)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onTertiaryContainer,
                  ),
                ),
              ),
              Text(
                'Ctrl+Shift+F to search · Ctrl+K quick capture',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onTertiaryContainer
                      .withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _dueLabel(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.day}/${d.month} ${two(d.hour)}:${two(d.minute)}';
  }

  /// Draggable divider between the sidebar and the editor.
  Widget _buildResizeHandle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final highlight = _hoverDivider || _dragDivider;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _hoverDivider = true),
      onExit: (_) => setState(() => _hoverDivider = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _dragDivider = true),
        onHorizontalDragUpdate: (d) => widget.controller
            .setSidebarWidth(widget.controller.sidebarWidth + d.delta.dx),
        onHorizontalDragEnd: (_) => setState(() => _dragDivider = false),
        onHorizontalDragCancel: () => setState(() => _dragDivider = false),
        child: Container(
          width: 7,
          color: highlight
              ? scheme.primary.withValues(alpha: 0.45)
              : Colors.transparent,
          child: Center(
            child: Container(
              width: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}
