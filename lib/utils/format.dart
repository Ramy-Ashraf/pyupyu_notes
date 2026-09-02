String _hm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Short label for list cards: "14:32", "Yesterday" or "29/8/2026".
String formatNoteDate(DateTime d) {
  final now = DateTime.now();
  if (_sameDay(d, now)) return _hm(d);
  final yesterday = now.subtract(const Duration(days: 1));
  if (_sameDay(d, yesterday)) return 'Yesterday';
  return '${d.day}/${d.month}/${d.year}';
}

/// "Edited 14:32" style label for the editor top bar.
String formatEdited(DateTime d) {
  final now = DateTime.now();
  if (_sameDay(d, now)) return 'Edited ${_hm(d)}';
  final yesterday = now.subtract(const Duration(days: 1));
  if (_sameDay(d, yesterday)) return 'Edited yesterday ${_hm(d)}';
  return 'Edited ${d.day}/${d.month}/${d.year} ${_hm(d)}';
}
