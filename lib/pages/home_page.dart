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
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
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
        },
        child: Focus(
          autofocus: true,
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
      ),
    );
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
