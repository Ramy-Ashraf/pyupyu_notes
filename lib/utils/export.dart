import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/note.dart';
import '../widgets/drawing/stroke_render.dart';

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
