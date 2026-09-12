import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/markdown_table.dart';

/// Excel-green used for the active-cell border and fill handle.
const Color _kExcelGreen = Color(0xFF217346);
const Color _kExcelGreenDark = Color(0xFF4CA374);

/// Like [IntrinsicColumnWidth], but clamped so columns never collapse below
/// [minWidth] nor blow past [maxWidth] (long content wraps instead).
class ClampedIntrinsicColumnWidth extends IntrinsicColumnWidth {
  const ClampedIntrinsicColumnWidth({
    this.minWidth = 92,
    this.maxWidth = 320,
    super.flex,
  });

  final double minWidth;
  final double maxWidth;

  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) =>
      super
          .minIntrinsicWidth(cells, containerWidth)
          .clamp(minWidth, maxWidth);

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) =>
      super
          .maxIntrinsicWidth(cells, containerWidth)
          .clamp(minWidth, maxWidth);
}

/// A spreadsheet-style table block: Excel-like gridlines, a column-letter
/// header (A, B, C…), a row-number gutter, a shaded header row, and a green
/// active-cell border with fill handle.
///
/// Editing model mirrors Excel:
/// - a single click selects a cell (green border);
/// - typing a printable character starts editing and replaces the content;
///   double-click / Enter / F2 start editing with the caret;
/// - `Enter` commits and moves down, `Tab` / `Shift+Tab` commit and move
///   along the row, arrows move the selection;
/// - `Delete` clears the cell, `Escape` cancels the edit, `Ctrl+C` /
///   `Ctrl+V` copy and paste the active cell;
/// - right-click a cell / column letter / row number for the row and column
///   operations, or use the ＋ row / ＋ column helpers under the grid.
///
/// Data lives in the caller-owned [table] ([TableData] is mutated in place);
/// every mutation is reported through [onChanged] / [onDeleted] so the
/// owning editor can regenerate the note's Markdown.
class ExcelTableBlock extends StatefulWidget {
  const ExcelTableBlock({
    super.key,
    required this.table,
    required this.focusNode,
    required this.dark,
    required this.onChanged,
    required this.onDeleted,
    required this.onActivated,
    this.autofocus = false,
    this.initialRow = 0,
    this.initialCol = 0,
  });

  final TableData table;

  /// Selection-mode keyboard focus (arrows/typing while a cell is selected).
  /// Owned by the parent so it can also track which block is active.
  final FocusNode focusNode;

  final bool dark;
  final VoidCallback onChanged;
  final VoidCallback onDeleted;

  /// Called when the user clicks or focuses anywhere in this table, so the
  /// parent can route toolbar actions here.
  final VoidCallback onActivated;

  /// Whether to select the first cell (used right after insertion).
  final bool autofocus;

  /// Cell to select initially when [autofocus] is set.
  final int initialRow;
  final int initialCol;

  @override
  State<ExcelTableBlock> createState() => ExcelTableBlockState();
}

class ExcelTableBlockState extends State<ExcelTableBlock> {
  int _activeRow = 0;
  int _activeCol = 0;
  bool _editing = false;
  bool _hovering = false;
  TextEditingController? _cellCtrl;
  FocusNode? _cellFocus;

  TableData get _table => widget.table;

  /// The table data owned by the parent (exposed for tests and tooling).
  TableData get table => widget.table;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onBlockFocusChanged);
    if (widget.autofocus) {
      _activeRow = _clampInt(widget.initialRow, 0, _table.rowCount - 1);
      _activeCol = _clampInt(widget.initialCol, 0, _table.columnCount - 1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.focusNode.requestFocus();
      });
    }
  }

  static int _clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

  @override
  void didUpdateWidget(ExcelTableBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      oldWidget.focusNode.removeListener(_onBlockFocusChanged);
      widget.focusNode.addListener(_onBlockFocusChanged);
    }
    _activeRow = _clampInt(_activeRow, 0, _table.rowCount - 1);
    _activeCol = _clampInt(_activeCol, 0, _table.columnCount - 1);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onBlockFocusChanged);
    // A cell editor may still be open when the block is removed (note
    // switch, table deleted from the toolbar); release it. Children have
    // already unmounted by the time State.dispose runs.
    _cellFocus?.dispose();
    _cellCtrl?.dispose();
    super.dispose();
  }

  void _onBlockFocusChanged() {
    if (widget.focusNode.hasFocus) widget.onActivated();
    if (mounted) setState(() {});
  }

  // ---- palette -------------------------------------------------------------

  Color get _sheet => widget.dark ? const Color(0xFF2B2B2B) : Colors.white;
  Color get _grid =>
      widget.dark ? const Color(0xFF4B4B4B) : const Color(0xFFD3D7DC);
  Color get _gutterFill =>
      widget.dark ? const Color(0xFF353535) : const Color(0xFFF3F3F3);
  Color get _headerFill =>
      widget.dark ? const Color(0xFF3D3D3D) : const Color(0xFFEAEAEA);
  Color get _cellText =>
      widget.dark ? const Color(0xFFE6E6E6) : const Color(0xFF1F1F1F);
  Color get _mutedText =>
      widget.dark ? const Color(0xFF9A9A9A) : const Color(0xFF7A7F87);
  Color get _frame =>
      widget.dark ? const Color(0xFF5C5C5C) : const Color(0xFFB7BDC5);
  Color get _accent => widget.dark ? _kExcelGreenDark : _kExcelGreen;

  BorderSide get _gridSide => BorderSide(color: _grid, width: 1);

  TextStyle get _cellStyle =>
      TextStyle(fontSize: 13, height: 1.25, color: _cellText);
  TextStyle get _gutterStyle => TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        color: _mutedText,
      );

  /// Gridlines for a cell at logical [row]/[col] of a [rows]×[cols] table:
  /// right border between columns, bottom border between rows; the outer
  /// frame is drawn by the sheet container.
  Border _cellBorder(int row, int col, int rows, int cols) => Border(
        right: col < cols - 1 ? _gridSide : BorderSide.none,
        bottom: row < rows - 1 ? _gridSide : BorderSide.none,
      );

  // ---- selection & editing -------------------------------------------------

  /// Releases the cell editor. Disposal is deferred to the end of the frame
  /// because teardown can run from inside the editor's own key/focus
  /// callbacks while the TextField is still mounted.
  void _teardownEditor() {
    final focus = _cellFocus;
    final ctrl = _cellCtrl;
    _cellFocus = null;
    _cellCtrl = null;
    _editing = false;
    if (focus != null) {
      if (focus.hasFocus) focus.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) => focus.dispose());
    }
    if (ctrl != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    }
  }

  void selectCell(int row, int col, {bool edit = false}) {
    widget.onActivated();
    // Clicking away commits the in-progress edit (Excel behavior); only
    // Escape discards.
    if (_editing) _commit();
    setState(() {
      _activeRow = _clampInt(row, 0, _table.rowCount - 1);
      _activeCol = _clampInt(col, 0, _table.columnCount - 1);
    });
    if (edit) {
      _startEditing();
    } else {
      widget.focusNode.requestFocus();
    }
  }

  /// Begins editing the active cell. With [seed] the content is replaced by
  /// that text (Excel's "type over" behavior); with [selectAll] the existing
  /// content starts out fully selected.
  void _startEditing({String? seed, bool selectAll = false}) {
    widget.onActivated();
    if (_editing) _commit(); // defensive; callers normally commit first
    final text = seed ?? _table.cellAt(_activeRow, _activeCol);
    setState(() {
      _editing = true;
      _cellCtrl = TextEditingController(text: text)
        ..addListener(_onCellTextChanged);
      _cellFocus = FocusNode(onKeyEvent: _handleEditKeys)
        ..addListener(_onCellFocusLost);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_editing || _cellFocus == null) return;
      _cellFocus!.requestFocus();
      _cellCtrl!.selection = selectAll
          ? TextSelection(baseOffset: 0, extentOffset: text.length)
          : TextSelection.collapsed(offset: text.length);
    });
  }

  void _onCellTextChanged() {
    if (mounted) setState(() {}); // re-measure the column while typing
  }

  void _onCellFocusLost() {
    // Ignore losses triggered by our own teardown; commit on real blur.
    if (!_editing || (_cellFocus?.hasFocus ?? true)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing && (_cellFocus?.hasFocus ?? false)) return;
      if (mounted && _editing) _commit();
    });
  }

  /// Writes the editing buffer into the table and reports the change.
  void _commit() {
    if (!_editing) return;
    final text = _cellCtrl?.text ?? '';
    _teardownEditor();
    if (_table.cellAt(_activeRow, _activeCol) != text) {
      _table.setCell(_activeRow, _activeCol, text);
      widget.onChanged();
    }
    if (mounted) setState(() {});
  }

  void _cancelEditing() {
    if (!_editing) return;
    _teardownEditor();
    widget.focusNode.requestFocus();
    if (mounted) setState(() {});
  }

  /// Commit-and-move used while editing a cell.
  KeyEventResult _handleEditKeys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _commit();
      _moveSelection(1, 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      _commit();
      _moveSelection(0, shift ? -1 : 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _cancelEditing();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _commit();
      _moveSelection(-1, 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _commit();
      _moveSelection(1, 0);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Excel selection-mode keys while a cell is selected but not editing.
  /// Key events bubble here from the cell editor too, so this must stay
  /// inert while a cell is being edited.
  KeyEventResult _handleSelectKeys(FocusNode node, KeyEvent event) {
    if (_editing || (_cellFocus?.hasFocus ?? false)) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final meta = HardwareKeyboard.instance.isMetaPressed;

    switch (key) {
      case LogicalKeyboardKey.arrowUp:
        _moveSelection(-1, 0);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _moveSelection(1, 0);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _moveSelection(0, -1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _moveSelection(0, 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.tab:
        _moveSelection(0, shift ? -1 : 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
      case LogicalKeyboardKey.f2:
        _startEditing();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        _table.setCell(_activeRow, _activeCol, '');
        widget.onChanged();
        return KeyEventResult.handled;
      default:
        break;
    }
    if (ctrl || meta) {
      if (key == LogicalKeyboardKey.keyC) {
        Clipboard.setData(
          ClipboardData(text: _table.cellAt(_activeRow, _activeCol)),
        );
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyV) {
        _pasteIntoActiveCell();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final char = event.character;
    if (char != null && char.isNotEmpty && char.codeUnitAt(0) >= 0x20) {
      _startEditing(seed: char);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _pasteIntoActiveCell() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = (data?.text ?? '')
        .replaceAll('\r\n', ' ')
        .replaceAll('\n', ' ');
    _table.setCell(_activeRow, _activeCol, text);
    widget.onChanged();
    setState(() {});
  }

  /// Moves the selection, clamped to the grid (Excel behavior — no wrap,
  /// no automatic row creation; use the ＋ row / ＋ column helpers).
  void _moveSelection(int dRow, int dCol) {
    if (_editing) _commit();
    setState(() {
      _activeRow = _clampInt(_activeRow + dRow, 0, _table.rowCount - 1);
      _activeCol = _clampInt(_activeCol + dCol, 0, _table.columnCount - 1);
    });
    widget.focusNode.requestFocus();
  }

  // ---- structure operations (toolbar + context menus) ----------------------

  void insertRow({required bool above}) {
    if (_editing) _commit(); // land the edit before shifting rows
    final newIdx = _table.insertRowAt(above ? _activeRow : _activeRow + 1);
    if (newIdx == null) return;
    setState(() => _activeRow = newIdx);
    widget.focusNode.requestFocus();
    widget.onChanged();
  }

  void insertColumn({required bool before}) {
    if (_editing) _commit(); // land the edit before shifting columns
    final newIdx = _table.insertColumnAt(before ? _activeCol : _activeCol + 1);
    if (newIdx == null) return;
    setState(() => _activeCol = newIdx);
    widget.focusNode.requestFocus();
    widget.onChanged();
  }

  void deleteRow() {
    if (_editing) _commit(); // land the edit before removing the row
    if (!_table.deleteRowAt(_activeRow)) {
      widget.onDeleted();
      return;
    }
    setState(() => _activeRow = _clampInt(_activeRow, 0, _table.rowCount - 1));
    widget.focusNode.requestFocus();
    widget.onChanged();
  }

  void deleteColumn() {
    if (_editing) _commit(); // land the edit before removing the column
    if (!_table.deleteColumnAt(_activeCol)) {
      widget.onDeleted();
      return;
    }
    setState(() => _activeCol = _clampInt(_activeCol, 0, _table.columnCount - 1));
    widget.focusNode.requestFocus();
    widget.onChanged();
  }

  void clearActiveCell() {
    _table.setCell(_activeRow, _activeCol, '');
    widget.onChanged();
    setState(() {});
  }

  void deleteTable() {
    if (_editing) _commit();
    widget.onDeleted();
  }

  // ---- context menus -------------------------------------------------------

  Future<void> _showMenuAt(
    Offset globalPos,
    List<PopupMenuEntry<String>> items,
  ) async {
    widget.onActivated();
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPos & const Size(1, 1),
        Offset.zero & (overlay?.size ?? const Size(400, 400)),
      ),
      items: items,
    );
    if (!mounted) return;
    switch (choice) {
      case 'rowAbove':
        insertRow(above: true);
      case 'rowBelow':
        insertRow(above: false);
      case 'colLeft':
        insertColumn(before: true);
      case 'colRight':
        insertColumn(before: false);
      case 'deleteRow':
        deleteRow();
      case 'deleteColumn':
        deleteColumn();
      case 'clearCell':
        clearActiveCell();
      case 'deleteTable':
        deleteTable();
    }
  }

  static const List<PopupMenuEntry<String>> _cellMenuItems = [
    PopupMenuItem(value: 'rowAbove', height: 38, child: Text('Insert row above')),
    PopupMenuItem(value: 'rowBelow', height: 38, child: Text('Insert row below')),
    PopupMenuItem(value: 'colLeft', height: 38, child: Text('Insert column left')),
    PopupMenuItem(value: 'colRight', height: 38, child: Text('Insert column right')),
    PopupMenuDivider(),
    PopupMenuItem(value: 'clearCell', height: 38, child: Text('Clear contents')),
    PopupMenuItem(value: 'deleteRow', height: 38, child: Text('Delete row')),
    PopupMenuItem(value: 'deleteColumn', height: 38, child: Text('Delete column')),
    PopupMenuDivider(),
    PopupMenuItem(value: 'deleteTable', height: 38, child: Text('Delete table')),
  ];

  static const List<PopupMenuEntry<String>> _columnMenuItems = [
    PopupMenuItem(value: 'colLeft', height: 38, child: Text('Insert column left')),
    PopupMenuItem(value: 'colRight', height: 38, child: Text('Insert column right')),
    PopupMenuDivider(),
    PopupMenuItem(value: 'deleteColumn', height: 38, child: Text('Delete column')),
    PopupMenuDivider(),
    PopupMenuItem(value: 'deleteTable', height: 38, child: Text('Delete table')),
  ];

  static const List<PopupMenuEntry<String>> _rowMenuItems = [
    PopupMenuItem(value: 'rowAbove', height: 38, child: Text('Insert row above')),
    PopupMenuItem(value: 'rowBelow', height: 38, child: Text('Insert row below')),
    PopupMenuDivider(),
    PopupMenuItem(value: 'deleteRow', height: 38, child: Text('Delete row')),
    PopupMenuDivider(),
    PopupMenuItem(value: 'deleteTable', height: 38, child: Text('Delete table')),
  ];

  // ---- rendering -----------------------------------------------------------

  Widget _gutterCell({
    required Widget child,
    required int gridRow,
    required int totalRows,
    double height = 22,
    void Function(Offset)? onSecondaryTapUp,
  }) {
    final cell = Container(
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _gutterFill,
        border: _cellBorder(gridRow, 0, totalRows, 2),
      ),
      child: child,
    );
    if (onSecondaryTapUp == null) return cell;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapUp: (d) => onSecondaryTapUp(d.globalPosition),
      child: cell,
    );
  }

  Widget _letterCell(int col, int totalRows) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapUp: (d) =>
          _showMenuAt(d.globalPosition, _columnMenuItems),
      child: Container(
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _gutterFill,
          border: _cellBorder(0, col + 1, totalRows, _table.columnCount + 1),
        ),
        child: Text(TableData.columnLetter(col), style: _gutterStyle),
      ),
    );
  }

  Widget _rowNumberCell(int dataRow, int totalRows) {
    return _gutterCell(
      child: Text('${dataRow + 1}', style: _gutterStyle),
      gridRow: dataRow + 1,
      totalRows: totalRows,
      height: 32,
      onSecondaryTapUp: (pos) => _showMenuAt(pos, _rowMenuItems),
    );
  }

  Widget _dataCell(int row, int col) {
    final table = _table;
    final cols = table.columnCount;
    final active = _activeRow == row && _activeCol == col;
    final isHeader = row == 0;
    final value = table.cellAt(row, col);
    final editing = active && _editing;

    final Widget content;
    if (editing) {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: TextField(
          controller: _cellCtrl,
          focusNode: _cellFocus,
          style: _cellStyle,
          maxLines: 1,
          cursorColor: _accent,
          decoration: const InputDecoration(
            isCollapsed: true,
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 7),
          ),
        ),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          value,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: isHeader
              ? _cellStyle.copyWith(fontWeight: FontWeight.w700)
              : _cellStyle,
        ),
      );
    }

    final cell = Container(
      constraints: const BoxConstraints(minHeight: 32),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: active
            ? _sheet
            : isHeader
                ? _headerFill
                : Colors.transparent,
        border: active
            ? Border.all(color: _accent, width: 2)
            : _cellBorder(row, col, table.rowCount, cols),
      ),
      child: content,
    );

    final wrapped = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => selectCell(row, col, edit: active),
      onDoubleTap: () => selectCell(row, col, edit: true),
      onSecondaryTapUp: (d) {
        if (!active) selectCell(row, col);
        _showMenuAt(d.globalPosition, _cellMenuItems);
      },
      child: cell,
    );

    if (!active) return wrapped;
    // Excel-style fill handle on the active cell.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        wrapped,
        Positioned(
          right: -3,
          bottom: -3,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _accent,
              border: Border.all(color: _sheet, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final table = _table;
    final cols = table.columnCount;
    final totalRows = table.rowCount + 1; // + column-letter row
    final editingSomewhere = _editing || (_cellFocus?.hasFocus ?? false);
    final showHelpers =
        _hovering || widget.focusNode.hasFocus || editingSomewhere;

    final grid = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: _sheet,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: _frame),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: widget.dark ? 0.3 : 0.10),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Focus(
              focusNode: widget.focusNode,
              onKeyEvent: _handleSelectKeys,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  // `fill` alone would leave every row 0px tall (fill cells
                  // contribute no height); intrinsicHeight both sizes rows
                  // from the tallest cell and stretches every cell to it.
                  defaultVerticalAlignment:
                      TableCellVerticalAlignment.intrinsicHeight,
                  columnWidths: const {0: FixedColumnWidth(30)},
                  defaultColumnWidth: const ClampedIntrinsicColumnWidth(),
                  children: [
                    TableRow(children: [
                      _gutterCell(child: const SizedBox.shrink(), gridRow: 0, totalRows: totalRows),
                      for (var c = 0; c < cols; c++) _letterCell(c, totalRows),
                    ]),
                    for (var r = 0; r < table.rowCount; r++)
                      TableRow(children: [
                        _rowNumberCell(r, totalRows),
                        for (var c = 0; c < cols; c++) _dataCell(r, c),
                      ]),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (showHelpers)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _helperButton(
                  icon: Icons.add,
                  label: 'Row',
                  onTap: () => insertRow(above: false),
                ),
                const SizedBox(width: 10),
                _helperButton(
                  icon: Icons.add,
                  label: 'Column',
                  onTap: () => insertColumn(before: false),
                ),
              ],
            ),
          ),
      ],
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: grid,
    );
  }

  Widget _helperButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: _mutedText),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 11.5, color: _mutedText)),
          ],
        ),
      ),
    );
  }
}
