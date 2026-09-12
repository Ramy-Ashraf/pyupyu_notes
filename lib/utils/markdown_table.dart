/// Pure model behind the Excel-style table blocks in text mode.
///
/// Tables are stored as GitHub-flavoured Markdown so notes stay portable
/// plain text (and export to `.txt` unchanged): a header row, a delimiter
/// row (`---`), then body rows:
///
/// ```text
/// | Name | Age |
/// | ---- | --- |
/// | Alex | 30  |
/// ```
///
/// [findMarkdownTables] locates every table block in a document, [TableData]
/// parses/serializes one block, and its row/column helpers implement the
/// editing operations exposed by the spreadsheet-style table widget.
///
/// This file is pure Dart (no Flutter dependency) so the logic is trivially
/// unit-testable.
library;

/// Hard limits for the insert-table dialog and the editing operations.
const int kMaxTableColumns = 20;
const int kMaxTableRows = 60;

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

// ---- cell parsing ----------------------------------------------------------

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

/// Whether [line] is a Markdown delimiter row (`| --- | :---: |`).
bool isDelimiterLine(String line) {
  if (!line.contains('|')) return false;
  final cells = splitTableCells(line);
  return cells.isNotEmpty && cells.every(_isDelimiterCell);
}

/// Whether [line] could belong to a table block (any non-empty pipe line).
bool isTableLine(String line) =>
    line.trim().isNotEmpty && line.contains('|');

// ---- block detection -------------------------------------------------------

/// A Markdown table block occupying document lines [startLine]..[endLine]
/// (0-based, inclusive).
class TableBlockRange {
  const TableBlockRange(this.startLine, this.endLine);

  final int startLine;
  final int endLine;
}

/// Finds every Markdown table block in [text].
///
/// A block is a header pipe-line followed by a delimiter row and then body
/// rows. Two tables written back to back are split at the second header
/// (a body row is never followed by a delimiter row), so each stays an
/// independent block.
List<TableBlockRange> findMarkdownTables(String text) {
  final lines = text.split('\n');
  final out = <TableBlockRange>[];
  var i = 0;
  while (i < lines.length - 1) {
    if (isTableLine(lines[i]) &&
        !isDelimiterLine(lines[i]) &&
        isDelimiterLine(lines[i + 1])) {
      var e = i + 1;
      while (e + 1 < lines.length &&
          isTableLine(lines[e + 1]) &&
          !isDelimiterLine(lines[e + 1]) &&
          // Stop before a header row of the next back-to-back table.
          !(e + 2 < lines.length && isDelimiterLine(lines[e + 2]))) {
        e++;
      }
      out.add(TableBlockRange(i, e));
      i = e + 1;
    } else {
      i++;
    }
  }
  return out;
}

// ---- table data ------------------------------------------------------------

/// An in-memory table: [rows] holds the header first (the Markdown delimiter
/// row is not kept as data; it is re-derived from [alignments] on save).
class TableData {
  TableData({required List<List<String>> rows, List<TableAlignment>? alignments})
      : rows = rows,
        alignments = alignments ?? _defaultAligns(rows) {
    _normalize();
  }

  /// Empty [columns] × [bodyRows] table (header row included).
  TableData.empty(int columns, int bodyRows)
      : this(
          rows: [
            for (var i = 0; i < bodyRows + 1; i++)
              List<String>.filled(columns, '', growable: true),
          ],
        );

  final List<List<String>> rows;
  final List<TableAlignment> alignments;

  int get rowCount => rows.length;
  int get columnCount => alignments.length;

  static List<TableAlignment> _defaultAligns(List<List<String>> rows) =>
      List<TableAlignment>.generate(
        rows.isEmpty ? 1 : rows.first.length,
        (_) => TableAlignment.none,
      );

  void _normalize() {
    final cols = alignments.length;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      while (row.length < cols) {
        row.add('');
      }
      if (row.length > cols) rows[i] = row.sublist(0, cols);
    }
  }

  String cellAt(int row, int col) =>
      rows[row][col.clamp(0, columnCount - 1)];

  void setCell(int row, int col, String value) {
    rows[row][col.clamp(0, columnCount - 1)] = value;
  }

  /// Inserts an empty row at [at] (0-based; header is row 0). Returns the new
  /// row index, or null at the row limit.
  int? insertRowAt(int at) {
    if (rows.length >= kMaxTableRows) return null;
    final idx = at.clamp(0, rows.length);
    rows.insert(idx, List<String>.filled(columnCount, '', growable: true));
    return idx;
  }

  /// Deletes the row at [at]. Deleting the last remaining row reports false
  /// (the caller removes the whole table instead).
  bool deleteRowAt(int at) {
    if (rows.length <= 1 || at < 0 || at >= rows.length) return false;
    rows.removeAt(at);
    return true;
  }

  /// Inserts an empty column at [at]. Returns the new column index, or null
  /// at the column limit.
  int? insertColumnAt(int at) {
    if (columnCount >= kMaxTableColumns) return null;
    final idx = at.clamp(0, columnCount);
    for (final row in rows) {
      row.insert(idx, '');
    }
    alignments.insert(idx, TableAlignment.none);
    return idx;
  }

  /// Deletes the column at [at]. Deleting the last column reports false.
  bool deleteColumnAt(int at) {
    if (columnCount <= 1 || at < 0 || at >= columnCount) return false;
    for (final row in rows) {
      row.removeAt(at);
    }
    alignments.removeAt(at);
    return true;
  }

  /// Parses the lines of one table block (header, delimiter, body…).
  static TableData parse(List<String> lines) {
    final header = splitTableCells(lines.first);
    final delimCells =
        lines.length > 1 ? splitTableCells(lines[1]) : <String>['---'];
    final cols = header.isEmpty ? 1 : header.length;
    final aligns = List<TableAlignment>.generate(
      cols,
      (i) => i < delimCells.length
          ? alignmentFromCell(delimCells[i])
          : TableAlignment.none,
    );
    final rows = <List<String>>[
      for (var i = 0; i < lines.length; i++)
        if (i != 1) splitTableCells(lines[i]),
    ];
    return TableData(rows: rows, alignments: aligns);
  }

  /// Serialized Markdown, padded so pipes line up in the plain-text view.
  String toMarkdown() {
    final escaped = [
      for (final r in rows) [for (final c in r) _escapeCell(c)],
    ];
    final widths = List<int>.filled(columnCount, 3);
    for (final row in escaped) {
      for (var j = 0; j < columnCount; j++) {
        if (row[j].length > widths[j]) widths[j] = row[j].length;
      }
    }
    String rowOf(List<String> cells) => '| ${[
          for (var j = 0; j < columnCount; j++) cells[j].padRight(widths[j]),
        ].join(' | ')} |';
    final buf = StringBuffer(rowOf(escaped.first));
    buf.write('\n| ${[
      for (var j = 0; j < columnCount; j++)
        _delimiterFor(alignments[j], widths[j]),
    ].join(' | ')} |');
    for (var i = 1; i < escaped.length; i++) {
      buf.write('\n${rowOf(escaped[i])}');
    }
    return buf.toString();
  }

  /// Spreadsheets label columns A, B … Z, AA …
  static String columnLetter(int index) {
    var n = index + 1;
    final out = StringBuffer();
    while (n > 0) {
      final rem = (n - 1) % 26;
      out.write(String.fromCharCode(0x41 + rem));
      n = (n - 1) ~/ 26;
    }
    return out.toString();
  }
}
