/// Markdown pipe-table model + text edits behind the Notepad-style table
/// feature in text mode.
///
/// Tables are stored as GitHub-flavoured Markdown so notes stay portable
/// plain text (and export to `.txt` unchanged), exactly like Windows
/// Notepad: a header row, a delimiter row (`---`), then body rows:
///
/// ```text
/// | Name | Age |
/// | ---  | --- |
/// | Alex | 30  |
/// ```
///
/// [findMarkdownTable] locates the table surrounding a caret offset, and the
/// `build…` / row / column helpers perform Notepad's Table-menu operations
/// (insert/delete rows and columns, delete/select the table, align columns)
/// plus Tab / Shift+Tab cell navigation and Enter to move down a row.
///
/// This file is pure Dart (no Flutter dependency) so the logic is trivially
/// unit-testable.
library;

/// Hard limits for the insert-table dialog (mirrors Notepad's picker range).
const int kMaxTableColumns = 20;
const int kMaxTableBodyRows = 50;

/// Logical alignment parsed from a delimiter cell (`:---`, `---:`, …).
enum TableAlignment { none, left, center, right }

/// Parses a delimiter cell such as `---`, `:--`, `--:` or `:-:`.
TableAlignment alignmentFromCell(String cell) {
  final c = cell.trim();
  final l = c.startsWith(':');
  final r = c.endsWith(':');
  if (l && r) return TableAlignment.center;
  if (l) return TableAlignment.left;
  if (r) return TableAlignment.right;
  return TableAlignment.none;
}

String _delimiterFor(TableAlignment a, int width) {
  final w = width < 3 ? 3 : width;
  switch (a) {
    case TableAlignment.left:
      return ':${'-' * (w - 1)}';
    case TableAlignment.right:
      return '${'-' * (w - 1)}:';
    case TableAlignment.center:
      return ':${'-' * (w - 2)}:';
    case TableAlignment.none:
      return '-' * w;
  }
}

/// A parsed Markdown table block inside a document.
///
/// [rows] holds the header first, then every body row (the delimiter row is
/// exposed separately via [alignments]). All cells are trimmed, unescaped
/// values normalized to [columnCount] entries.
class MarkdownTable {
  const MarkdownTable({
    required this.startLine,
    required this.endLine,
    required this.delimiterLine,
    required this.columnCount,
    required this.startOffset,
    required this.endOffset,
    required this.rows,
    required this.alignments,
  });

  /// First line of the block (the header row), 0-based.
  final int startLine;

  /// Last line of the block (inclusive), 0-based.
  final int endLine;

  /// Absolute line index of the delimiter (`---`) row.
  final int delimiterLine;

  final int columnCount;

  /// Document offset of the first header character.
  final int startOffset;

  /// Document offset just past the last body character (excludes `\n`).
  final int endOffset;

  final List<List<String>> rows;
  final List<TableAlignment> alignments;
}

/// A text replacement plus the selection to apply afterwards.
class TableEdit {
  const TableEdit.caret(this.text, int offset)
      : baseOffset = offset,
        extentOffset = offset;

  const TableEdit.range(this.text, this.baseOffset, this.extentOffset);

  final String text;
  final int baseOffset;
  final int extentOffset;
}

// ---- line helpers ---------------------------------------------------------

/// Integer clamp (avoids `num` widening from `int.clamp`).
int _clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

List<int> _lineStarts(List<String> lines) {
  final starts = List<int>.filled(lines.length, 0);
  var p = 0;
  for (var i = 0; i < lines.length; i++) {
    starts[i] = p;
    p += lines[i].length + 1; // +1 for '\n'
  }
  return starts;
}

int _lineIndexAt(List<int> starts, int offset) {
  var idx = 0;
  for (var i = 0; i < starts.length; i++) {
    if (starts[i] <= offset) {
      idx = i;
    } else {
      break;
    }
  }
  return idx;
}

// ---- cell parsing ---------------------------------------------------------

/// Positions of unescaped `|` characters in [line].
List<int> _pipePositions(String line) {
  final out = <int>[];
  for (var i = 0; i < line.length; i++) {
    final c = line.codeUnitAt(i);
    if (c == 0x5C /* \ */ && i + 1 < line.length) {
      i++; // skip the escaped character
      continue;
    }
    if (c == 0x7C /* | */) out.add(i);
  }
  return out;
}

/// Splits a table line into trimmed, unescaped cells. Outer pipes are
/// optional: `a | b` parses like `| a | b |`.
List<String> splitTableCells(String line) {
  final raw = <String>[];
  final cur = StringBuffer();
  void push() {
    raw.add(cur.toString());
    cur.clear();
  }

  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '\\' && i + 1 < line.length) {
      final next = line[i + 1];
      if (next == '|' || next == '\\') {
        cur.write(next);
        i++;
        continue;
      }
      cur.write(c);
      continue;
    }
    if (c == '|') {
      push();
    } else {
      cur.write(c);
    }
  }
  push();

  if (raw.length > 1 && raw.first.trim().isEmpty) raw.removeAt(0);
  if (raw.length > 1 && raw.last.trim().isEmpty) raw.removeLast();
  return [for (final s in raw) s.trim()];
}

String _escapeCell(String cell) =>
    cell.replaceAll('\\', '\\\\').replaceAll('|', '\\|');

bool _isDelimiterCell(String cell) =>
    RegExp(r'^:?-{1,}:?$').hasMatch(cell.trim());

bool _isDelimiterLine(String line) {
  if (!line.contains('|')) return false;
  final cells = splitTableCells(line);
  return cells.isNotEmpty && cells.every(_isDelimiterCell);
}

bool _isTableLine(String line) =>
    line.trim().isNotEmpty && line.contains('|');

// ---- lookup ---------------------------------------------------------------

/// Finds the Markdown table surrounding [offset], or null when the caret is
/// not inside a valid `header + delimiter + body…` block.
MarkdownTable? findMarkdownTable(String text, int offset) {
  if (text.isEmpty) return null;
  final off = _clampInt(offset, 0, text.length);
  final lines = text.split('\n');
  final starts = _lineStarts(lines);
  final caretLine = _lineIndexAt(starts, off);

  var s = caretLine;
  var e = caretLine;
  while (s > 0 && _isTableLine(lines[s - 1])) {
    s--;
  }
  while (e < lines.length - 1 && _isTableLine(lines[e + 1])) {
    e++;
  }
  if (e - s + 1 < 2) return null;
  if (!_isDelimiterLine(lines[s + 1])) return null;
  if (_isDelimiterLine(lines[s])) return null;

  final header = splitTableCells(lines[s]);
  if (header.isEmpty) return null;
  final cols = header.length;

  final delimCells = splitTableCells(lines[s + 1]);
  final aligns = List<TableAlignment>.generate(
    cols,
    (i) => i < delimCells.length
        ? alignmentFromCell(delimCells[i])
        : TableAlignment.none,
  );

  final rows = <List<String>>[];
  for (var i = s; i <= e; i++) {
    if (i == s + 1) continue; // delimiter row
    rows.add(_normalizeRow(splitTableCells(lines[i]), cols));
  }

  return MarkdownTable(
    startLine: s,
    endLine: e,
    delimiterLine: s + 1,
    columnCount: cols,
    startOffset: starts[s],
    endOffset: starts[e] + lines[e].length,
    rows: rows,
    alignments: aligns,
  );
}

/// Whether [offset] sits inside a valid Markdown table.
bool isInMarkdownTable(String text, int offset) =>
    findMarkdownTable(text, offset) != null;

List<String> _normalizeRow(List<String> cells, int cols) {
  final row = List<String>.of(cells);
  while (row.length < cols) {
    row.add('');
  }
  return row.sublist(0, cols);
}

// ---- rendering ------------------------------------------------------------

String _renderRow(List<String> cells) =>
    '| ${cells.map(_escapeCell).join(' | ')} |';

String _renderDelimiter(List<TableAlignment> aligns) =>
    '| ${aligns.map((a) => _delimiterFor(a, 3)).join(' | ')} |';

String _renderBlock(List<List<String>> rows, List<TableAlignment> aligns) {
  final buf = StringBuffer(_renderRow(rows.first));
  buf.write('\n${_renderDelimiter(aligns)}');
  for (var i = 1; i < rows.length; i++) {
    buf.write('\n${_renderRow(rows[i])}');
  }
  return buf.toString();
}

/// Cells with Markdown-significant characters (`|`, `\`) escaped, so padded
/// rendering never breaks the table structure.
List<List<String>> _escapedRows(List<List<String>> rows) =>
    [for (final r in rows) [for (final c in r) _escapeCell(c)]];

List<int> _paddedWidths(List<List<String>> escaped, int cols) {
  final widths = List<int>.filled(cols, 3);
  for (final row in escaped) {
    for (var j = 0; j < cols; j++) {
      if (row[j].length > widths[j]) widths[j] = row[j].length;
    }
  }
  return widths;
}

String _renderPaddedBlock(
  List<List<String>> rows,
  List<TableAlignment> aligns,
) {
  final cols = aligns.length;
  final escaped = _escapedRows(rows);
  final widths = _paddedWidths(escaped, cols);
  String rowOf(List<String> cells) => '| ${[
        for (var j = 0; j < cols; j++) cells[j].padRight(widths[j]),
      ].join(' | ')} |';
  final buf = StringBuffer(rowOf(escaped.first));
  buf.write(
    '\n| ${[
      for (var j = 0; j < cols; j++) _delimiterFor(aligns[j], widths[j]),
    ].join(' | ')} |',
  );
  for (var i = 1; i < escaped.length; i++) {
    buf.write('\n${rowOf(escaped[i])}');
  }
  return buf.toString();
}

/// Start offset (relative to the line) of the *content* of column [col] in
/// a freshly rendered `| a | b |` row built from [cells].
int _renderedCellStart(List<String> cells, int col) {
  var pos = 2; // skip '| '
  for (var i = 0; i < col; i++) {
    pos += _escapeCell(cells[i]).length + 3; // content + ' | '
  }
  return pos;
}

// ---- raw cell geometry (original source lines) ----------------------------

/// Raw `(start, end)` segment (including padding spaces) of column [col]
/// within [line], as character indexes into the line.
(int, int) _cellSegment(String line, int col, int columnCount) {
  final c = _clampInt(col, 0, columnCount - 1);
  final pipes = _pipePositions(line);
  final startsOuter = line.trim().startsWith('|');
  int s, e;
  if (startsOuter) {
    s = c < pipes.length ? pipes[c] + 1 : line.length;
    e = c + 1 < pipes.length ? pipes[c + 1] : line.length;
  } else {
    s = c == 0 ? 0 : (c - 1 < pipes.length ? pipes[c - 1] + 1 : line.length);
    e = c < pipes.length ? pipes[c] : line.length;
  }
  s = _clampInt(s, 0, line.length);
  e = _clampInt(e, 0, line.length);
  if (e < s) e = s;
  return (s, e);
}

bool _isBlank(String c) => c == ' ' || c == '\t';

/// Trims padding spaces off [_cellSegment]; the selectable cell content.
(int, int) _trimmedCell(String line, int col, int columnCount) {
  final (s, e) = _cellSegment(line, col, columnCount);
  var cs = s;
  var ce = e;
  while (cs < ce && _isBlank(line[cs])) {
    cs++;
  }
  while (ce > cs && _isBlank(line[ce - 1])) {
    ce--;
  }
  return (cs, ce);
}

/// Which column of [line] holds [offsetInLine].
int _columnAt(String line, int offsetInLine, int columnCount) {
  for (var col = 0; col < columnCount; col++) {
    final (_, e) = _cellSegment(line, col, columnCount);
    if (offsetInLine <= e) return col;
  }
  return columnCount - 1;
}

/// Logical `(row, col)` of [offset] inside [table]. The delimiter line maps
/// to the header row so every Table-menu action stays available there.
({int row, int col}) _tableCellAt(
  String text,
  MarkdownTable table,
  int offset,
) {
  final off = _clampInt(offset, 0, text.length);
  final lines = text.split('\n');
  final starts = _lineStarts(lines);
  final lineIdx = _lineIndexAt(starts, off);
  final inLine = off - starts[lineIdx];
  final col = _columnAt(lines[lineIdx], inLine, table.columnCount);
  final int row;
  if (lineIdx <= table.delimiterLine) {
    row = 0;
  } else {
    row = lineIdx - table.startLine - 1;
  }
  return (row: _clampInt(row, 0, table.rows.length - 1), col: col);
}

/// Absolute line index in the document for logical [row] (header = 0).
int _lineOfRow(MarkdownTable table, int row) =>
    row == 0 ? table.startLine : table.startLine + row + 1;

/// Intra-cell caret drift preserved across structural edits.
int _offsetInCell(String text, MarkdownTable table, int offset, int col) {
  final lines = text.split('\n');
  final starts = _lineStarts(lines);
  final lineIdx = _lineIndexAt(starts, _clampInt(offset, 0, text.length));
  final line = lines[lineIdx];
  final (cs, ce) = _trimmedCell(line, col, table.columnCount);
  final abs = starts[lineIdx];
  final len = ce - cs;
  if (len <= 0) return 0;
  return _clampInt(offset - (abs + cs), 0, len);
}

String _replaceBlock(String text, MarkdownTable table, String block) =>
    text.replaceRange(table.startOffset, table.endOffset, block);

int _caretForCell(
  int blockStart,
  String block,
  List<List<String>> rows,
  int row,
  int col, [
  int offsetInCell = 0,
]) {
  final lines = block.split('\n');
  final starts = _lineStarts(lines);
  final lineIdx = row == 0 ? 0 : row + 1;
  final lineStart = blockStart + starts[lineIdx];
  final contentLen = _escapeCell(rows[row][col]).length;
  final drift = _clampInt(offsetInCell, 0, contentLen);
  return lineStart + _renderedCellStart(rows[row], col) + drift;
}

List<List<String>> _copyRows(List<List<String>> rows) =>
    [for (final r in rows) List<String>.of(r)];

// ---- insert ---------------------------------------------------------------

/// Inserts an empty [columns] × [bodyRows] table at [offset], keeping it on
/// its own lines (splitting the current line when needed, like Notepad).
/// The caret lands inside the first header cell.
TableEdit buildInsertTable(
  String text,
  int offset,
  int columns,
  int bodyRows,
) {
  final cols = _clampInt(columns, 1, kMaxTableColumns);
  final br = _clampInt(bodyRows, 1, kMaxTableBodyRows);
  final rows = <List<String>>[
    List<String>.filled(cols, ''),
    for (var i = 0; i < br; i++) List<String>.filled(cols, ''),
  ];
  final aligns = List<TableAlignment>.filled(cols, TableAlignment.none);
  final block = _renderBlock(rows, aligns);

  final off = _clampInt(offset, 0, text.length);
  final before = text.substring(0, off);
  final after = text.substring(off);
  final needPre = off > 0 && !before.endsWith('\n');
  final needPost = after.isNotEmpty && !after.startsWith('\n');

  final buf = StringBuffer(before);
  if (needPre) buf.write('\n');
  final blockStart = buf.length;
  buf.write(block);
  if (after.isNotEmpty && needPost) buf.write('\n');
  buf.write(after);
  return TableEdit.caret(buf.toString(), blockStart + 2);
}

// ---- rows -----------------------------------------------------------------

/// Inserts an empty row above/below the row holding [offset].
TableEdit? insertTableRow(String text, int offset, {required bool above}) {
  final table = findMarkdownTable(text, offset);
  if (table == null) return null;
  final pos = _tableCellAt(text, table, offset);
  final drift = _offsetInCell(text, table, offset, pos.col);
  final rows = _copyRows(table.rows);
  final at = above ? pos.row : pos.row + 1;
  rows.insert(at, List<String>.filled(table.columnCount, ''));
  final block = _renderBlock(rows, table.alignments);
  final newText = _replaceBlock(text, table, block);
  final caretRow = above ? pos.row + 1 : pos.row;
  return TableEdit.caret(
    newText,
    _caretForCell(table.startOffset, block, rows, caretRow, pos.col, drift),
  );
}

/// Deletes the row holding [offset]. Deleting the last remaining row removes
/// the whole table; deleting the header promotes the first body row.
TableEdit? deleteTableRow(String text, int offset) {
  final table = findMarkdownTable(text, offset);
  if (table == null) return null;
  if (table.rows.length <= 1) return deleteMarkdownTable(text, offset);
  final pos = _tableCellAt(text, table, offset);
  final rows = _copyRows(table.rows)..removeAt(pos.row);
  final block = _renderBlock(rows, table.alignments);
  final newText = _replaceBlock(text, table, block);
  final caretRow = _clampInt(pos.row, 0, rows.length - 1);
  final caretCol = _clampInt(pos.col, 0, table.columnCount - 1);
  return TableEdit.caret(
    newText,
    _caretForCell(table.startOffset, block, rows, caretRow, caretCol),
  );
}

// ---- columns --------------------------------------------------------------

/// Inserts an empty column to the left/right of the column holding [offset].
TableEdit? insertTableColumn(
  String text,
  int offset, {
  required bool before,
}) {
  final table = findMarkdownTable(text, offset);
  if (table == null) return null;
  if (table.columnCount >= kMaxTableColumns) return null;
  final pos = _tableCellAt(text, table, offset);
  final drift = _offsetInCell(text, table, offset, pos.col);
  final rows = _copyRows(table.rows);
  final at = before ? pos.col : pos.col + 1;
  for (final row in rows) {
    row.insert(at, '');
  }
  final aligns = List<TableAlignment>.of(table.alignments)
    ..insert(at, TableAlignment.none);
  final block = _renderBlock(rows, aligns);
  final newText = _replaceBlock(text, table, block);
  return TableEdit.caret(
    newText,
    _caretForCell(
      table.startOffset,
      block,
      rows,
      pos.row,
      before ? pos.col + 1 : pos.col,
      drift,
    ),
  );
}

/// Deletes the column holding [offset]. Deleting the last column removes the
/// whole table.
TableEdit? deleteTableColumn(String text, int offset) {
  final table = findMarkdownTable(text, offset);
  if (table == null) return null;
  if (table.columnCount <= 1) return deleteMarkdownTable(text, offset);
  final pos = _tableCellAt(text, table, offset);
  final rows = _copyRows(table.rows);
  for (final row in rows) {
    row.removeAt(pos.col);
  }
  final aligns = List<TableAlignment>.of(table.alignments)
    ..removeAt(pos.col);
  final block = _renderBlock(rows, aligns);
  final newText = _replaceBlock(text, table, block);
  final caretCol = _clampInt(pos.col, 0, table.columnCount - 2);
  return TableEdit.caret(
    newText,
    _caretForCell(table.startOffset, block, rows, pos.row, caretCol),
  );
}

// ---- delete / select / format ---------------------------------------------

/// Removes the whole table surrounding [offset], consuming one adjacent
/// newline so no stray blank lines are left behind.
TableEdit? deleteMarkdownTable(String text, int offset) {
  final table = findMarkdownTable(text, offset);
  if (table == null) return null;
  final s = table.startOffset;
  final e = table.endOffset;
  if (e < text.length && text[e] == '\n') {
    return TableEdit.caret(text.replaceRange(s, e + 1, ''), s);
  }
  if (s > 0 && text[s - 1] == '\n') {
    return TableEdit.caret(text.replaceRange(s - 1, e, ''), s - 1);
  }
  return TableEdit.caret(text.replaceRange(s, e, ''), s);
}

/// Selects the full row holding [offset] (Notepad's Select > Row).
TableEdit? selectTableRow(String text, int offset) {
  final table = findMarkdownTable(text, offset);
  if (table == null) return null;
  final pos = _tableCellAt(text, table, offset);
  final lines = text.split('\n');
  final starts = _lineStarts(lines);
  final lineIdx = _lineOfRow(table, pos.row);
  return TableEdit.range(
    text,
    starts[lineIdx],
    starts[lineIdx] + lines[lineIdx].length,
  );
}

/// Selects the whole table surrounding [offset] (Notepad's Select > Table).
TableEdit? selectMarkdownTable(String text, int offset) {
  final table = findMarkdownTable(text, offset);
  if (table == null) return null;
  return TableEdit.range(text, table.startOffset, table.endOffset);
}

/// Pads every cell so pipes line up (the text-mode equivalent of Notepad's
/// "Fit columns" — it aligns source columns instead of pixels).
TableEdit? formatMarkdownTable(String text, int offset) {
  final table = findMarkdownTable(text, offset);
  if (table == null) return null;
  final pos = _tableCellAt(text, table, offset);
  final drift = _offsetInCell(text, table, offset, pos.col);
  final block = _renderPaddedBlock(table.rows, table.alignments);
  final newText = _replaceBlock(text, table, block);
  // Recompute the caret from padded widths (on escaped cells, matching the
  // renderer above).
  final cols = table.columnCount;
  final escaped = _escapedRows(table.rows);
  final widths = _paddedWidths(escaped, cols);
  final lines = block.split('\n');
  final starts = _lineStarts(lines);
  final lineIdx = pos.row == 0 ? 0 : pos.row + 1;
  var cellStart = starts[lineIdx] + 2;
  for (var j = 0; j < pos.col; j++) {
    cellStart += widths[j] + 3;
  }
  final caret = table.startOffset +
      cellStart +
      _clampInt(drift, 0, escaped[pos.row][pos.col].length);
  return TableEdit.caret(newText, caret);
}

// ---- keyboard navigation --------------------------------------------------

/// Moves to the next (or with [backwards], previous) cell, selecting a
/// non-empty cell's content like Word/Notepad. Tabbing past the last cell
/// appends a new body row — Shift+Tab on the first cell collapses the caret
/// to the start of the table. Returns null when [offset] is not in a table.
TableEdit? moveTableCell(String text, int offset, {required bool backwards}) {
  final table = findMarkdownTable(text, offset);
  if (table == null) return null;
  final pos = _tableCellAt(text, table, offset);
  final lastRow = table.rows.length - 1;
  final lastCol = table.columnCount - 1;

  if (!backwards && pos.row == lastRow && pos.col == lastCol) {
    final rows = _copyRows(table.rows)
      ..add(List<String>.filled(table.columnCount, ''));
    final block = _renderBlock(rows, table.alignments);
    final newText = _replaceBlock(text, table, block);
    return TableEdit.caret(
      newText,
      _caretForCell(table.startOffset, block, rows, lastRow + 1, 0),
    );
  }
  if (backwards && pos.row == 0 && pos.col == 0) {
    return TableEdit.caret(text, table.startOffset);
  }

  int row, col;
  if (backwards) {
    row = pos.col > 0 ? pos.row : pos.row - 1;
    col = pos.col > 0 ? pos.col - 1 : lastCol;
  } else {
    row = pos.col < lastCol ? pos.row : pos.row + 1;
    col = pos.col < lastCol ? pos.col + 1 : 0;
  }

  final lines = text.split('\n');
  final starts = _lineStarts(lines);
  final lineIdx = _lineOfRow(table, row);
  final line = lines[lineIdx];
  final (cs, ce) = _trimmedCell(line, col, table.columnCount);
  final abs = starts[lineIdx];
  if (ce > cs) return TableEdit.range(text, abs + cs, abs + ce);
  return TableEdit.caret(text, abs + cs);
}

/// Handles Enter inside a table: moves down one row in the same column
/// (appending a body row past the end). On an empty last body row it deletes
/// that row and exits the table onto the next line — mirroring how Enter on
/// an empty list item exits the list. Returns null outside tables.
TableEdit? moveTableDown(String text, int offset) {
  final table = findMarkdownTable(text, offset);
  if (table == null) return null;
  final pos = _tableCellAt(text, table, offset);
  final lastRow = table.rows.length - 1;

  if (pos.row == lastRow) {
    final isEmptyBodyRow =
        pos.row > 0 && table.rows[pos.row].every((c) => c.isEmpty);
    if (isEmptyBodyRow) {
      final rows = _copyRows(table.rows)..removeAt(pos.row);
      final block = _renderBlock(rows, table.alignments);
      var newText = _replaceBlock(text, table, block);
      final blockEnd = table.startOffset + block.length;
      if (blockEnd < newText.length) {
        // Step onto the line following the table.
        return TableEdit.caret(newText, blockEnd + 1);
      }
      newText = '$newText\n';
      return TableEdit.caret(newText, newText.length);
    }
    final rows = _copyRows(table.rows)
      ..add(List<String>.filled(table.columnCount, ''));
    final block = _renderBlock(rows, table.alignments);
    final newText = _replaceBlock(text, table, block);
    return TableEdit.caret(
      newText,
      _caretForCell(table.startOffset, block, rows, lastRow + 1, pos.col),
    );
  }

  final lines = text.split('\n');
  final starts = _lineStarts(lines);
  final lineIdx = _lineOfRow(table, pos.row + 1);
  final (cs, _) = _trimmedCell(lines[lineIdx], pos.col, table.columnCount);
  return TableEdit.caret(text, starts[lineIdx] + cs);
}
