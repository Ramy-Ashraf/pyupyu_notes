import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/format_span.dart';
import '../utils/markdown_table.dart' as mdtable;

/// A TextEditingController that carries bold/italic/underline/strikethrough
/// formatting ranges, keeps them aligned across edits, renders them via
/// [buildTextSpan] (including the IME composing underline), and provides
/// checklist / bullet-list behaviors. Smart Enter continuation lives in the
/// change listener so it works no matter how the newline arrived (keyboard,
/// IME, or programmatic).
class FormatTextController extends TextEditingController {
  FormatTextController({super.text, List<FormatSpan>? formats})
      : _formats = normalizeSpans(formats ?? const []) {
    _prev = value;
    addListener(_handleValueChanged);
  }

  List<FormatSpan> _formats;
  late TextEditingValue _prev;
  bool _suppress = false;

  /// Invoked after any user-visible change (text or formatting).
  void Function()? onEdited;

  List<FormatSpan> get formats => List.unmodifiable(_formats);

  // ---- change tracking ----------------------------------------------------

  void _handleValueChanged() {
    if (_suppress) return;
    final oldV = _prev;
    final newV = value;
    _prev = newV;
    if (oldV.text == newV.text) return;
    _formats = adjustSpansForChange(_formats, oldV.text, newV.text);
    if (!_maybeSmartNewline(oldV, newV)) {
      _renumberLists();
      onEdited?.call();
    }
    // If the smart newline rewrote the value, the nested listener pass
    // adjusts spans, renumbers and notifies [onEdited] itself.
  }

  /// Replaces the whole content (used when the note changes externally).
  void replaceAll(String text, List<FormatSpan> formats) {
    _suppress = true;
    _formats = normalizeSpans(formats);
    value = value.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange.empty,
    );
    _prev = value;
    _suppress = false;
    onEdited?.call();
  }

  // ---- formatting ---------------------------------------------------------

  void toggleFormat(int flag) {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final s = math.min(sel.start, sel.end);
    final e = math.max(sel.start, sel.end);
    if (s >= e || e > text.length) return;

    var spans = List<FormatSpan>.of(_formats);
    for (final pos in [s, e]) {
      spans = splitSpansAt(spans, pos);
    }
    spans.sort((a, b) => a.start.compareTo(b.start));
    final covered = spans
        .where((sp) => !sp.isEmpty && sp.start >= s && sp.end <= e)
        .toList();
    final allHave = covered.isNotEmpty && covered.every((sp) => sp.has(flag));

    final out = <FormatSpan>[];
    var cursor = s;
    for (final sp in spans) {
      if (sp.end <= s || sp.start >= e) {
        out.add(sp);
        continue;
      }
      if (sp.start > cursor) {
        out.add(FormatSpan(cursor, sp.start, allHave ? 0 : flag));
      }
      out.add(allHave ? sp.withoutFlags(flag) : sp.withFlag(flag));
      cursor = sp.end;
    }
    if (cursor < e) {
      out.add(FormatSpan(cursor, e, allHave ? 0 : flag));
    }
    _formats = normalizeSpans(out);
    onEdited?.call();
  }

  void clearFormats() {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final s = math.min(sel.start, sel.end);
    final e = math.max(sel.start, sel.end);
    if (s >= e || e > text.length) return;

    var spans = List<FormatSpan>.of(_formats);
    for (final pos in [s, e]) {
      spans = splitSpansAt(spans, pos);
    }
    _formats = normalizeSpans([
      for (final sp in spans)
        (sp.start >= s && sp.end <= e)
            ? sp.withoutFlags(FormatFlags.all)
            : sp,
    ]);
    onEdited?.call();
  }

  /// Whether every character in the current selection carries [flag].
  bool isActive(int flag) {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) return false;
    final s = math.min(sel.start, sel.end);
    final e = math.max(sel.start, sel.end);
    for (var i = s; i < e; i++) {
      if (!_charHas(i, flag)) return false;
    }
    return true;
  }

  bool _charHas(int pos, int flag) {
    for (final sp in _formats) {
      if (sp.start > pos) break;
      if (pos >= sp.start && pos < sp.end) return sp.has(flag);
    }
    return false;
  }

  // ---- lists --------------------------------------------------------------

  static const _listPrefixes = ['☐ ', '☒ ', '- ', '* ', '• '];

  int _listStateOf(String line) {
    if (line.startsWith('☐ ')) return 1;
    if (line.startsWith('☒ ')) return 2;
    return 0;
  }

  /// Detects a bare newline typed at the end of a list line and continues
  /// it: list prefixes repeat (checked items continue unchecked), numbered
  /// items increment. Rewrites [value]; returns true when it did.
  bool _maybeSmartNewline(TextEditingValue oldV, TextEditingValue newV) {
    final oldText = oldV.text;
    final newText = newV.text;
    // Exactly one '\n' inserted, nothing replaced — derive pos from caret.
    if (newText.length != oldText.length + 1) return false;
    final sel = newV.selection;
    if (!sel.isValid || !sel.isCollapsed) return false;
    final pos = sel.baseOffset - 1;
    if (pos < 0 || pos >= newText.length) return false;
    if (newText.codeUnitAt(pos) != 0x0A) return false;
    if (pos > oldText.length) return false;
    if (newText.substring(0, pos) != oldText.substring(0, pos)) return false;
    if (newText.substring(pos + 1) != oldText.substring(pos)) return false;

    final lineStart = pos == 0 ? 0 : newText.lastIndexOf('\n', pos - 1) + 1;
    final lineToCaret = newText.substring(lineStart, pos);

    String? prefix;
    for (final pfx in _listPrefixes) {
      if (lineToCaret.startsWith(pfx)) {
        prefix = pfx;
        break;
      }
    }
    if (prefix == null) {
      // Numbered list: "3. item" continues as "4. ", an empty "3. " exits.
      final m = RegExp(r'^(\d+)([.)]) (.*)$').firstMatch(lineToCaret);
      if (m == null) return false;
      final n = int.parse(m.group(1)!);
      final delim = m.group(2)!;
      if (m.group(3)!.isEmpty) {
        final from = lineStart == 0 ? 0 : lineStart - 1;
        value = newV.copyWith(
          text: newText.replaceRange(from, pos + 1, ''),
          selection: TextSelection.collapsed(offset: from),
          composing: TextRange.empty,
        );
        return true;
      }
      final next = '${n + 1}$delim ';
      value = newV.copyWith(
        text: newText.replaceRange(pos + 1, pos + 1, next),
        selection: TextSelection.collapsed(offset: pos + 1 + next.length),
        composing: TextRange.empty,
      );
      return true;
    }

    if (lineToCaret == prefix) {
      // Enter on an empty item: remove the whole item instead.
      final from = lineStart == 0 ? 0 : lineStart - 1;
      value = newV.copyWith(
        text: newText.replaceRange(from, pos + 1, ''),
        selection: TextSelection.collapsed(offset: from),
        composing: TextRange.empty,
      );
    } else {
      final next = prefix == '☒ ' ? '☐ ' : prefix;
      value = newV.copyWith(
        text: newText.replaceRange(pos + 1, pos + 1, next),
        selection: TextSelection.collapsed(offset: pos + 1 + next.length),
        composing: TextRange.empty,
      );
    }
    return true;
  }

  /// Renumbers consecutive numbered-list runs (of 2+ lines) so entries
  /// count 1, 2, 3… Runs on every text change; a no-op when the numbers
  /// are already correct, and skipped during IME composition. Lone
  /// numbered lines (a single "3. …") are left untouched.
  void _renumberLists() {
    final composing = value.composing;
    if (composing.isValid && !composing.isCollapsed) return;
    final t = text;
    if (t.isEmpty) return;
    final re = RegExp(r'^(\d+)([.)]) ');
    final oldLines = t.split('\n');
    final newLines = List<String>.of(oldLines);
    var changed = false;
    var runStart = -1;
    var delim = '.';
    for (var i = 0; i <= oldLines.length; i++) {
      final m = i < oldLines.length ? re.firstMatch(oldLines[i]) : null;
      if (m != null && runStart == -1) {
        runStart = i;
        delim = m.group(2)!;
      }
      if (m == null && runStart != -1) {
        if (i - runStart >= 2) {
          for (var k = runStart; k < i; k++) {
            final expected = '${k - runStart + 1}$delim ';
            if (!newLines[k].startsWith(expected)) {
              newLines[k] = newLines[k].replaceFirst(re, expected);
              changed = true;
            }
          }
        }
        runStart = -1;
      }
    }
    if (!changed) return;
    final newText = newLines.join('\n');

    int mapOffset(int off) {
      if (off < 0) off = t.length;
      var line = 0;
      var lineStart = 0;
      while (line < oldLines.length &&
          lineStart + oldLines[line].length + 1 <= off) {
        lineStart += oldLines[line].length + 1;
        line++;
      }
      var delta = 0;
      for (var i = 0; i < line && i < newLines.length; i++) {
        delta += newLines[i].length - oldLines[i].length;
      }
      return (off + delta).clamp(0, newText.length);
    }

    final sel = value.selection;
    value = value.copyWith(
      text: newText,
      selection: TextSelection(
        baseOffset: mapOffset(sel.baseOffset),
        extentOffset: mapOffset(sel.extentOffset),
      ),
      composing: TextRange.empty,
    );
  }

  /// Cycles the selected lines through: plain → unchecked ☐ → checked ☒ →
  /// plain. Bullets ("- ", "• ") convert to checkboxes.
  void toggleChecklist() {
    final sel = selection;
    if (!sel.isValid || text.isEmpty) return;
    final t = text;
    final s = math.min(sel.start, sel.end);
    final e = math.max(sel.start, sel.end);
    final blockStart = s == 0 ? 0 : t.lastIndexOf('\n', s - 1) + 1;
    var blockEnd = t.indexOf('\n', e);
    if (blockEnd == -1) blockEnd = t.length;

    final lines = t.substring(blockStart, blockEnd).split('\n');
    final states = lines.map(_listStateOf).toList();
    final action = states.every((st) => st == 2)
        ? 2 // remove
        : states.every((st) => st == 1)
            ? 1 // check
            : 0; // add / normalize to unchecked

    String convert(String line) {
      if (action == 2) return line.substring(2);
      if (action == 1) return '☒ ${line.substring(2)}';
      var rest = _listStateOf(line) == 0 ? line : line.substring(2);
      for (final b in const ['• ', '- ', '* ']) {
        if (rest.startsWith(b)) {
          rest = rest.substring(b.length);
          break;
        }
      }
      return '☐ $rest';
    }

    final newBlock = lines.map(convert).join('\n');
    value = value.copyWith(
      text: t.replaceRange(blockStart, blockEnd, newBlock),
      selection: TextSelection(
        baseOffset: blockStart,
        extentOffset: blockStart + newBlock.length,
      ),
      composing: TextRange.empty,
    );
  }

  /// Toggles "- " bullets on the selected lines, converting checkboxes and
  /// other bullet markers along the way.
  void toggleBulletList() {
    final sel = selection;
    if (!sel.isValid || text.isEmpty) return;
    final t = text;
    final s = math.min(sel.start, sel.end);
    final e = math.max(sel.start, sel.end);
    final blockStart = s == 0 ? 0 : t.lastIndexOf('\n', s - 1) + 1;
    var blockEnd = t.indexOf('\n', e);
    if (blockEnd == -1) blockEnd = t.length;

    final lines = t.substring(blockStart, blockEnd).split('\n');
    final remove = lines.every((l) => l.startsWith('- '));

    String convert(String line) {
      var rest = line;
      for (final pfx in _listPrefixes) {
        if (rest.startsWith(pfx)) {
          rest = rest.substring(pfx.length);
          break;
        }
      }
      return remove ? rest : '- $rest';
    }

    final newBlock = lines.map(convert).join('\n');
    value = value.copyWith(
      text: t.replaceRange(blockStart, blockEnd, newBlock),
      selection: TextSelection(
        baseOffset: blockStart,
        extentOffset: blockStart + newBlock.length,
      ),
      composing: TextRange.empty,
    );
  }

  /// Toggles numbered lists ("1. ", "2. ", …) on the selected lines,
  /// converting other list markers along the way. Empty lines are left
  /// bare and not counted.
  void toggleNumberedList() {
    final sel = selection;
    if (!sel.isValid || text.isEmpty) return;
    final t = text;
    final s = math.min(sel.start, sel.end);
    final e = math.max(sel.start, sel.end);
    final blockStart = s == 0 ? 0 : t.lastIndexOf('\n', s - 1) + 1;
    var blockEnd = t.indexOf('\n', e);
    if (blockEnd == -1) blockEnd = t.length;

    final lines = t.substring(blockStart, blockEnd).split('\n');
    final numRe = RegExp(r'^\d+[.)] ');
    final nonEmpty = lines.where((l) => l.trim().isNotEmpty);
    final remove = nonEmpty.isNotEmpty && nonEmpty.every(numRe.hasMatch);

    var n = 0;
    final newLines = lines.map((line) {
      if (remove) return line.replaceFirst(numRe, '');
      var rest = line;
      for (final pfx in _listPrefixes) {
        if (rest.startsWith(pfx)) {
          rest = rest.substring(pfx.length);
          break;
        }
      }
      final num = numRe.firstMatch(rest);
      if (num != null) rest = rest.substring(num.end);
      if (rest.trim().isEmpty) return rest;
      n++;
      return '$n. $rest';
    }).toList();

    final newBlock = newLines.join('\n');
    value = value.copyWith(
      text: t.replaceRange(blockStart, blockEnd, newBlock),
      selection: TextSelection(
        baseOffset: blockStart,
        extentOffset: blockStart + newBlock.length,
      ),
      composing: TextRange.empty,
    );
  }

  // ---- tables (Notepad-style Markdown pipe tables) ------------------------

  int _caret() {
    if (!selection.isValid) return text.length;
    final o = selection.extentOffset;
    return o < 0 ? 0 : (o > text.length ? text.length : o);
  }

  void _applyTableEdit(mdtable.TableEdit edit) {
    int clamp(int v) {
      if (v < 0) return 0;
      return v > edit.text.length ? edit.text.length : v;
    }
    value = value.copyWith(
      text: edit.text,
      selection: TextSelection(
        baseOffset: clamp(edit.baseOffset),
        extentOffset: clamp(edit.extentOffset),
      ),
      composing: TextRange.empty,
    );
  }

  /// The Markdown table surrounding the caret, if any.
  mdtable.MarkdownTable? currentTable() =>
      mdtable.findMarkdownTable(text, _caret());

  /// Whether the caret sits inside a Markdown table (drives the Table
  /// toolbar button and Tab/Enter interception).
  bool get isInTable =>
      selection.isValid && mdtable.isInMarkdownTable(text, _caret());

  /// Inserts an empty [columns] × [bodyRows] table at the caret (header row
  /// included automatically) and moves the caret into its first cell.
  void insertTable(int columns, int bodyRows) {
    _applyTableEdit(mdtable.buildInsertTable(text, _caret(), columns, bodyRows));
  }

  void insertTableRowAbove() {
    final edit = mdtable.insertTableRow(text, _caret(), above: true);
    if (edit != null) _applyTableEdit(edit);
  }

  void insertTableRowBelow() {
    final edit = mdtable.insertTableRow(text, _caret(), above: false);
    if (edit != null) _applyTableEdit(edit);
  }

  void insertTableColumnLeft() {
    final edit = mdtable.insertTableColumn(text, _caret(), before: true);
    if (edit != null) _applyTableEdit(edit);
  }

  void insertTableColumnRight() {
    final edit = mdtable.insertTableColumn(text, _caret(), before: false);
    if (edit != null) _applyTableEdit(edit);
  }

  void deleteTableRow() {
    final edit = mdtable.deleteTableRow(text, _caret());
    if (edit != null) _applyTableEdit(edit);
  }

  void deleteTableColumn() {
    final edit = mdtable.deleteTableColumn(text, _caret());
    if (edit != null) _applyTableEdit(edit);
  }

  void deleteTable() {
    final edit = mdtable.deleteMarkdownTable(text, _caret());
    if (edit != null) _applyTableEdit(edit);
  }

  /// Pads cells so pipes line up (text-mode "fit columns").
  void formatTable() {
    final edit = mdtable.formatMarkdownTable(text, _caret());
    if (edit != null) _applyTableEdit(edit);
  }

  /// Selects the row holding the caret (Notepad's Select > Row).
  void selectTableRow() {
    final edit = mdtable.selectTableRow(text, _caret());
    if (edit != null) _applyTableEdit(edit);
  }

  /// Selects the whole table (Notepad's Select > Table).
  void selectTable() {
    final edit = mdtable.selectMarkdownTable(text, _caret());
    if (edit != null) _applyTableEdit(edit);
  }

  /// Tab / Shift+Tab cell navigation. Returns true when the key was consumed
  /// (caret inside a table); Tab past the last cell appends a new body row.
  bool handleTableTab({required bool backwards}) {
    final edit = mdtable.moveTableCell(text, _caret(), backwards: backwards);
    if (edit == null) return false;
    _applyTableEdit(edit);
    return true;
  }

  /// Enter inside a table moves down one row (appending past the end, or
  /// exiting from an empty last row). Returns true when consumed.
  bool handleTableEnter() {
    final edit = mdtable.moveTableDown(text, _caret());
    if (edit == null) return false;
    _applyTableEdit(edit);
    return true;
  }

  // ---- rendering ----------------------------------------------------------

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final t = text;
    var composing = TextRange.empty;
    if (withComposing && value.composing.isValid && !value.composing.isCollapsed) {
      final cs = math.max(0, value.composing.start);
      final ce = math.min(t.length, value.composing.end);
      if (ce > cs) composing = TextRange(start: cs, end: ce);
    }
    if (_formats.isEmpty && composing == TextRange.empty) {
      return TextSpan(text: t, style: style);
    }

    // Split at every span and composing boundary, then style each segment.
    final cuts = <int>{0, t.length};
    for (final sp in _formats) {
      cuts
        ..add(math.max(0, math.min(sp.start, t.length)))
        ..add(math.max(0, math.min(sp.end, t.length)));
    }
    if (composing != TextRange.empty) {
      cuts
        ..add(composing.start)
        ..add(composing.end);
    }
    final points = cuts.toList()..sort();

    final children = <TextSpan>[];
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (b <= a) continue;
      var flags = 0;
      for (final sp in _formats) {
        if (sp.start <= a && sp.end >= b) flags |= sp.flags;
      }
      final inComposing =
          composing != TextRange.empty && a >= composing.start && b <= composing.end;
      final seg = _styleFor(flags, composing: inComposing);
      children.add(TextSpan(text: t.substring(a, b), style: seg));
    }
    return TextSpan(style: style, children: children);
  }

  TextStyle _styleFor(int flags, {bool composing = false}) {
    var s = const TextStyle();
    if (flags & FormatFlags.h1 != 0) {
      s = s.copyWith(fontSize: 20, fontWeight: FontWeight.w700, height: 1.3);
    } else if (flags & FormatFlags.h2 != 0) {
      s = s.copyWith(fontSize: 17, fontWeight: FontWeight.w600, height: 1.35);
    }
    if (flags & FormatFlags.bold != 0) {
      s = s.copyWith(fontWeight: FontWeight.w700);
    }
    if (flags & FormatFlags.italic != 0) {
      s = s.copyWith(fontStyle: FontStyle.italic);
    }
    final decorations = <TextDecoration>[];
    if (flags & FormatFlags.underline != 0 || composing) {
      decorations.add(TextDecoration.underline);
    }
    if (flags & FormatFlags.strike != 0) {
      decorations.add(TextDecoration.lineThrough);
    }
    if (decorations.isNotEmpty) {
      s = s.copyWith(decoration: TextDecoration.combine(decorations));
    }
    return s;
  }
}
