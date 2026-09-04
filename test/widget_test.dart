import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Canvas, PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notes_app/controllers/format_text_controller.dart';
import 'package:notes_app/controllers/notes_controller.dart';
import 'package:notes_app/models/format_span.dart';
import 'package:notes_app/models/note.dart';
import 'package:notes_app/models/stroke_item.dart';
import 'package:notes_app/services/notes_store.dart';
import 'package:notes_app/utils/markdown_table.dart';
import 'package:notes_app/widgets/drawing/stroke_render.dart';

Note _note({
  String id = 'n1',
  String body = 'Title line\nsecond line',
  int colorIndex = 3,
  bool pinned = true,
  List<StrokeItem>? strokes,
  List<FormatSpan>? formats,
}) {
  final now = DateTime.now();
  return Note(
    id: id,
    body: body,
    colorIndex: colorIndex,
    pinned: pinned,
    createdAt: now,
    updatedAt: now,
    strokes: strokes,
    formats: formats,
  );
}

void main() {
  test('Note JSON round-trip preserves content', () {
    final note = _note(
      strokes: [
        StrokeItem(
          id: 's1',
          type: StrokeType.pen,
          points: const [Offset(0, 0), Offset(10, 12)],
          colorValue: 0xFF112233,
          width: 4,
        ),
        StrokeItem(
          id: 's2',
          type: StrokeType.rectangle,
          points: const [Offset(1, 1), Offset(50, 40)],
          colorValue: 0xFF445566,
          width: 2,
          filled: true,
        ),
        StrokeItem(
          id: 's3',
          type: StrokeType.text,
          points: const [Offset(5, 5)],
          colorValue: 0xFF000000,
          width: 18,
          text: 'Start',
        ),
        StrokeItem(
          id: 's4',
          type: StrokeType.diamond,
          points: const [Offset(0, 0), Offset(40, 30)],
          colorValue: 0xFF123456,
          width: 3,
          filled: true,
          fillStyle: FillStyles.crossHatch,
          dash: DashStyles.dashed,
          seed: 12345,
          angle: 0.5,
        ),
      ],
      formats: const [FormatSpan(0, 5, FormatFlags.bold)],
    );

    final restored = Note.fromJson(note.toJson());

    expect(restored.body, 'Title line\nsecond line');
    expect(restored.title, 'Title line');
    expect(restored.snippet, 'second line');
    expect(restored.strokes.length, 4);
    expect(restored.strokes[1].filled, isTrue);
    expect(restored.strokes[2].text, 'Start');
    expect(restored.strokes[3].type, StrokeType.diamond);
    expect(restored.strokes[3].fillStyle, FillStyles.crossHatch);
    expect(restored.strokes[3].dash, DashStyles.dashed);
    expect(restored.strokes[3].seed, 12345);
    expect(restored.strokes[3].angle, 0.5);
    expect(restored.formats.length, 1);
    expect(restored.formats[0].has(FormatFlags.bold), isTrue);
    expect(restored.hasDiagram, isTrue);
  });

  test('Checklist prefixes are stripped from titles', () {
    expect(_note(body: '☒ buy milk', pinned: false).title, 'buy milk');
  });

  test('Empty note falls back to default title', () {
    final note = _note(body: '   \n  ', pinned: false);
    expect(note.title, 'New note');
    expect(note.snippet, '');
    expect(note.hasDiagram, isFalse);
  });

  test('rough renderer paints every stroke type and style', () {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    for (var i = 0; i < StrokeType.values.length; i++) {
      final type = StrokeType.values[i];
      final isText = type == StrokeType.text;
      final isFreehand = type == StrokeType.pen || type == StrokeType.marker;
      final stroke = StrokeItem(
        id: 'r$i',
        type: type,
        points: isText ? const [Offset(0, 0)] : const [Offset(0, 0), Offset(60, 40)],
        colorValue: 0xFF222222,
        width: 3,
        filled: !isText && !isFreehand,
        fillStyle: FillStyles.crossHatch,
        dash: DashStyles.dashed,
        seed: i * 37 + 1,
        text: isText ? 'Hi\nThere' : null,
      );
      paintStroke(canvas, stroke);
      strokeHitTest(stroke, const Offset(30, 20), 4);
    }
    // Solid fill + dotted outline variants.
    paintStroke(
      canvas,
      StrokeItem(
        id: 'solid',
        type: StrokeType.rectangle,
        points: const [Offset(0, 0), Offset(50, 50)],
        colorValue: 0xFF000000,
        width: 4,
        filled: true,
        fillStyle: FillStyles.solid,
        dash: DashStyles.dotted,
        seed: 5,
      ),
    );
    // Rotated strokes render and hit-test in world space. The local top
    // edge midpoint (20, 0) rotates about the center (20, 10) onto a world
    // point that must hit, while the hollow center must miss.
    final rotated = StrokeItem(
      id: 'rot',
      type: StrokeType.rectangle,
      points: const [Offset(0, 0), Offset(40, 20)],
      colorValue: 0xFF000000,
      width: 2,
      seed: 9,
      angle: math.pi / 4,
    );
    paintStroke(canvas, rotated);
    final cos45 = math.cos(math.pi / 4);
    final worldEdge = Offset(
      20 + 0 * cos45 - (-10) * cos45,
      10 + 0 * cos45 + (-10) * cos45,
    );
    expect(strokeHitTest(rotated, worldEdge, 2), isTrue);
    expect(strokeHitTest(rotated, const Offset(20, 10), 2), isFalse);
    expect(strokeHitTest(rotated, const Offset(-30, 10), 2), isFalse);
    recorder.endRecording();
  });

  group('FormatTextController', () {
    test('toggleFormat applies bold to the selection', () {
      final c = FormatTextController(text: 'hello world');
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      c.toggleFormat(FormatFlags.bold);
      expect(c.formats.length, 1);
      expect(c.formats.first.start, 0);
      expect(c.formats.first.end, 5);
      expect(c.isActive(FormatFlags.bold), isTrue);

      c.toggleFormat(FormatFlags.bold);
      expect(c.formats, isEmpty);
    });

    test('spans shift when text is inserted before them', () {
      final c = FormatTextController(
        text: 'hello world',
        formats: const [FormatSpan(0, 5, FormatFlags.italic)],
      );
      c.value = const TextEditingValue(
        text: 'Xhello world',
        selection: TextSelection.collapsed(offset: 1),
      );
      expect(c.formats.single.start, 1);
      expect(c.formats.single.end, 6);
    });

    test('spans shrink when text inside them is deleted', () {
      final c = FormatTextController(
        text: 'abcdef',
        formats: const [FormatSpan(2, 5, FormatFlags.italic)],
      );
      c.value = const TextEditingValue(
        text: 'aef',
        selection: TextSelection.collapsed(offset: 1),
      );
      expect(c.formats.single.start, 1);
      expect(c.formats.single.end, 2);
    });

    test('typing a newline after a checklist item continues it', () {
      final c = FormatTextController(text: '☐ buy milk');
      c.selection = const TextSelection.collapsed(offset: 10);
      c.value = const TextEditingValue(
        text: '☐ buy milk\n',
        selection: TextSelection.collapsed(offset: 11),
      );
      expect(c.text, '☐ buy milk\n☐ ');
      expect(c.selection.baseOffset, 13);
    });

    test('Enter after a checked item starts an unchecked item', () {
      final c = FormatTextController(text: '☒ done');
      c.selection = const TextSelection.collapsed(offset: 6);
      c.value = const TextEditingValue(
        text: '☒ done\n',
        selection: TextSelection.collapsed(offset: 7),
      );
      expect(c.text, '☒ done\n☐ ');
    });

    test('Enter on an empty checklist item exits the list', () {
      final c = FormatTextController(text: '☐ buy milk\n☐ ');
      c.selection = const TextSelection.collapsed(offset: 13);
      c.value = const TextEditingValue(
        text: '☐ buy milk\n☐ \n',
        selection: TextSelection.collapsed(offset: 14),
      );
      expect(c.text, '☐ buy milk');
      expect(c.selection.baseOffset, 10);
    });

    test('Enter in plain text stays plain', () {
      final c = FormatTextController(text: 'hello');
      c.selection = const TextSelection.collapsed(offset: 5);
      c.value = const TextEditingValue(
        text: 'hello\n',
        selection: TextSelection.collapsed(offset: 6),
      );
      expect(c.text, 'hello\n');
      expect(c.selection.baseOffset, 6);
    });

    test('formatting survives a checklist continuation', () {
      final c = FormatTextController(
        text: '☐ buy milk',
        formats: const [FormatSpan(2, 10, FormatFlags.bold)],
      );
      c.selection = const TextSelection.collapsed(offset: 10);
      c.value = const TextEditingValue(
        text: '☐ buy milk\n',
        selection: TextSelection.collapsed(offset: 11),
      );
      expect(c.text, '☐ buy milk\n☐ ');
      expect(c.formats.single.start, 2);
      expect(c.formats.single.end, 10);
    });

    test('heading flags toggle and shift with edits', () {
      final c = FormatTextController(text: 'Title');
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      c.toggleFormat(FormatFlags.h1);
      expect(c.formats.single.flags, FormatFlags.h1);
      // Inserting inside the heading extends it.
      c.value = const TextEditingValue(
        text: 'Ti!tle',
        selection: TextSelection.collapsed(offset: 3),
      );
      expect(c.formats.single.start, 0);
      expect(c.formats.single.end, 6);
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 6);
      c.toggleFormat(FormatFlags.h1);
      expect(c.formats, isEmpty);
    });

    test('toggleChecklist cycles plain → unchecked → checked → plain', () {
      final c = FormatTextController(text: 'task one\ntask two');
      c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
      c.toggleChecklist();
      expect(c.text, '☐ task one\n☐ task two');
      c.toggleChecklist();
      expect(c.text, '☒ task one\n☒ task two');
      c.toggleChecklist();
      expect(c.text, 'task one\ntask two');
    });

    test('toggleChecklist converts bullets to checkboxes', () {
      final c = FormatTextController(text: '- first\n• second');
      c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
      c.toggleChecklist();
      expect(c.text, '☐ first\n☐ second');
    });

    test('toggleBulletList converts checkboxes to bullets and back', () {
      final c = FormatTextController(text: '☐ first\n☒ second\nplain');
      c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
      c.toggleBulletList();
      expect(c.text, '- first\n- second\n- plain');
      c.toggleBulletList();
      expect(c.text, 'first\nsecond\nplain');
    });

    test('numbered lists continue with the next number', () {
      final c = FormatTextController(text: '1. one');
      c.selection = const TextSelection.collapsed(offset: 6);
      c.value = const TextEditingValue(
        text: '1. one\n',
        selection: TextSelection.collapsed(offset: 7),
      );
      expect(c.text, '1. one\n2. ');
      expect(c.selection.baseOffset, 10);
    });

    test('Enter on an empty numbered item exits the list', () {
      final c = FormatTextController(text: '1. one\n2. ');
      c.selection = const TextSelection.collapsed(offset: 10);
      c.value = const TextEditingValue(
        text: '1. one\n2. \n',
        selection: TextSelection.collapsed(offset: 11),
      );
      expect(c.text, '1. one');
      expect(c.selection.baseOffset, 6);
    });

    test('numbered runs renumber after edits', () {
      final c = FormatTextController(text: '1. a\n2. b');
      c.selection = const TextSelection.collapsed(offset: 9);
      c.value = const TextEditingValue(
        text: '1. a\n5. bX',
        selection: TextSelection.collapsed(offset: 10),
      );
      expect(c.text, '1. a\n2. bX');
      expect(c.selection.baseOffset, 10);
    });

    test('a lone numbered line is left alone', () {
      final c = FormatTextController(text: '3. just a note');
      c.selection = const TextSelection.collapsed(offset: 14);
      c.value = const TextEditingValue(
        text: '3. just a note!',
        selection: TextSelection.collapsed(offset: 15),
      );
      expect(c.text, '3. just a note!');
    });

    test('toggleNumberedList converts and strips numbers', () {
      final c = FormatTextController(text: 'one\n\ntwo');
      c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
      c.toggleNumberedList();
      expect(c.text, '1. one\n\n2. two');
      c.toggleNumberedList();
      expect(c.text, 'one\n\ntwo');
    });

    test('toggleNumberedList converts bullets and checkboxes', () {
      final c = FormatTextController(text: '- a\n☐ b');
      c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
      c.toggleNumberedList();
      expect(c.text, '1. a\n2. b');
    });



    testWidgets('buildTextSpan merges format flags with the composing range',
        (tester) async {
      final c = FormatTextController(
        text: 'abcdef',
        formats: const [FormatSpan(0, 3, FormatFlags.bold)],
      );
      c.value =
          c.value.copyWith(composing: const TextRange(start: 2, end: 5));

      late final BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox();
          },
        ),
      ));

      final span = c.buildTextSpan(
        context: ctx,
        style: const TextStyle(),
        withComposing: true,
      );
      final children = span.children!;
      expect(children.length, 4); // [0,2) [2,3) [3,5) [5,6)

      final bold = children[0].style!;
      expect(bold.fontWeight, FontWeight.w700);
      expect(bold.decoration, isNull);

      final boldComposing = children[1].style!;
      expect(boldComposing.fontWeight, FontWeight.w700);
      expect(boldComposing.decoration, TextDecoration.underline);

      final composingOnly = children[2].style!;
      expect(composingOnly.fontWeight, isNull);
      expect(composingOnly.decoration, TextDecoration.underline);
    });
  });

  testWidgets('multi-line text label bounds cover every line',
      (tester) async {
    final s = StrokeItem(
      id: 't',
      type: StrokeType.text,
      points: const [Offset(0, 0)],
      colorValue: 0xFF000000,
      width: 18,
      text: 'One\nTwo\nThree',
    );
    final bounds = strokeBounds(s);
    expect(bounds.width, greaterThan(0));
    // Three lines at 18px with a 1.25 height factor are ~68px tall.
    expect(bounds.height, greaterThan(60));
  });

  group('Markdown tables (Notepad-style)', () {
    test('splitTableCells handles outer pipes and escapes', () {
      expect(splitTableCells('| Name | Age |'), ['Name', 'Age']);
      expect(splitTableCells('a | b'), ['a', 'b']);
      expect(splitTableCells('a \\| b | c'), ['a | b', 'c']);
    });

    test('plain text and lone pipe lines are not tables', () {
      expect(findMarkdownTable('hello', 2), isNull);
      expect(findMarkdownTable('a | b', 2), isNull);
      expect(isInMarkdownTable('just text', 4), isFalse);
    });

    test('insertTable creates a header, delimiter and body rows', () {
      final c = FormatTextController(text: '');
      c.selection = const TextSelection.collapsed(offset: 0);
      c.insertTable(2, 2);
      expect(c.text, '|  |  |\n| --- | --- |\n|  |  |\n|  |  |');
      expect(c.selection.baseOffset, 2);
      expect(c.isInTable, isTrue);
    });

    test('Tab moves to the next cell', () {
      final c = FormatTextController(text: '');
      c.selection = const TextSelection.collapsed(offset: 0);
      c.insertTable(2, 1);
      expect(c.handleTableTab(backwards: false), isTrue);
      expect(c.text, '|  |  |\n| --- | --- |\n|  |  |');
      expect(c.selection.baseOffset, 6);
    });

    test('Tab past the last cell appends a body row', () {
      final c = FormatTextController(text: '');
      c.selection = const TextSelection.collapsed(offset: 0);
      c.insertTable(1, 1);
      c.selection = TextSelection.collapsed(offset: c.text.length);
      expect(c.handleTableTab(backwards: false), isTrue);
      expect(c.text, '|  |\n| --- |\n|  |\n|  |');
      expect(c.selection.baseOffset, 20);
    });

    test('Enter on an empty last row exits the table', () {
      final c = FormatTextController(text: 'A\n|  |\n| --- |\n|  |\nB');
      c.selection = const TextSelection.collapsed(offset: 16);
      expect(c.handleTableEnter(), isTrue);
      expect(c.text, 'A\n|  |\n| --- |\nB');
      expect(c.selection.baseOffset, 15);
    });

    test('deleteTableColumn narrows the table', () {
      final c = FormatTextController(
        text: '| a | b |\n| --- | --- |\n| c | d |',
      );
      c.selection = const TextSelection.collapsed(offset: 2);
      c.deleteTableColumn();
      expect(c.text, '| b |\n| --- |\n| d |');
      expect(c.selection.baseOffset, 2);
    });

    test('formatTable aligns pipes', () {
      final c = FormatTextController(
        text: '| a | bb |\n| --- | --- |\n| ccc | d |',
      );
      c.selection = const TextSelection.collapsed(offset: 2);
      c.formatTable();
      expect(c.text, '| a   | bb  |\n| --- | --- |\n| ccc | d   |');
    });

    test('formatTable keeps escaped pipes intact', () {
      final c = FormatTextController(
        text: '| a\\|b | c |\n| --- | --- |\n| d | e |',
      );
      c.selection = const TextSelection.collapsed(offset: 2);
      c.formatTable();
      expect(c.text, '| a\\|b | c   |\n| ---- | --- |\n| d    | e   |');
    });

    test('deleteTable removes the block without stray blank lines', () {
      final c = FormatTextController(
        text: 'A\n|  |\n| --- |\n|  |\nB',
      );
      c.selection = const TextSelection.collapsed(offset: 5);
      c.deleteTable();
      expect(c.text, 'A\nB');
    });

    test('insertTableRowAbove keeps the caret in its cell', () {
      final c = FormatTextController(
        text: '| a | b |\n| --- | --- |\n| c | d |',
      );
      c.selection = const TextSelection.collapsed(offset: 2);
      c.insertTableRowAbove();
      expect(c.text, '|  |  |\n| --- | --- |\n| a | b |\n| c | d |');
      expect(c.selection.baseOffset, 24);
    });

    test('insertTableRowBelow appends under the current row', () {
      final c = FormatTextController(
        text: '| a | b |\n| --- | --- |\n| c | d |',
      );
      c.selection = const TextSelection.collapsed(offset: 26);
      c.insertTableRowBelow();
      expect(c.text, '| a | b |\n| --- | --- |\n| c | d |\n|  |  |');
      expect(c.selection.baseOffset, 26);
    });

    test('insertTableColumnRight widens every row', () {
      final c = FormatTextController(
        text: '| a | b |\n| --- | --- |\n| c | d |',
      );
      c.selection = const TextSelection.collapsed(offset: 2);
      c.insertTableColumnRight();
      expect(c.text, '| a |  | b |\n| --- | --- | --- |\n| c |  | d |');
      expect(c.selection.baseOffset, 2);
    });

    test('deleteTableRow removes the current row', () {
      final c = FormatTextController(text: '| a |\n| --- |\n| b |');
      c.selection = const TextSelection.collapsed(offset: 16);
      c.deleteTableRow();
      expect(c.text, '| a |\n| --- |');
      expect(c.selection.baseOffset, 2);
    });

    test('Tab selects a non-empty cell for quick replacement', () {
      final c = FormatTextController(
        text: '| ab | cd |\n| --- | --- |\n| ef | gh |',
      );
      c.selection = const TextSelection.collapsed(offset: 3);
      expect(c.handleTableTab(backwards: false), isTrue);
      expect(c.selection.baseOffset, 7);
      expect(c.selection.extentOffset, 9);
    });

    test('Enter moves down one row in the same column', () {
      final c = FormatTextController(
        text: '| a | b |\n| --- | --- |\n| c | d |',
      );
      c.selection = const TextSelection.collapsed(offset: 2);
      expect(c.handleTableEnter(), isTrue);
      expect(c.text, '| a | b |\n| --- | --- |\n| c | d |');
      expect(c.selection.baseOffset, 26);
    });

    test('Enter on the last row appends a body row', () {
      final c = FormatTextController(text: '| a |\n| --- |\n| b |');
      c.selection = const TextSelection.collapsed(offset: 16);
      expect(c.handleTableEnter(), isTrue);
      expect(c.text, '| a |\n| --- |\n| b |\n|  |');
      expect(c.selection.baseOffset, 22);
    });
  });

  group('NotesController.duplicateNote', () {
    test('preserves labels and formatting', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final dir = await Directory.systemTemp.createTemp('notes_dup_test');
      addTearDown(() => dir.delete(recursive: true));
      final controller = NotesController(store: NotesStore(baseDir: dir));
      addTearDown(controller.dispose);

      final note = _note(
        formats: const [FormatSpan(0, 5, FormatFlags.bold)],
        strokes: [
          StrokeItem(
            id: 's1',
            type: StrokeType.text,
            points: const [Offset(1, 1)],
            colorValue: 0xFF000000,
            width: 18,
            text: 'Label',
          ),
        ],
      );

      controller.duplicateNote(note);

      final copy = controller.selected!;
      expect(copy.id, isNot(note.id));
      expect(copy.body, note.body);
      expect(copy.formats, note.formats);
      expect(copy.strokes.single.text, 'Label');
      expect(copy.strokes.single.id, isNot('s1'));
    });
  });

  group('NotesStore', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('notes_store_test');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    NotesStore newStore() => NotesStore(baseDir: tempDir);

    test('save then load round-trips', () async {
      final store = newStore();
      await store.init();
      store.saveSync([_note(id: 'a', body: 'hello')], 'dark');
      final data = store.loadSync();
      expect(data.notes.single.body, 'hello');
      expect(data.themeMode, 'dark');
    });

    test('second save leaves a loadable backup', () async {
      final store = newStore();
      await store.init();
      store.saveSync([_note(id: 'a', body: 'first')], 'light');
      store.saveSync([_note(id: 'a', body: 'second')], 'light');
      final bak = File(
        '${tempDir.path}${Platform.pathSeparator}notes_app_data'
        '${Platform.pathSeparator}notes.json.bak',
      );
      expect(bak.existsSync(), isTrue);
      final store2 = newStore();
      await store2.init();
      expect(store2.loadSync().notes.single.body, 'second');
    });

    test('sidebar width round-trips', () async {
      final store = newStore();
      await store.init();
      store.saveSync([_note(id: 'a', body: 'hello')], 'light',
          sidebarWidth: 420);
      final data = store.loadSync();
      expect(data.sidebarWidth, 420);
    });

    test('corrupt main file falls back to backup', () async {
      final store = newStore();
      await store.init();
      store.saveSync([_note(id: 'a', body: 'first')], 'light');
      store.saveSync([_note(id: 'a', body: 'second')], 'light');

      final main = File(
        '${tempDir.path}${Platform.pathSeparator}notes_app_data'
        '${Platform.pathSeparator}notes.json',
      );
      main.writeAsStringSync('{ not json');

      final recovered = store.loadSync();
      expect(recovered.notes.single.body, 'first');
    });
  });
}
