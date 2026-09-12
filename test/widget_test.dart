import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Canvas, PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notes_app/controllers/format_text_controller.dart';
import 'package:notes_app/controllers/notes_controller.dart';
import 'package:notes_app/models/format_span.dart';
import 'package:notes_app/models/note.dart';
import 'package:notes_app/models/stroke_item.dart';
import 'package:notes_app/services/notes_store.dart';
import 'package:notes_app/utils/markdown_table.dart';
import 'package:notes_app/widgets/body_editor.dart';
import 'package:notes_app/widgets/drawing/stroke_render.dart';
import 'package:notes_app/widgets/table_block.dart';

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

  group('Markdown table model', () {
    test('splitTableCells handles outer pipes and escapes', () {
      expect(splitTableCells('| Name | Age |'), ['Name', 'Age']);
      expect(splitTableCells('a | b'), ['a', 'b']);
      expect(splitTableCells('a \\| b | c'), ['a | b', 'c']);
    });

    test('plain text and lone pipe lines are not tables', () {
      expect(findMarkdownTables('hello'), isEmpty);
      expect(findMarkdownTables('a | b'), isEmpty);
      expect(findMarkdownTables('just text\nmore'), isEmpty);
    });

    test('parse and serialize round-trip a table', () {
      const src = '| Name | Age |\n| ---- | --- |\n| Alex | 30  |';
      final tables = findMarkdownTables(src);
      expect(tables, hasLength(1));
      final data = TableData.parse(src.split('\n'));
      expect(data.rowCount, 2);
      expect(data.columnCount, 2);
      expect(data.cellAt(0, 0), 'Name');
      expect(data.cellAt(1, 1), '30');
      expect(data.toMarkdown(), src);
    });

    test('cells with pipes are escaped and unescaped safely', () {
      final data = TableData(rows: [
        ['a | b', 'c'],
        ['d', 'e'],
      ]);
      final md = data.toMarkdown();
      expect(md, contains(r'a \| b'));
      final parsed = TableData.parse(md.split('\n'));
      expect(parsed.cellAt(0, 0), 'a | b');
      expect(parsed.toMarkdown(), md);
    });

    test('back-to-back tables are detected separately', () {
      const src = '| a | b |\n| --- | --- |\n| 1 | 2 |\n'
          '| c | d |\n| --- | --- |\n| 3 | 4 |';
      expect(findMarkdownTables(src), hasLength(2));
    });

    test('rows and columns can be inserted and deleted', () {
      final data = TableData.parse('| a | b |\n| --- | --- |\n| c | d |'.split('\n'));
      expect(data.insertRowAt(2), 2);
      expect(data.rowCount, 3);
      expect(data.cellAt(2, 0), '');
      expect(data.deleteRowAt(1), isTrue);
      expect(data.cellAt(1, 0), '');
      expect(data.insertColumnAt(1), 1);
      expect(data.columnCount, 3);
      expect(data.cellAt(0, 1), '');
      expect(data.deleteColumnAt(0), isTrue);
      expect(data.cellAt(0, 0), '');
      expect(data.cellAt(0, 1), 'b');
      // Down to a single row/column, deletion refuses: the caller removes
      // the whole table instead.
      expect(data.deleteRowAt(0), isTrue);
      expect(data.deleteRowAt(0), isFalse);
      expect(data.deleteColumnAt(0), isTrue);
      expect(data.deleteColumnAt(0), isFalse);
    });

    test('serialization pads cells so pipes line up', () {
      final data = TableData(rows: [
        ['a', 'bb'],
        ['ccc', 'd'],
      ]);
      expect(
        data.toMarkdown(),
        '| a   | bb  |\n| --- | --- |\n| ccc | d   |',
      );
    });

    test('empty tables have the requested size', () {
      final data = TableData.empty(3, 2);
      expect(data.rowCount, 3); // header + 2 body rows
      expect(data.columnCount, 3);
      expect(
        data.toMarkdown(),
        '|     |     |     |\n| --- | --- | --- |\n'
        '|     |     |     |\n|     |     |     |',
      );
    });

    test('column letters follow the spreadsheet convention', () {
      expect(TableData.columnLetter(0), 'A');
      expect(TableData.columnLetter(25), 'Z');
      expect(TableData.columnLetter(26), 'AA');
    });
  });

  group('BodyEditor tables (Excel-style)', () {
    Future<BodyEditorState> pumpEditor(
      WidgetTester tester, {
      String body = '',
      List<FormatSpan> formats = const [],
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BodyEditor(
            noteId: 'n1',
            initialBody: body,
            initialFormats: formats,
            textColor: Colors.black,
            onChanged: (_, _) {},
          ),
        ),
      ));
      await tester.pump();
      return tester.state<BodyEditorState>(find.byType(BodyEditor));
    }

    testWidgets('insertTable creates a grid and Markdown source',
        (tester) async {
      final editor = await pumpEditor(tester);
      editor.insertTable(2, 1);
      await tester.pump();

      expect(find.byType(ExcelTableBlock), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      // The grid must actually lay out — a zero-height table is invisible
      // and unclickable in the running app.
      final size = tester.getSize(find.byType(ExcelTableBlock));
      expect(size.height, greaterThan(80));
      expect(size.width, greaterThan(180));
      expect(
        editor.text,
        // An empty text line is kept above and below the grid for typing;
        // empty cells are padded to the minimum column width.
        '\n|     |     |\n| --- | --- |\n|     |     |\n',
      );
    });

    testWidgets('clicking a cell and typing fills it (seeded edit)',
        (tester) async {
      final editor = await pumpEditor(tester);
      editor.insertTable(1, 2);
      await tester.pump();

      final grid =
          tester.state<ExcelTableBlockState>(find.byType(ExcelTableBlock));
      grid.selectCell(0, 0); // single click: select only, no editor yet
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(ExcelTableBlock),
          matching: find.byType(TextField),
        ),
        findsNothing,
      );

      // A printable key event starts a seeded edit that replaces content.
      await simulateKeyDownEvent(LogicalKeyboardKey.keyH, character: 'H');
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(ExcelTableBlock),
          matching: find.byType(TextField),
        ),
        findsOneWidget,
      );
      expect(grid.table.cellAt(0, 0), ''); // not committed until Enter/Tab

      await tester.enterText(
        find.descendant(
          of: find.byType(ExcelTableBlock),
          matching: find.byType(TextField),
        ),
        'Hello',
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(grid.table.cellAt(0, 0), 'Hello');
      expect(editor.text, contains('Hello'));
    });

    testWidgets('typing into a cell updates the Markdown',
        (tester) async {
      final editor = await pumpEditor(tester);
      editor.insertTable(2, 1);
      await tester.pump();

      final grid =
          tester.state<ExcelTableBlockState>(find.byType(ExcelTableBlock));
      grid.selectCell(0, 0, edit: true);
      await tester.pump();

      await tester.enterText(
        find.descendant(
          of: find.byType(ExcelTableBlock),
          matching: find.byType(TextField),
        ),
        'Name',
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      // Tab committed the cell: the Markdown now holds the value.
      expect(editor.text, contains('| Name |'));
    });

    testWidgets('Enter commits and moves down a row', (tester) async {
      final editor = await pumpEditor(tester);
      editor.insertTable(1, 2);
      await tester.pump();

      final grid =
          tester.state<ExcelTableBlockState>(find.byType(ExcelTableBlock));
      grid.selectCell(0, 0, edit: true);
      await tester.pump();

      await tester.enterText(
        find.descendant(
          of: find.byType(ExcelTableBlock),
          matching: find.byType(TextField),
        ),
        'top',
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(editor.text, contains('top'));
      // The cell below (row 1) is now selected; typing replaces it.
      grid.selectCell(1, 0, edit: true);
      await tester.pump();
      await tester.enterText(
        find.descendant(
          of: find.byType(ExcelTableBlock),
          matching: find.byType(TextField),
        ),
        'bottom',
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(editor.text, contains('bottom'));
      final md = editor.text;
      expect(md.indexOf('top'), lessThan(md.indexOf('bottom')));
    });

    testWidgets('row and column operations edit the grid', (tester) async {
      final editor = await pumpEditor(tester);
      editor.insertTable(2, 1);
      await tester.pump();

      final grid =
          tester.state<ExcelTableBlockState>(find.byType(ExcelTableBlock));
      grid.selectCell(0, 0);
      grid.insertColumn(before: false);
      await tester.pump();
      expect(grid.table.columnCount, 3);
      expect(editor.text, contains('| --- | --- | --- |'));

      grid.insertRow(above: true);
      await tester.pump();
      expect(grid.table.rowCount, 3); // header + new row + body row

      grid.deleteColumn();
      await tester.pump();
      expect(grid.table.columnCount, 2);

      grid.deleteRow();
      await tester.pump();
      expect(grid.table.rowCount, 2);
    });

    testWidgets('deleting the table removes the block and merges text',
        (tester) async {
      final editor = await pumpEditor(tester, body: 'before\nafter');
      editor.insertTable(1, 1);
      await tester.pump();
      expect(find.byType(ExcelTableBlock), findsOneWidget);

      final grid =
          tester.state<ExcelTableBlockState>(find.byType(ExcelTableBlock));
      grid.selectCell(0, 0);
      grid.deleteTable();
      await tester.pump();

      expect(find.byType(ExcelTableBlock), findsNothing);
      expect(editor.text, 'before\nafter');
    });

    testWidgets('an existing Markdown table renders as a grid',
        (tester) async {
      final editor = await pumpEditor(
        tester,
        body: 'Title\n| Name | Age |\n| ---- | --- |\n| Alex | 30  |\n',
      );
      await tester.pump();

      expect(find.byType(ExcelTableBlock), findsOneWidget);
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Alex'), findsOneWidget);
      // The plain text block stays editable beside the grid.
      expect(find.text('Title'), findsOneWidget);
      expect(editor.text,
          'Title\n| Name | Age |\n| ---- | --- |\n| Alex | 30  |\n');
    });

    testWidgets('typing a Markdown table in text converts it to a grid',
        (tester) async {
      final editor = await pumpEditor(tester, body: 'keep me');
      await tester.enterText(find.byType(TextField).first,
          'keep me\n| a | b |\n| --- | --- |\n| 1 | 2 |');
      await tester.pump();
      await tester.pump();

      expect(find.byType(ExcelTableBlock), findsOneWidget);
      expect(find.text('a'), findsOneWidget);
      expect(find.text('1'), findsWidgets); // cell + row-number gutter
      expect(editor.text, contains('| a   | b   |'));
    });

    testWidgets('text blocks keep editing between two tables',
        (tester) async {
      // The editor normalizes Markdown padding, so feed it padded source.
      const body = '| a   |\n| --- |\n| 1   |\nhello\n'
          '| b   |\n| --- |\n| 2   |';
      final editor = await pumpEditor(tester, body: body);
      await tester.pump();

      expect(find.byType(ExcelTableBlock), findsNWidgets(2));
      expect(find.text('hello'), findsOneWidget);
      expect(editor.text, body);
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
