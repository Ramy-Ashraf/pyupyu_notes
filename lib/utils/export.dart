import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/note.dart';
import '../models/stroke_item.dart';
import '../widgets/drawing/stroke_render.dart';
import 'markdown_table.dart';

String _safeName(String s) =>
    s.replaceAll(RegExp(r'[\\/:*?"<>|\r\n]'), '_').trim();

/// File-name base for exports; falls back when the title sanitizes to empty.
String _fileBase(String title) {
  final name = _safeName(title);
  return name.isEmpty ? 'note' : name;
}

String _stamp() {
  final d = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}${two(d.month)}${two(d.day)}-${two(d.hour)}${two(d.minute)}${two(d.second)}';
}

Future<Directory> _exportDir() async {
  final downloads = await getDownloadsDirectory();
  if (downloads != null) return downloads;
  return getApplicationSupportDirectory();
}

/// Writes the note's text to the Downloads folder. Returns the path, or
/// null when there is nothing to export.
Future<String?> exportNoteText(Note note) async {
  if (note.body.trim().isEmpty) return null;
  final dir = await _exportDir();
  final file = File(
    '${dir.path}${Platform.pathSeparator}'
    '${_fileBase(note.title)}-${_stamp()}.txt',
  );
  await file.writeAsString(note.body, flush: true);
  return file.path;
}

/// Writes the note as Markdown (body + tag footer + diagram placeholder).
Future<String?> exportNoteMarkdown(Note note) async {
  if (note.body.trim().isEmpty && note.strokes.isEmpty) return null;
  final dir = await _exportDir();
  final buf = StringBuffer(note.body);
  if (note.tags.isNotEmpty) {
    buf.write('\n\n---\n');
    buf.write(note.tags.map((t) => '#$t').join(' '));
    buf.write('\n');
  }
  if (note.strokes.isNotEmpty) {
    buf.write('\n\n![diagram](${_fileBase(note.title)}-diagram-${_stamp()}.png)\n');
  }
  final file = File(
    '${dir.path}${Platform.pathSeparator}'
    '${_fileBase(note.title)}-${_stamp()}.md',
  );
  await file.writeAsString(buf.toString(), flush: true);
  return file.path;
}

String _escapeHtml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// Writes a printable HTML file (open in a browser to print / save as PDF).
/// Markdown tables are converted to real HTML tables.
Future<String?> exportNoteHtml(Note note, {required Color background}) async {
  if (note.body.trim().isEmpty) return null;
  final dir = await _exportDir();
  final bg =
      '#${background.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
  final buf = StringBuffer()
    ..write('<!doctype html><html><head><meta charset="utf-8">'
        '<title>${_escapeHtml(note.title)}</title>'
        '<style>body{font-family:"Segoe UI",sans-serif;max-width:800px;'
        'margin:32px auto;padding:24px;background:$bg;}'
        'table{border-collapse:collapse;margin:12px 0;}'
        'td,th{border:1px solid #999;padding:6px 10px;}'
        'th{background:#00000010;}pre{white-space:pre-wrap;}</style>'
        '</head><body><h1>${_escapeHtml(note.title)}</h1>');
  final ranges = findMarkdownTables(note.body);
  if (ranges.isEmpty) {
    buf.write('<pre>${_escapeHtml(note.body)}</pre>');
  } else {
    final lines = note.body.split('\n');
    var cursor = 0;
    for (final r in ranges) {
      if (r.startLine > cursor) {
        buf.write(
            '<pre>${_escapeHtml(lines.sublist(cursor, r.startLine).join('\n'))}</pre>');
      }
      final table =
          TableData.parse(lines.sublist(r.startLine, r.endLine + 1));
      buf.write('<table><tr>');
      for (var c = 0; c < table.columnCount; c++) {
        buf.write('<th>${_escapeHtml(table.cellAt(0, c))}</th>');
      }
      buf.write('</tr>');
      for (var row = 1; row < table.rowCount; row++) {
        buf.write('<tr>');
        for (var c = 0; c < table.columnCount; c++) {
          buf.write('<td>${_escapeHtml(table.cellAt(row, c))}</td>');
        }
        buf.write('</tr>');
      }
      buf.write('</table>');
      cursor = r.endLine + 1;
    }
    if (cursor < lines.length) {
      buf.write('<pre>${_escapeHtml(lines.sublist(cursor).join('\n'))}</pre>');
    }
  }
  if (note.tags.isNotEmpty) {
    buf.write('<p><em>${note.tags.map((t) => '#$t').join(' ')}</em></p>');
  }
  buf.write('</body></html>');
  final file = File(
    '${dir.path}${Platform.pathSeparator}'
    '${_fileBase(note.title)}-${_stamp()}.html',
  );
  await file.writeAsString(buf.toString(), flush: true);
  return file.path;
}

/// Exports every Markdown table in the note as CSV (tables separated by a
/// blank line). Returns null when there are no tables.
Future<String?> exportTablesCsv(Note note) async {
  final ranges = findMarkdownTables(note.body);
  if (ranges.isEmpty) return null;
  final lines = note.body.split('\n');
  final buf = StringBuffer();
  String csvCell(String c) {
    if (c.contains(RegExp(r'[",\n]'))) {
      return '"${c.replaceAll('"', '""')}"';
    }
    return c;
  }

  for (var i = 0; i < ranges.length; i++) {
    if (i > 0) buf.write('\n');
    final table = TableData.parse(
        lines.sublist(ranges[i].startLine, ranges[i].endLine + 1));
    for (var r = 0; r < table.rowCount; r++) {
      buf.write([
        for (var c = 0; c < table.columnCount; c++)
          csvCell(table.cellAt(r, c)),
      ].join(','));
      buf.write('\n');
    }
  }
  final dir = await _exportDir();
  final file = File(
    '${dir.path}${Platform.pathSeparator}'
    '${_fileBase(note.title)}-tables-${_stamp()}.csv',
  );
  await file.writeAsString(buf.toString(), flush: true);
  return file.path;
}

/// Builds an SVG document for the diagram (vector export / clipboard).
String buildDiagramSvg(Note note,
    {Color background = const Color(0xFFFFFFFF)}) {
  final strokes = note.strokes;
  if (strokes.isEmpty) return '';
  var bounds = strokeBounds(strokes.first);
  for (final s in strokes.skip(1)) {
    bounds = bounds.expandToInclude(strokeBounds(s));
  }
  const pad = 16.0;
  final x0 = bounds.left - pad;
  final y0 = bounds.top - pad;
  final w = bounds.width + pad * 2;
  final h = bounds.height + pad * 2;
  String hex(int v) =>
      '#${v.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  final buf = StringBuffer()
    ..write('<svg xmlns="http://www.w3.org/2000/svg" '
        'width="${w.toStringAsFixed(1)}" height="${h.toStringAsFixed(1)}" '
        'viewBox="$x0 $y0 $w $h">');
  buf.write('<rect x="$x0" y="$y0" width="$w" height="$h" '
      'fill="${hex(background.toARGB32())}"/>');
  for (final s in strokes) {
    final color = hex(s.colorValue);
    final sw = s.width;
    final dash = s.dash == DashStyles.dashed
        ? ' stroke-dasharray="8 5"'
        : s.dash == DashStyles.dotted
            ? ' stroke-dasharray="1.5 5" stroke-linecap="round"'
            : '';
    final pts = s.points.map((p) => '${p.dx},${p.dy}').join(' ');
    switch (s.type) {
      case StrokeType.pen:
      case StrokeType.marker:
        final op = s.type == StrokeType.marker ? ' opacity="0.45"' : '';
        buf.write('<polyline points="$pts" fill="none" stroke="$color" '
            'stroke-width="$sw" stroke-linecap="round" '
            'stroke-linejoin="round"$dash$op/>');
      case StrokeType.line:
      case StrokeType.arrow:
        if (s.points.length >= 2) {
          final a = s.points[0];
          final b = s.points[1];
          buf.write('<line x1="${a.dx}" y1="${a.dy}" x2="${b.dx}" y2="${b.dy}" '
              'stroke="$color" stroke-width="$sw"$dash/>');
          if (s.type == StrokeType.arrow) {
            buf.write('<circle cx="${b.dx}" cy="${b.dy}" r="${sw * 1.2}" '
                'fill="$color"/>');
          }
        }
      case StrokeType.rectangle:
      case StrokeType.sticky:
        if (s.points.length >= 2) {
          final r = Rect.fromPoints(s.points[0], s.points[1]);
          final fill = s.type == StrokeType.sticky
              ? color
              : (s.filled ? color : 'none');
          final fillOp = s.type == StrokeType.sticky
              ? ' fill-opacity="0.25"'
              : (s.filled && s.fillStyle != FillStyles.solid
                  ? ' fill-opacity="0.15"'
                  : '');
          buf.write('<rect x="${r.left}" y="${r.top}" width="${r.width}" '
              'height="${r.height}" fill="$fill" stroke="$color" '
              'stroke-width="$sw"$dash$fillOp/>');
          if ((s.text ?? '').isNotEmpty) {
            buf.write('<text x="${r.left + 8}" y="${r.top + 20}" '
                'font-size="14" fill="$color">'
                '${_escapeHtml(s.text!).replaceAll('\n', '&#10;')}</text>');
          }
        }
      case StrokeType.ellipse:
        if (s.points.length >= 2) {
          final r = Rect.fromPoints(s.points[0], s.points[1]);
          buf.write('<ellipse cx="${r.center.dx}" cy="${r.center.dy}" '
              'rx="${r.width / 2}" ry="${r.height / 2}" '
              'fill="${s.filled ? color : 'none'}" stroke="$color" '
              'stroke-width="$sw"$dash/>');
        }
      case StrokeType.diamond:
        if (s.points.length >= 2) {
          final a = s.points[0];
          final b = s.points[1];
          final cx = (a.dx + b.dx) / 2;
          final cy = (a.dy + b.dy) / 2;
          buf.write('<polygon points="$cx,${a.dy} ${b.dx},$cy $cx,${b.dy} '
              '${a.dx},$cy" fill="${s.filled ? color : 'none'}" '
              'stroke="$color" stroke-width="$sw"$dash/>');
        }
      case StrokeType.text:
        if ((s.text ?? '').isNotEmpty) {
          final p = s.points.first;
          final esc = _escapeHtml(s.text!);
          buf.write('<text x="${p.dx}" y="${p.dy + s.width}" '
              'font-size="${s.width}" fill="$color" '
              'font-family="Segoe Print, cursive">$esc</text>');
        }
    }
  }
  buf.write('</svg>');
  return buf.toString();
}

/// Writes the diagram as `.svg` (vector). Null when the canvas is empty.
Future<String?> exportDiagramSvg(Note note,
    {required Color background}) async {
  final svg = buildDiagramSvg(note, background: background);
  if (svg.isEmpty) return null;
  final dir = await _exportDir();
  final file = File(
    '${dir.path}${Platform.pathSeparator}'
    '${_fileBase(note.title)}-diagram-${_stamp()}.svg',
  );
  await file.writeAsString(svg, flush: true);
  return file.path;
}

/// Copies the diagram SVG to the clipboard. Returns false when empty.
Future<bool> copyDiagramSvg(Note note, {required Color background}) async {
  final svg = buildDiagramSvg(note, background: background);
  if (svg.isEmpty) return false;
  await Clipboard.setData(ClipboardData(text: svg));
  return true;
}

/// Renders the note's diagram to a PNG (2x for crispness) and writes it to
/// the Downloads folder. Returns the path, or null when the canvas is empty.
Future<String?> exportDiagramPng(Note note, {required Color background}) async {
  if (note.strokes.isEmpty) return null;

  var bounds = strokeBounds(note.strokes.first);
  for (final s in note.strokes.skip(1)) {
    bounds = bounds.expandToInclude(strokeBounds(s));
  }
  const pad = 32.0;
  final w = math.max(bounds.width, 1) + pad * 2;
  final h = math.max(bounds.height, 1) + pad * 2;

  var scale = 2.0;
  const maxDim = 8000.0;
  if (w * scale > maxDim || h * scale > maxDim) {
    scale = math.min(maxDim / w, maxDim / h);
  }

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(scale, scale);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w, h),
    Paint()..color = background,
  );
  canvas.translate(pad - bounds.left, pad - bounds.top);
  for (final s in note.strokes) {
    paintStroke(canvas, s);
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (w * scale).round(),
    (h * scale).round(),
  );
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) return null;

  final dir = await _exportDir();
  final file = File(
    '${dir.path}${Platform.pathSeparator}'
    '${_fileBase(note.title)}-diagram-${_stamp()}.png',
  );
  await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  return file.path;
}
