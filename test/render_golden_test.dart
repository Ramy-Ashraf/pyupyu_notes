import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notes_app/utils/markdown_table.dart';
import 'package:notes_app/widgets/table_block.dart';

/// Renders the Excel table block to a golden PNG for visual inspection.
/// Run with `flutter test test/render_golden_test.dart --update-goldens`.
void main() {
  testWidgets('render table block', (tester) async {
    final table = TableData.parse(
      '| Product | Qty | Price |\n'
      '| --- | --- | --- |\n'
      '| Apples | 3 | 2.50 |\n'
      '| Bread | 1 | 1.20 |\n'
      '| Milk | 2 | 0.99 |'.split('\n'),
    );
    final focusNode = FocusNode();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Scaffold(
          backgroundColor: const Color(0xFFFBF0CE),
          body: Center(
            child: SizedBox(
              width: 640,
              child: ExcelTableBlock(
                table: table,
                focusNode: focusNode,
                dark: false,
                onChanged: () {},
                onDeleted: () {},
                onActivated: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    focusNode.requestFocus();
    await tester.pump();

    // Selected cell shows the green border; helpers show while focused.
    tester
        .state<ExcelTableBlockState>(find.byType(ExcelTableBlock))
        .selectCell(1, 0);
    await tester.pump();

    await expectLater(
      find.byType(ExcelTableBlock),
      matchesGoldenFile('goldens/table_block.png'),
    );

    // Regression: the grid must have real, usable size.
    final size = tester.getSize(find.byType(ExcelTableBlock));
    expect(size.height, greaterThan(100), reason: 'table collapsed to zero height');
    expect(size.width, greaterThan(200));
  });
}
