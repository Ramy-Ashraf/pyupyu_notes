import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/format_text_controller.dart';
import '../models/format_span.dart';
import '../utils/markdown_table.dart';
import 'table_block.dart';

/// Row/column operations the toolbar can apply to the focused table block.
enum TableOp {
  rowAbove,
  rowBelow,
  columnLeft,
  columnRight,
  deleteRow,
  deleteColumn,
  deleteTable,
}

/// A text run of the note body.
abstract class _Block {
  _Block(this.focusNode);

  final FocusNode focusNode;
}

/// A text run of the note body.
class _TextBlock extends _Block {
  _TextBlock(this.controller, super.focusNode);

  final FormatTextController controller;
}

/// A spreadsheet table block.
class _TableBlock extends _Block {
  _TableBlock(this.table, super.focusNode, this.key, {this.autofocus = false});

  final TableData table;
  final GlobalKey<ExcelTableBlockState> key;

  /// Whether the grid should select its first cell when first built.
  final bool autofocus;
}

/// The note body editor: the body is split into blocks at Markdown table
/// boundaries. Text runs keep the full rich-text experience (bold/italic,
/// headings, checklists, lists) in their own field; each Markdown table is
/// rendered and edited as an Excel-style grid ([ExcelTableBlock]).
///
/// The plain Markdown body stays the source of truth: every edit recomposes
/// the document text and reports it (with the formatting ranges) through
/// [onChanged], so persistence and `.txt` export are unchanged.
class BodyEditor extends StatefulWidget {
  const BodyEditor({
    super.key,
    required this.noteId,
    required this.initialBody,
    this.initialFormats = const [],
    required this.textColor,
    required this.onChanged,
    this.onFocusChanged,
    this.onRequestInsertTable,
  });

  /// Identifies the note being edited; switching it rebuilds the editor
  /// from the new note's content.
  final String noteId;

  final String initialBody;
  final List<FormatSpan> initialFormats;
  final Color textColor;

  /// Fired after every content change with the recomposed Markdown body and
  /// its formatting spans.
  final void Function(String body, List<FormatSpan> formats) onChanged;

  /// Fired when focus moves (or content changes) so toolbar states refresh.
  final VoidCallback? onFocusChanged;

  /// Fired from the right-click menu of a text block ("Insert table…").
  final VoidCallback? onRequestInsertTable;

  @override
  State<BodyEditor> createState() => BodyEditorState();
}

class BodyEditorState extends State<BodyEditor> {
  late List<_Block> _blocks;
  late String _syncedBody;
  int? _focusedIndex;

  @override
  void initState() {
    super.initState();
    _blocks = _buildBlocks(
      widget.initialBody,
      widget.initialFormats,
      reuseTables: false,
    );
    _syncedBody = _composeBlocks(_blocks);
    if (widget.initialBody.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusTextBlock(0, atEnd: false);
      });
    } else if (_syncedBody != widget.initialBody) {
      // Normalize the stored body (e.g. pad an unpiped table) immediately.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onChanged(_syncedBody, _composeBlockFormats(_blocks));
        }
      });
    }
  }

  @override
  void didUpdateWidget(BodyEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Note switched, or external content change (e.g. restored from disk).
    if (widget.noteId != oldWidget.noteId ||
        widget.initialBody != _syncedBody) {
      _rebuild(
        widget.initialBody,
        globalSpans: widget.initialFormats,
        reuseTables: false,
      );
    }
  }

  @override
  void dispose() {
    for (final b in _blocks) {
      if (b is _TextBlock) {
        b.controller.dispose();
        b.focusNode.dispose();
      } else if (b is _TableBlock) {
        b.focusNode.dispose();
      }
    }
    super.dispose();
  }

  // ---- public API (toolbar) ------------------------------------------------

  /// The recomposed Markdown body (kept current on every change).
  String get text => _syncedBody;

  /// Whether the focused block is a table (drives the toolbar Table menu).
  bool get isTableFocused {
    final i = _focusedIndex;
    return i != null && i < _blocks.length && _blocks[i] is _TableBlock;
  }

  /// Whether every character in the focused text block's selection carries
  /// [flag].
  bool isActive(int flag) =>
      _focusedTextBlock?.controller.isActive(flag) ?? false;

  void toggleFormat(int flag) =>
      _focusedTextBlock?.controller.toggleFormat(flag);

  void toggleChecklist() =>
      _focusedTextBlock?.controller.toggleChecklist();

  void toggleBulletList() =>
      _focusedTextBlock?.controller.toggleBulletList();

  void toggleNumberedList() =>
      _focusedTextBlock?.controller.toggleNumberedList();

  void clearFormats() => _focusedTextBlock?.controller.clearFormats();

  /// Returns keyboard focus to the block that had it (used after toolbar
  /// button clicks steal focus).
  void refocus() {
    final i = _focusedIndex;
    if (i == null || i >= _blocks.length) {
      final t = _lastTextIndex;
      if (t != null) _focusTextBlock(t, atEnd: true);
      return;
    }
    final b = _blocks[i];
    if (b is _TextBlock) {
      b.focusNode.requestFocus();
    } else if (b is _TableBlock) {
      b.focusNode.requestFocus();
    }
  }

  /// Inserts [insertion] at the caret of the focused text block.
  void insertText(String insertion) {
    final block =
        _focusedTextBlock ?? _lastTextBlock ?? _ensureTrailingTextBlock();
    final v = block.controller.value;
    final sel = v.selection;
    final from = sel.isValid
        ? math.min(sel.baseOffset, sel.extentOffset)
        : v.text.length;
    final to = sel.isValid
        ? math.max(sel.baseOffset, sel.extentOffset)
        : v.text.length;
    block.controller.value = v.copyWith(
      text: v.text.replaceRange(from, to, insertion),
      selection: TextSelection.collapsed(offset: from + insertion.length),
      composing: TextRange.empty,
    );
    block.focusNode.requestFocus();
  }

  /// Inserts an empty [columns] × [bodyRows] table, splitting the focused
  /// text block at the caret; the caret moves into the table's first cell.
  void insertTable(int columns, int bodyRows) {
    final tableBlock = _TableBlock(
      TableData.empty(columns, bodyRows),
      FocusNode(),
      GlobalKey<ExcelTableBlockState>(),
      autofocus: true,
    );

    final textIdx = _focusedTextIndex ?? _lastTextIndex;
    final List<_Block> next;
    final dispose = <_Block>[];

    if (textIdx == null) {
      next = [..._blocks, _newTextBlock("", const []), tableBlock];
    } else {
      final block = _blocks[textIdx] as _TextBlock;
      final caret = _clampInt(
        block.controller.selection.baseOffset,
        0,
        block.controller.text.length,
      );
      final head = _newTextBlock(
        block.controller.text.substring(0, caret),
        _spansLeft(block.controller.formats, caret),
      );
      final tail = _newTextBlock(
        block.controller.text.substring(caret),
        _spansRight(block.controller.formats, caret),
      );
      dispose.add(block);
      next = List<_Block>.of(_blocks)
        ..removeRange(textIdx, textIdx + 1)
        ..insertAll(textIdx, [
          if (head.controller.text.isNotEmpty || textIdx == 0) head,
          tableBlock,
          if (tail.controller.text.isNotEmpty ||
              textIdx == _blocks.length - 1)
            tail,
        ]);
    }

    _pruneEmptyRunsBetweenTables(next);
    _disposeLater(dispose);
    setState(() {
      _blocks = next;
      _focusedIndex = next.indexOf(tableBlock);
      _syncedBody = _composeBlocks(_blocks);
    });
    widget.onChanged(_syncedBody, _composeBlockFormats(_blocks));
    widget.onFocusChanged?.call();
  }

  void applyTableOp(TableOp op) {
    final i = _focusedIndex;
    if (i == null || i >= _blocks.length) return;
    final block = _blocks[i];
    if (block is! _TableBlock) return;
    final state = block.key.currentState;
    if (state == null) return;
    switch (op) {
      case TableOp.rowAbove:
        state.insertRow(above: true);
      case TableOp.rowBelow:
        state.insertRow(above: false);
      case TableOp.columnLeft:
        state.insertColumn(before: true);
      case TableOp.columnRight:
        state.insertColumn(before: false);
      case TableOp.deleteRow:
        state.deleteRow();
      case TableOp.deleteColumn:
        state.deleteColumn();
      case TableOp.deleteTable:
        state.deleteTable();
    }
  }

  // ---- block helpers -------------------------------------------------------

  _TextBlock _newTextBlock(String text, List<FormatSpan> formats) {
    late final _TextBlock block;
    block = _TextBlock(
      FormatTextController(text: text, formats: formats),
      FocusNode(onKeyEvent: (_, event) => _handleTextBlockKeys(block, event)),
    );
    block.controller.onEdited = () => _onTextBlockChanged(block);
    block.focusNode.addListener(() {
      if (!block.focusNode.hasFocus) return;
      final i = _blocks.indexOf(block);
      if (i >= 0) {
        _focusedIndex = i;
        widget.onFocusChanged?.call();
      }
    });
    return block;
  }

  _TextBlock? get _focusedTextBlock {
    final i = _focusedTextIndex;
    return i == null ? null : _blocks[i] as _TextBlock;
  }

  int? get _focusedTextIndex {
    final i = _focusedIndex;
    if (i == null || i >= _blocks.length) return null;
    return _blocks[i] is _TextBlock ? i : null;
  }

  int? get _lastTextIndex {
    for (var i = _blocks.length - 1; i >= 0; i--) {
      if (_blocks[i] is _TextBlock) return i;
    }
    return null;
  }

  _TextBlock? get _lastTextBlock {
    final i = _lastTextIndex;
    return i == null ? null : _blocks[i] as _TextBlock;
  }

  /// Guarantees at least one text block (appends one if the body is all
  /// tables) so there is always somewhere to type.
  _TextBlock _ensureTrailingTextBlock() {
    final last = _lastTextBlock;
    if (last != null) return last;
    final block = _newTextBlock('', const []);
    setState(() => _blocks = [..._blocks, block]);
    return block;
  }

  void _focusTextBlock(int index, {required bool atEnd}) {
    if (index < 0 || index >= _blocks.length) return;
    final block = _blocks[index];
    if (block is! _TextBlock) return;
    block.focusNode.requestFocus();
    block.controller.selection = TextSelection.collapsed(
      offset: atEnd ? block.controller.text.length : 0,
    );
  }

  // ---- document composition ------------------------------------------------

  String _composeBlocks(List<_Block> blocks) {
    final buf = StringBuffer();
    for (var i = 0; i < blocks.length; i++) {
      if (i > 0) buf.write('\n');
      buf.write(_blockText(blocks[i]));
    }
    return buf.toString();
  }

  List<FormatSpan> _composeBlockFormats(List<_Block> blocks) {
    final out = <FormatSpan>[];
    var offset = 0;
    for (var i = 0; i < blocks.length; i++) {
      if (i > 0) offset += 1;
      final b = blocks[i];
      if (b is _TextBlock) {
        for (final sp in b.controller.formats) {
          out.add(FormatSpan(sp.start + offset, sp.end + offset, sp.flags));
        }
      }
      offset += _blockText(b).length;
    }
    return normalizeSpans(out);
  }

  // ---- structure parsing ---------------------------------------------------

  /// Builds the block list for [doc]. Existing table blocks whose serialized
  /// Markdown matches a table range are reused (same [TableData], focus node
  /// and key) so grid state survives rebuilds.
  List<_Block> _buildBlocks(
    String doc,
    List<FormatSpan> globalSpans, {
    required bool reuseTables,
  }) {
    final lines = doc.split('\n');
    final lineStarts = List<int>.filled(lines.length, 0);
    var p = 0;
    for (var i = 0; i < lines.length; i++) {
      lineStarts[i] = p;
      p += lines[i].length + 1;
    }
    final oldTables = reuseTables
        ? [
            for (final b in _blocks)
              if (b is _TableBlock) b,
          ]
        : <_TableBlock>[];
    final tables = findMarkdownTables(doc);
    final blocks = <_Block>[];
    var line = 0;

    void addTextRun(int from, int to) {
      if (to <= from) return;
      final text = lines.sublist(from, to).join('\n');
      final segStart = lineStarts[from];
      final segEnd = lineStarts[to - 1] + lines[to - 1].length;
      final local = [
        for (final sp in globalSpans)
          if (sp.end > segStart && sp.start < segEnd)
            FormatSpan(
              math.max(sp.start, segStart) - segStart,
              math.min(sp.end, segEnd) - segStart,
              sp.flags,
            ),
      ];
      blocks.add(_newTextBlock(text, local));
    }

    for (final t in tables) {
      addTextRun(line, t.startLine);
      final tableLines = lines.sublist(t.startLine, t.endLine + 1);
      final md = tableLines.join('\n');
      _TableBlock? existing;
      for (var i = 0; i < oldTables.length; i++) {
        if (oldTables[i].table.toMarkdown() == md) {
          existing = oldTables.removeAt(i);
          break;
        }
      }
      blocks.add(
        existing ??
            _TableBlock(
              TableData.parse(tableLines),
              FocusNode(),
              GlobalKey<ExcelTableBlockState>(),
            ),
      );
      line = t.endLine + 1;
    }
    addTextRun(line, lines.length);
    if (blocks.isEmpty) blocks.add(_newTextBlock('', const []));
    return blocks;
  }

  /// Parses [doc] into blocks and swaps them in, keeping the focus/caret at
  /// [focusOffset] (a text caret, or a cell when that offset now belongs to
  /// a table).
  void _rebuild(
    String doc, {
    int? focusOffset,
    List<FormatSpan>? globalSpans,
    bool reuseTables = true,
  }) {
    final spans = globalSpans ?? _composeBlockFormats(_blocks);
    final oldBlocks = _blocks;
    final blocks = _buildBlocks(doc, spans, reuseTables: reuseTables);
    final recomposed = _composeBlocks(blocks);

    // Locate the focus target in the new blocks.
    int? focusIndex;
    int? focusCaret;
    (int, int)? focusCell;
    if (focusOffset != null) {
      final lineStarts = <int>[];
      var p = 0;
      for (final b in blocks) {
        lineStarts.add(p);
        p += _blockText(b).length + 1;
      }
      for (var i = 0; i < blocks.length; i++) {
        final b = blocks[i];
        final len = _blockText(b).length;
        final start = lineStarts[i];
        if (focusOffset >= start && focusOffset <= start + len) {
          focusIndex = i;
          if (b is _TextBlock) {
            focusCaret = _clampInt(focusOffset - start, 0, len);
          } else if (b is _TableBlock) {
            final table = b.table;
            final blockText = recomposed.substring(
              start,
              math.min(start + len, recomposed.length),
            );
            focusCell = _mapOffsetToCell(table, blockText, focusOffset - start);
          }
          break;
        }
      }
    }

    // Deferred disposal — the rebuild can run from inside a controller's own
    // change notification while its TextField is still mounted.
    final keptNodes = <FocusNode>{
      for (final b in blocks)
        if (b is _TableBlock) b.focusNode,
    };
    final stale = <_Block>[];
    for (final b in oldBlocks) {
      if (keptNodes.contains(b.focusNode)) continue;
      stale.add(b);
    }

    setState(() {
      _blocks = blocks;
      _focusedIndex = focusIndex;
      _syncedBody = recomposed;
    });
    _disposeLater(stale);

    widget.onChanged(_syncedBody, _composeBlockFormats(_blocks));
    widget.onFocusChanged?.call();

    if (focusIndex != null) {
      final target = focusIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final b = _blocks[target];
        if (b is _TextBlock) {
          if (focusCaret != null) {
            b.controller.selection = TextSelection.collapsed(
              offset: _clampInt(focusCaret, 0, b.controller.text.length),
            );
          }
          b.focusNode.requestFocus();
        } else if (b is _TableBlock) {
          final cell = focusCell ?? (0, 0);
          b.key.currentState?.selectCell(cell.$1, cell.$2);
        }
      });
    }
  }

  // ---- change handling -----------------------------------------------------

  void _onTextBlockChanged(_TextBlock block) {
    if (!_blocks.contains(block)) {
      // Stale notification from a block replaced by a rebuild (its disposal
      // is deferred by a frame) — it is no longer part of the document.
      return;
    }
    final doc = _composeBlocks(_blocks);
    final kinds = [for (final b in _blocks) b is _TableBlock];
    if (!listEquals(kinds, _segmentKinds(doc))) {
      // A Markdown table was just typed/pasted into plain text: restructure
      // and drop the caret into the new grid.
      final idx = _blocks.indexOf(block);
      final caret = (idx >= 0 ? _docOffsetOfBlock(idx) : 0) +
          _clampInt(
            block.controller.selection.baseOffset,
            0,
            block.controller.text.length,
          );
      _rebuild(doc, focusOffset: caret);
      return;
    }
    setState(() => _syncedBody = doc);
    widget.onChanged(doc, _composeBlockFormats(_blocks));
    widget.onFocusChanged?.call();
  }

  /// Kind (table?) of each block segment the document would parse into.
  List<bool> _segmentKinds(String doc) {
    final kinds = <bool>[];
    final lines = doc.split('\n');
    var line = 0;
    for (final t in findMarkdownTables(doc)) {
      if (t.startLine > line) kinds.add(false);
      kinds.add(true);
      line = t.endLine + 1;
    }
    if (line < lines.length) kinds.add(false);
    return kinds;
  }

  void _onTableChanged(_TableBlock block) {
    final doc = _composeBlocks(_blocks);
    setState(() => _syncedBody = doc);
    widget.onChanged(doc, _composeBlockFormats(_blocks));
    widget.onFocusChanged?.call();
  }

  // ---- table block lifecycle ----------------------------------------------

  /// Removes the table block at [index] and merges/separates its neighbors.
  void _removeTableBlock(int index) {
    final next = List<_Block>.of(_blocks);
    final removed = next.removeAt(index);
    final dispose = <_Block>[removed];
    int? focusIdx;
    int? pendingCaret;

    if (index > 0 &&
        index < next.length &&
        next[index - 1] is _TextBlock &&
        next[index] is _TextBlock) {
      // Join the text runs the table used to separate. An empty side
      // contributes nothing, so no stray newline is left behind.
      final a = next[index - 1] as _TextBlock;
      final b = next[index] as _TextBlock;
      final aEmpty = a.controller.text.isEmpty;
      final bEmpty = b.controller.text.isEmpty;
      final merged = _newTextBlock(
        aEmpty
            ? b.controller.text
            : bEmpty
                ? a.controller.text
                : '${a.controller.text}\n${b.controller.text}',
        aEmpty
            ? b.controller.formats
            : bEmpty
                ? a.controller.formats
                : [
                    ...a.controller.formats,
                    for (final sp in b.controller.formats)
                      FormatSpan(
                        sp.start + a.controller.text.length + 1,
                        sp.end + a.controller.text.length + 1,
                        sp.flags,
                      ),
                  ],
      );
      pendingCaret = aEmpty ? 0 : a.controller.text.length + 1;
      next
        ..removeRange(index - 1, index + 1)
        ..insert(index - 1, merged);
      dispose
        ..clear()
        ..addAll([removed, a, b]);
      focusIdx = index - 1;
    } else if (index > 0 &&
        index < next.length &&
        next[index - 1] is _TableBlock &&
        next[index] is _TableBlock) {
      // Keep two tables separated by an empty line.
      next.insert(index, _newTextBlock('', const []));
      focusIdx = index;
    } else if (next.isNotEmpty) {
      focusIdx = math.min(math.max(index - 1, 0), next.length - 1);
    }

    if (next.isEmpty) next.add(_newTextBlock('', const []));
    _disposeLater(dispose);
    setState(() {
      _blocks = next;
      _focusedIndex = focusIdx;
      _syncedBody = _composeBlocks(_blocks);
    });
    widget.onChanged(_syncedBody, _composeBlockFormats(_blocks));
    widget.onFocusChanged?.call();

    if (focusIdx != null) {
      final target = focusIdx;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final i = math.min(target, _blocks.length - 1);
        final b = _blocks[i];
        if (b is _TextBlock) {
          b.focusNode.requestFocus();
          b.controller.selection = TextSelection.collapsed(
            offset: _clampInt(
              pendingCaret ?? b.controller.text.length,
              0,
              b.controller.text.length,
            ),
          );
        } else if (b is _TableBlock) {
          b.focusNode.requestFocus();
        }
      });
    }
  }

  /// Removes empty text runs squeezed between two tables (they would parse
  /// as an unwanted blank separator after recomposition... or rather, they
  /// would render as stray empty lines with nothing to click).
  void _pruneEmptyRunsBetweenTables(List<_Block> blocks) {
    for (var i = blocks.length - 1; i >= 0; i--) {
      if (blocks.length <= 1) break;
      final b = blocks[i];
      if (b is! _TextBlock) continue;
      final prevIsTable = i > 0 && blocks[i - 1] is _TableBlock;
      final nextIsTable =
          i + 1 < blocks.length && blocks[i + 1] is _TableBlock;
      if (b.controller.text.isEmpty && prevIsTable && nextIsTable) {
        b.controller.dispose();
        b.focusNode.dispose();
        blocks.removeAt(i);
      }
    }
  }

  void _disposeLater(List<_Block> blocks) {
    if (blocks.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final b in blocks) {
        if (b is _TextBlock) {
          b.controller.dispose();
          b.focusNode.dispose();
        } else if (b is _TableBlock) {
          b.focusNode.dispose();
        }
      }
    });
  }

  // ---- focus movement between blocks ---------------------------------------

  KeyEventResult _handleTextBlockKeys(_TextBlock block, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final sel = block.controller.selection;
    if (key == LogicalKeyboardKey.arrowDown &&
        sel.isCollapsed &&
        sel.baseOffset >= block.controller.text.length) {
      final i = _blocks.indexOf(block);
      if (i >= 0 && i + 1 < _blocks.length) {
        _focusNeighbor(_blocks[i + 1], fromStart: true);
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.arrowUp &&
        sel.isCollapsed &&
        sel.baseOffset <= 0) {
      final i = _blocks.indexOf(block);
      if (i > 0) {
        _focusNeighbor(_blocks[i - 1], fromStart: false);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _focusNeighbor(_Block block, {required bool fromStart}) {
    if (block is _TextBlock) {
      block.focusNode.requestFocus();
      block.controller.selection = TextSelection.collapsed(
        offset: fromStart ? 0 : block.controller.text.length,
      );
    } else if (block is _TableBlock) {
      final state = block.key.currentState;
      if (state != null) {
        if (fromStart) {
          state.selectCell(0, 0);
        } else {
          state.selectCell(
            block.table.rowCount - 1,
            block.table.columnCount - 1,
          );
        }
      } else {
        block.focusNode.requestFocus();
      }
    }
  }

  // ---- pure helpers --------------------------------------------------------

  /// The source text a block contributes to the document.
  String _blockText(_Block block) => block is _TextBlock
      ? block.controller.text
      : (block as _TableBlock).table.toMarkdown();

  int _clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

  int _docOffsetOfBlock(int index) {
    var offset = 0;
    for (var i = 0; i < index && i < _blocks.length; i++) {
      offset += _blockText(_blocks[i]).length + 1;
    }
    return offset;
  }

  (int, int) _mapOffsetToCell(TableData table, String blockText, int offset) {
    final clamped = _clampInt(offset, 0, blockText.length);
    final parts = blockText.substring(0, clamped).split('\n');
    final lineIdx = parts.length - 1;
    final lineText = parts.last;
    var pipes = 0;
    for (var i = 0; i < lineText.length; i++) {
      final c = lineText[i];
      if (c == '\\') {
        i++;
        continue;
      }
      if (c == '|') pipes++;
    }
    final row = lineIdx == 0 ? 0 : math.max(0, lineIdx - 1);
    final col = math.max(0, math.min(pipes - 1, table.columnCount - 1));
    return (
      _clampInt(row, 0, table.rowCount - 1),
      _clampInt(col, 0, table.columnCount - 1),
    );
  }

  List<FormatSpan> _spansLeft(List<FormatSpan> spans, int pos) => [
        for (final sp in spans)
          if (sp.end <= pos)
            sp
          else if (sp.start < pos) FormatSpan(sp.start, pos, sp.flags),
      ];

  List<FormatSpan> _spansRight(List<FormatSpan> spans, int pos) => [
        for (final sp in spans)
          if (sp.start >= pos)
            FormatSpan(sp.start - pos, sp.end - pos, sp.flags)
          else if (sp.end > pos) FormatSpan(0, sp.end - pos, sp.flags),
      ];

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final docEmpty = _syncedBody.isEmpty;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final i = _lastTextIndex;
        if (i != null) {
          _focusTextBlock(i, atEnd: true);
        } else {
          FocusManager.instance.primaryFocus?.unfocus();
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < _blocks.length; i++)
                      _buildBlock(_blocks[i], dark, docEmpty && i == 0),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBlock(_Block block, bool dark, bool showHint) {
    if (block is _TextBlock) {
      return SizedBox(
        width: double.infinity,
        child: TextField(
          controller: block.controller,
          focusNode: block.focusNode,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textAlignVertical: TextAlignVertical.top,
          style: TextStyle(
            color: widget.textColor,
            fontSize: 15,
            height: 1.5,
          ),
          cursorColor: widget.textColor.withValues(alpha: 0.8),
          contextMenuBuilder: (context, editableTextState) =>
              _textContextMenu(context, editableTextState),
          decoration: InputDecoration(
            hintText: showHint ? 'Take a note…' : null,
            hintStyle: TextStyle(
              color: widget.textColor.withValues(alpha: 0.35),
              fontSize: 15,
            ),
            border: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 2),
          ),
        ),
      );
    }

    final table = block as _TableBlock;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ExcelTableBlock(
        key: table.key,
        table: table.table,
        focusNode: table.focusNode,
        dark: dark,
        autofocus: table.autofocus,
        onChanged: () => _onTableChanged(table),
        onDeleted: () {
          final i = _blocks.indexOf(table);
          if (i >= 0) _removeTableBlock(i);
        },
        onActivated: () {
          final i = _blocks.indexOf(table);
          if (i >= 0 && _focusedIndex != i) {
            _focusedIndex = i;
            widget.onFocusChanged?.call();
          }
        },
      ),
    );
  }

  Widget _textContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final items = [...editableTextState.contextMenuButtonItems];
    if (widget.onRequestInsertTable != null) {
      items.add(
        ContextMenuButtonItem(
          label: 'Insert table…',
          onPressed: () {
            editableTextState.hideToolbar();
            widget.onRequestInsertTable!();
          },
        ),
      );
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: items,
    );
  }
}
