import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/src/features/csv_import/domain/csv_transaction_row.dart';
import 'package:pocket_pilot/src/features/csv_import/ui/csv_mapping_screen.dart';

void main() {
  const rows = [
    CsvTransactionRow(
      date: '2026-07-10',
      type: 'EXPENSE',
      amount: 120.0,
      currencyCode: 'MXN',
      accountName: 'RappiCard',
      tagNames: [],
      notes: 'Café',
    ),
    CsvTransactionRow(
      date: '2026-07-11',
      type: 'EXPENSE',
      amount: 45.0,
      currencyCode: 'MXN',
      accountName: 'RappiCard',
      tagNames: [],
      notes: 'Comida',
    ),
  ];

  Future<void> pumpReview(
    WidgetTester tester, {
    required Set<int> included,
    required Set<int> duplicates,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => CsvDuplicateReviewSection(
              rows: rows,
              duplicateRowIndices: duplicates,
              isRowIncluded: included.contains,
              onRowIncludedChanged: (index, value) => setState(() {
                if (value) {
                  included.add(index);
                } else {
                  included.remove(index);
                }
              }),
              onIncludeAll: () => setState(() => included.addAll(duplicates)),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('muestra el indicador y omite duplicados por defecto', (
    tester,
  ) async {
    final included = <int>{};
    await pumpReview(tester, included: included, duplicates: {0});

    expect(find.byKey(const Key('duplicate-badge-0')), findsOneWidget);
    expect(find.text('Duplicado'), findsOneWidget);
    expect(
      tester.widget<Switch>(find.byKey(const Key('duplicate-toggle-0'))).value,
      isFalse,
    );
    expect(find.text('Omitir'), findsOneWidget);
  });

  testWidgets('el interruptor incluye un duplicado individualmente', (
    tester,
  ) async {
    final included = <int>{};
    await pumpReview(tester, included: included, duplicates: {0});

    await tester.tap(find.byKey(const Key('duplicate-toggle-0')));
    await tester.pump();

    expect(included, {0});
    expect(
      tester.widget<Switch>(find.byKey(const Key('duplicate-toggle-0'))).value,
      isTrue,
    );
    expect(find.text('Incluir'), findsOneWidget);
  });

  testWidgets('la acción masiva incluye todos los duplicados', (tester) async {
    final included = <int>{};
    await pumpReview(tester, included: included, duplicates: {0, 1});

    await tester.tap(find.byKey(const Key('include-all-duplicates')));
    await tester.pump();

    expect(included, {0, 1});
    expect(
      tester.widget<Switch>(find.byKey(const Key('duplicate-toggle-0'))).value,
      isTrue,
    );
    expect(
      tester.widget<Switch>(find.byKey(const Key('duplicate-toggle-1'))).value,
      isTrue,
    );
  });

  test('el resumen muestra importadas y omitidas por duplicado', () {
    expect(
      csvImportSummaryText(importedCount: 3, skippedDuplicateCount: 2),
      '3 transacciones importadas; 2 omitidas por duplicado',
    );
  });
}
