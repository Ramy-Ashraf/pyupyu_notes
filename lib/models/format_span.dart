import 'dart:math' as math;

/// Bitmask flags for rich-text formatting on a note's body.
class FormatFlags {
  static const int bold = 1;
  static const int italic = 2;
  static const int underline = 4;
  static const int strike = 8;
  static const int h1 = 16;
  static const int h2 = 32;
  static const int all = bold | italic | underline | strike | h1 | h2;
}

/// A half-open range [start, end) of characters sharing the same formatting.
class FormatSpan {
  const FormatSpan(this.start, this.end, this.flags);

  final int start;
  final int end;
  final int flags;

  bool get isEmpty => end <= start;
  bool has(int flag) => flags & flag != 0;

  @override
  bool operator ==(Object other) =>
      other is FormatSpan &&
      other.start == start &&
      other.end == end &&
      other.flags == flags;

  @override
  int get hashCode => Object.hash(start, end, flags);

  FormatSpan withFlag(int flag) => FormatSpan(start, end, flags | flag);
  FormatSpan withoutFlags(int mask) => FormatSpan(start, end, flags & ~mask);

  Map<String, dynamic> toJson() => {'s': start, 'e': end, 'f': flags};

  factory FormatSpan.fromJson(Map<String, dynamic> json) => FormatSpan(
        (json['s'] as num).toInt(),
        (json['e'] as num).toInt(),
        (json['f'] as num?)?.toInt() ?? 0,
      );
}

/// Sorts, drops empty/flagless spans, and merges adjacent duplicates.
List<FormatSpan> normalizeSpans(List<FormatSpan> spans) {
  final filtered = spans
      .where((s) => !s.isEmpty && s.flags != 0)
      .toList()
    ..sort((a, b) =>
        a.start != b.start ? a.start.compareTo(b.start) : a.end.compareTo(b.end));
  final out = <FormatSpan>[];
  for (final s in filtered) {
    if (out.isNotEmpty) {
      final last = out.last;
      if (s.start < last.end && last.flags != s.flags) {
        // Overlapping ranges with different flags: keep the first, trim later.
        if (s.end > last.end) {
          out.add(FormatSpan(last.end, s.end, s.flags));
        }
        continue;
      }
      if (s.start <= last.end && last.flags == s.flags) {
        out[out.length - 1] =
            FormatSpan(last.start, math.max(last.end, s.end), last.flags);
        continue;
      }
    }
    out.add(s);
  }
  return out;
}

/// Splits any span crossing [pos] into two so the position becomes a boundary.
List<FormatSpan> splitSpansAt(List<FormatSpan> spans, int pos) {
  final out = <FormatSpan>[];
  for (final s in spans) {
    if (pos > s.start && pos < s.end) {
      out
        ..add(FormatSpan(s.start, pos, s.flags))
        ..add(FormatSpan(pos, s.end, s.flags));
    } else {
      out.add(s);
    }
  }
  return out;
}

/// Maps formatting spans across an edit that replaced the region
/// [commonPrefix, oldLen - commonSuffix) of [oldText] with the middle of
/// [newText]. Inserted text at a span boundary stays unformatted; insertion
/// strictly inside a span extends it.
List<FormatSpan> adjustSpansForChange(
  List<FormatSpan> spans,
  String oldText,
  String newText,
) {
  if (oldText == newText) return spans;
  final minLen = math.min(oldText.length, newText.length);

  var p = 0;
  while (p < minLen && oldText[p] == newText[p]) {
    p++;
  }
  var sfx = 0;
  while (sfx < minLen - p &&
      oldText[oldText.length - 1 - sfx] == newText[newText.length - 1 - sfx]) {
    sfx++;
  }

  final delLen = oldText.length - p - sfx;
  final insLen = newText.length - p - sfx;
  if (delLen == 0 && insLen == 0) return spans;
  final delEnd = p + delLen;
  final delta = insLen - delLen;

  return normalizeSpans([
    for (final s in spans)
      (() {
        int ns;
        int ne;
        if (delLen > 0) {
          ns = s.start <= p ? s.start : (s.start >= delEnd ? s.start + delta : p);
          ne = s.end <= p ? s.end : (s.end >= delEnd ? s.end + delta : p);
        } else {
          // Pure insertion at p.
          if (p <= s.start) {
            ns = s.start + insLen;
            ne = s.end + insLen;
          } else if (p >= s.end) {
            ns = s.start;
            ne = s.end;
          } else {
            ns = s.start;
            ne = s.end + insLen;
          }
        }
        return FormatSpan(ns, ne, s.flags);
      })(),
  ]);
}
