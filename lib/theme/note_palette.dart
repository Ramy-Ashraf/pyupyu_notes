import 'package:flutter/material.dart';

class NotePalette {
  const NotePalette({
    required this.bar,
    required this.body,
    required this.accent,
  });

  /// Stronger tone used for the note's top bar.
  final Color bar;

  /// Note background.
  final Color body;

  /// Accent used for icons/titles on the body.
  final Color accent;
}

/// Sticky-Notes-style palette: yellow, green, teal, blue, purple, pink,
/// gray, slate.
const List<NotePalette> notePalettes = [
  NotePalette(bar: Color(0xFFF6C244), body: Color(0xFFFBF0CE), accent: Color(0xFF8A6D1A)),
  NotePalette(bar: Color(0xFFA3D178), body: Color(0xFFE8F5DB), accent: Color(0xFF4F6F2E)),
  NotePalette(bar: Color(0xFF79D0BE), body: Color(0xFFDDF3EE), accent: Color(0xFF2E6E60)),
  NotePalette(bar: Color(0xFF86BCE8), body: Color(0xFFDFEDF9), accent: Color(0xFF2F5E86)),
  NotePalette(bar: Color(0xFFB39DE8), body: Color(0xFFECE5FA), accent: Color(0xFF5A4390)),
  NotePalette(bar: Color(0xFFEF9FBE), body: Color(0xFFFAE7EE), accent: Color(0xFF8E3D5C)),
  NotePalette(bar: Color(0xFFB7BDC7), body: Color(0xFFEDF0F4), accent: Color(0xFF565D69)),
  NotePalette(bar: Color(0xFF98A2B3), body: Color(0xFFE3E7EC), accent: Color(0xFF3F4650)),
];

NotePalette paletteFor(int index, bool dark) {
  var i = index;
  if (i < 0 || i >= notePalettes.length) i = 0;
  final p = notePalettes[i];
  if (!dark) return p;
  return NotePalette(
    bar: Color.lerp(p.bar, const Color(0xFF2F2F2F), 0.70)!,
    body: Color.lerp(p.body, const Color(0xFF262626), 0.82)!,
    accent: Color.lerp(p.accent, const Color(0xFFE4E4E4), 0.60)!,
  );
}

Color noteTextColor(bool dark) =>
    dark ? const Color(0xFFECECEC) : const Color(0xFF262626);
