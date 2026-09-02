import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/format_span.dart';

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
    if (!_maybeContinueList(oldV, newV)) {
      onEdited?.call();
    }
    // If the list continuation rewrote the value, the nested listener pass
    // adjusted spans and notified [onEdited] itself.
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
  /// the list (or exits it on an empty item). Checked items continue as
  /// unchecked. Rewrites [value]; returns true when it did.
  bool _maybeContinueList(TextEditingValue oldV, TextEditingValue newV) {
    final oldText = oldV.text;
    final newText = newV.text;
    final minLen = math.min(oldText.length, newText.length);

    var p = 0;
    while (p < minLen && oldText[p] == newText[p]) {
      p++;
    }
    var sfx = 0;
    while (sfx < minLen - p &&
        oldText.codeUnitAt(oldText.length - 1 - sfx) ==
            newText.codeUnitAt(newText.length - 1 - sfx)) {
      sfx++;
    }
    // Exactly one '\n' inserted, nothing replaced.
    if (oldText.length - p - sfx != 0 || newText.length - p - sfx != 1) {
      return false;
    }
    final pos = p;
    if (newText[pos] != '\n') return false;
    final sel = newV.selection;
    if (!sel.isCollapsed || sel.baseOffset != pos + 1) return false;

    final lineStart = pos == 0 ? 0 : newText.lastIndexOf('\n', pos - 1) + 1;
    final lineToCaret = newText.substring(lineStart, pos);
    String? prefix;
    for (final pfx in _listPrefixes) {
      if (lineToCaret.startsWith(pfx)) {
        prefix = pfx;
        break;
      }
    }
    if (prefix == null) return false;

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
      children.add(TextSpan(
        text: t.substring(a, b),
        style: _styleFor(flags, composing: inComposing),
      ));
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
