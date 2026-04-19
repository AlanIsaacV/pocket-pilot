import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/cashflow/data/cashflow_local_store.dart';
import 'package:pocket_pilot/src/features/cashflow/data/cashflow_repository.dart';
import 'package:pocket_pilot/src/features/cashflow/domain/cashflow_snapshot.dart';

void main() {
  group('CashflowRepository.getSnapshot', () {
    test('totals + net come directly from grand totals query', () async {
      final repo = CashflowRepository(
        local: _FakeLocal(
          totals: const {'income': 50000, 'expense': 30000},
        ),
      );

      final snap = await repo.getSnapshot(
        currencyCode: 'MXN',
        months: 3,
        now: DateTime.utc(2026, 4, 1),
      );

      expect(snap.totalInCents, 50000);
      expect(snap.totalOutCents, 30000);
      expect(snap.netCents, 20000);
      expect(snap.currencyCode, 'MXN');
      expect(snap.windowMonths, 3);
    });

    test('empty period yields isEmpty snapshot', () async {
      final repo = CashflowRepository(local: _FakeLocal());

      final snap = await repo.getSnapshot(
        currencyCode: 'MXN',
        months: 3,
        now: DateTime.utc(2026, 4, 1),
      );

      expect(snap.isEmpty, true);
      expect(snap.byCategory, isEmpty);
      expect(snap.byNature, isEmpty);
    });

    test('category fold keeps top N per kind + Otros with the rest', () async {
      final repo = CashflowRepository(
        local: _FakeLocal(
          totals: const {'income': 0, 'expense': 21000},
          categoryRows: [
            for (var i = 0; i < 8; i++)
              {
                'category_id': 'c$i',
                'name': 'Cat$i',
                'color': null,
                'kind': 'expense',
                // 8000, 7000, 6000, 5000, 4000, 3000, 2000, 1000 → total 36000
                'total_cents': (8 - i) * 1000,
              },
          ],
        ),
      );

      final snap = await repo.getSnapshot(
        currencyCode: 'MXN',
        months: 3,
        now: DateTime.utc(2026, 4, 1),
        topN: 3,
      );

      // With topN=3 we keep Cat0, Cat1, Cat2 and fold Cat3..Cat7 into Otros.
      final expense = snap.byCategory.where((e) => e.kind == 'expense').toList();
      expect(expense.map((e) => e.label).toList(), [
        'Cat0',
        'Cat1',
        'Cat2',
        'Otros',
      ]);
      expect(expense.last.amountCents, 5000 + 4000 + 3000 + 2000 + 1000);
    });

    test('income and expense folds live in separate buckets', () async {
      final repo = CashflowRepository(
        local: _FakeLocal(
          totals: const {'income': 12000, 'expense': 8000},
          categoryRows: const [
            {
              'category_id': 'i1',
              'name': 'Salario',
              'color': '#00FF00',
              'kind': 'income',
              'total_cents': 10000,
            },
            {
              'category_id': 'i2',
              'name': 'Extras',
              'color': null,
              'kind': 'income',
              'total_cents': 2000,
            },
            {
              'category_id': 'e1',
              'name': 'Comida',
              'color': '#FF0000',
              'kind': 'expense',
              'total_cents': 5000,
            },
            {
              'category_id': 'e2',
              'name': 'Transporte',
              'color': null,
              'kind': 'expense',
              'total_cents': 3000,
            },
          ],
        ),
      );

      final snap = await repo.getSnapshot(
        currencyCode: 'MXN',
        months: 3,
        now: DateTime.utc(2026, 4, 1),
      );

      final income = snap.byCategory.where((e) => e.kind == 'income').toList();
      final expense = snap.byCategory.where((e) => e.kind == 'expense').toList();

      expect(income.map((e) => e.label).toList(), ['Salario', 'Extras']);
      expect(expense.map((e) => e.label).toList(), ['Comida', 'Transporte']);
      // No Otros because each kind had <= topN entries.
      expect(income.any((e) => e.label == 'Otros'), false);
      expect(expense.any((e) => e.label == 'Otros'), false);
    });

    test('nature rows map 1:1 without folding', () async {
      final repo = CashflowRepository(
        local: _FakeLocal(
          totals: const {'income': 0, 'expense': 20000},
          natureRows: const [
            {'nature': 'required', 'kind': 'expense', 'total_cents': 10000},
            {'nature': 'lifestyle', 'kind': 'expense', 'total_cents': 7000},
            {'nature': 'obligation', 'kind': 'expense', 'total_cents': 3000},
          ],
        ),
      );

      final snap = await repo.getSnapshot(
        currencyCode: 'MXN',
        months: 3,
        now: DateTime.utc(2026, 4, 1),
      );

      expect(snap.byNature, hasLength(3));
      expect(snap.byNature.first.label, 'required');
      expect(snap.byNature.first.amountCents, 10000);
      expect(snap.byNature.last.label, 'obligation');
    });

    test('entriesFor picks the right list', () async {
      const entry = CashflowBreakdownEntry(
        id: 'x',
        label: 'X',
        kind: 'expense',
        amountCents: 1,
      );
      const snap = CashflowSnapshot(
        currencyCode: 'MXN',
        windowMonths: 3,
        totalInCents: 0,
        totalOutCents: 1,
        netCents: -1,
        byCategory: [entry],
        byNature: [],
      );

      expect(snap.entriesFor(BreakdownMode.category), [entry]);
      expect(snap.entriesFor(BreakdownMode.nature), isEmpty);
    });
  });
}

class _FakeLocal extends CashflowLocalStore {
  final Map<String, int> totals;
  final List<Map<String, dynamic>> categoryRows;
  final List<Map<String, dynamic>> natureRows;

  _FakeLocal({
    this.totals = const {},
    this.categoryRows = const [],
    this.natureRows = const [],
  }) : super(db: DatabaseHelper());

  @override
  Future<Map<String, int>> getTotals({
    required String currencyCode,
    required String windowStart,
    required String windowEnd,
  }) async =>
      totals;

  @override
  Future<List<Map<String, dynamic>>> getCategoryTotals({
    required String currencyCode,
    required String windowStart,
    required String windowEnd,
  }) async =>
      categoryRows;

  @override
  Future<List<Map<String, dynamic>>> getNatureTotals({
    required String currencyCode,
    required String windowStart,
    required String windowEnd,
  }) async =>
      natureRows;
}
