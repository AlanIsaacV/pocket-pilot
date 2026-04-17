import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/budgets/data/budget_local_store.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_local_store.dart';
import 'package:pocket_pilot/src/features/statistics/data/statistics_repository.dart';
import 'package:pocket_pilot/src/features/statistics/domain/trend.dart';

void main() {
  group('StatisticsRepository.getSeriesList', () {
    test('expense category: avg = total / N, trend flat', () async {
      final repo = StatisticsRepository(
        local: _FakeLocalStore(
          categorySeries: const [
            {
              'category_id': 'c1',
              'name': 'Comida',
              'color': '#FF0000',
              'icon': 'restaurant',
              'kind': 'expense',
              'total_cents': 60000,         // 6 months * 10000
              'current_month_cents': 10000,
              'first_half_cents': 30000,
              'second_half_cents': 30000,
            },
          ],
        ),
        budgetLocal: _FakeBudgetLocalStore(),
      );

      final list = await repo.getSeriesList(
        currencyCode: 'MXN',
        windowStart: '2025-11-01',
        windowEnd: '2026-05-01',
        windowMid: '2026-02-01',
        currentYm: '2026-04',
        months: 6,
      );

      expect(list, hasLength(1));
      expect(list[0].categoryId, 'c1');
      expect(list[0].totalCents, 60000);
      expect(list[0].avgMonthlyCents, 10000);
      expect(list[0].currentMonthCents, 10000);
      expect(list[0].trend, Trend.flat);
    });

    test('income category: sign is flipped to positive', () async {
      final repo = StatisticsRepository(
        local: _FakeLocalStore(
          categorySeries: const [
            {
              'category_id': 'c2',
              'name': 'Salario',
              'color': '#00FF00',
              'icon': 'work',
              'kind': 'income',
              // Income subtracts in SQL, so totals come back negative.
              'total_cents': -120000,
              'current_month_cents': -20000,
              'first_half_cents': -60000,
              'second_half_cents': -60000,
            },
          ],
        ),
        budgetLocal: _FakeBudgetLocalStore(),
      );

      final list = await repo.getSeriesList(
        currencyCode: 'MXN',
        windowStart: '2025-11-01',
        windowEnd: '2026-05-01',
        windowMid: '2026-02-01',
        currentYm: '2026-04',
        months: 6,
      );

      expect(list[0].totalCents, 120000);
      expect(list[0].currentMonthCents, 20000);
      expect(list[0].avgMonthlyCents, 20000);
      expect(list[0].kind, 'income');
    });

    test('trend up when second half > first half by > threshold', () async {
      final repo = StatisticsRepository(
        local: _FakeLocalStore(
          categorySeries: const [
            {
              'category_id': 'c3',
              'name': 'Ocio',
              'color': '#A0A0A0',
              'icon': 'movie',
              'kind': 'expense',
              'total_cents': 100,
              'current_month_cents': 0,
              'first_half_cents': 40,
              'second_half_cents': 60, // +50% over first half
            },
          ],
        ),
        budgetLocal: _FakeBudgetLocalStore(),
      );

      final list = await repo.getSeriesList(
        currencyCode: 'MXN',
        windowStart: '2025-11-01',
        windowEnd: '2026-05-01',
        windowMid: '2026-02-01',
        currentYm: '2026-04',
        months: 6,
      );

      expect(list[0].trend, Trend.up);
    });
  });

  group('StatisticsRepository.getHistory', () {
    test('zero-fills missing months in order', () async {
      final repo = StatisticsRepository(
        local: _FakeLocalStore(
          monthlySeries: const [
            {'ym': '2026-01', 'amount_cents': 5000},
            {'ym': '2026-03', 'amount_cents': 7000},
          ],
          categorySeries: const [
            {
              'category_id': 'c1',
              'name': 'Comida',
              'color': '#FF0000',
              'icon': 'restaurant',
              'kind': 'expense',
              'total_cents': 12000,
              'current_month_cents': 0,
              'first_half_cents': 0,
              'second_half_cents': 12000,
            },
          ],
        ),
        budgetLocal: _FakeBudgetLocalStore(),
      );

      final history = await repo.getHistory(
        categoryId: 'c1',
        currencyCode: 'MXN',
        months: 3,
        now: DateTime.utc(2026, 3, 15),
      );

      expect(history.points.map((p) => p.yearMonth).toList(), [
        '2026-01',
        '2026-02',
        '2026-03',
      ]);
      expect(history.points.map((p) => p.amountCents).toList(), [
        5000,
        0,
        7000,
      ]);
    });

    test('budget with non-matching currency resolves to null', () async {
      final repo = StatisticsRepository(
        local: _FakeLocalStore(
          categorySeries: const [
            {
              'category_id': 'c1',
              'name': 'Comida',
              'color': '#FF0000',
              'icon': 'restaurant',
              'kind': 'expense',
              'total_cents': 1,
              'current_month_cents': 0,
              'first_half_cents': 0,
              'second_half_cents': 1,
            },
          ],
        ),
        budgetLocal: _FakeBudgetLocalStore(
          budgetRow: const {
            'id': 'b1',
            'category_id': 'c1',
            'limit_amount_cents': 10000,
            'currency_code': 'USD', // mismatch
            'period': 'MONTHLY',
            'created_at': '2026-01-01T00:00:00Z',
            'updated_at': '2026-01-01T00:00:00Z',
            'deleted_at': null,
          },
        ),
      );

      final history = await repo.getHistory(
        categoryId: 'c1',
        currencyCode: 'MXN',
        months: 3,
        now: DateTime.utc(2026, 4, 1),
      );

      expect(history.budget, isNull);
    });

    test('budget lookup failure leaves budget null (logged)', () async {
      final repo = StatisticsRepository(
        local: _FakeLocalStore(
          categorySeries: const [
            {
              'category_id': 'c1',
              'name': 'Comida',
              'color': '#FF0000',
              'icon': 'restaurant',
              'kind': 'expense',
              'total_cents': 1,
              'current_month_cents': 0,
              'first_half_cents': 0,
              'second_half_cents': 1,
            },
          ],
        ),
        budgetLocal: _FakeBudgetLocalStore(throwOnFind: true),
      );

      final history = await repo.getHistory(
        categoryId: 'c1',
        currencyCode: 'MXN',
        months: 3,
        now: DateTime.utc(2026, 4, 1),
      );

      expect(history.budget, isNull);
    });
  });
}

// ---- fakes ---------------------------------------------------------

class _FakeLocalStore extends StatisticsLocalStore {
  final List<Map<String, dynamic>> categorySeries;
  final List<Map<String, dynamic>> monthlySeries;

  _FakeLocalStore({
    this.categorySeries = const [],
    this.monthlySeries = const [],
  }) : super(db: DatabaseHelper());

  @override
  Future<List<Map<String, dynamic>>> getCategorySeries({
    required String currencyCode,
    required String windowStart,
    required String windowEnd,
    required String windowMid,
    required String currentYm,
  }) async =>
      categorySeries;

  @override
  Future<List<Map<String, dynamic>>> getMonthlySeries({
    required String categoryId,
    required String currencyCode,
    required String windowStart,
    required String windowEnd,
  }) async =>
      monthlySeries;
}

class _FakeBudgetLocalStore extends BudgetLocalStore {
  final Map<String, dynamic>? budgetRow;
  final bool throwOnFind;

  _FakeBudgetLocalStore({this.budgetRow, this.throwOnFind = false})
      : super(db: DatabaseHelper());

  @override
  Future<Map<String, dynamic>?> findByCategory(String categoryId) async {
    if (throwOnFind) throw StateError('boom');
    return budgetRow;
  }

  @override
  Future<int> computeSpentCents(String categoryId, String period) async => 0;
}
