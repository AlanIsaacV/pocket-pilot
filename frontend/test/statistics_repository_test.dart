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
              'current_month_cents': 10000, // equal to avg → flat
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

    test('trend up when current month > window avg by > threshold', () async {
      final repo = StatisticsRepository(
        local: _FakeLocalStore(
          categorySeries: const [
            {
              'category_id': 'c3',
              'name': 'Ocio',
              'color': '#A0A0A0',
              'icon': 'movie',
              'kind': 'expense',
              'total_cents': 60000,          // 6m * 10000 avg
              'current_month_cents': 15000,  // +50% over avg
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

    test('trend down when current month < window avg by > threshold', () async {
      final repo = StatisticsRepository(
        local: _FakeLocalStore(
          categorySeries: const [
            {
              'category_id': 'c4',
              'name': 'Ocio',
              'color': '#A0A0A0',
              'icon': 'movie',
              'kind': 'expense',
              'total_cents': 60000,         // avg 10000
              'current_month_cents': 5000,  // -50% vs avg
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

      expect(list[0].trend, Trend.down);
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
            },
          ],
        ),
        budgetLocal: _FakeBudgetLocalStore(),
      );

      final history = await repo.getHistory(
        categoryId: 'c1',
        currencyCode: 'MXN',
        from: '2026-01-01',
        to: '2026-03-15',
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
        from: '2026-02-01',
        to: '2026-04-01',
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
            },
          ],
        ),
        budgetLocal: _FakeBudgetLocalStore(throwOnFind: true),
      );

      final history = await repo.getHistory(
        categoryId: 'c1',
        currencyCode: 'MXN',
        from: '2026-02-01',
        to: '2026-04-01',
      );

      expect(history.budget, isNull);
    });
  });

  group('StatisticsRepository.getTagHistory', () {
    test(
      'total = sum of breakdown slices; current = last month in points',
      () async {
        final repo = StatisticsRepository(
          local: _FakeLocalStore(
            tagMonthlySeries: const [
              {'ym': '2026-03', 'amount_cents': 30000},
              {'ym': '2026-05', 'amount_cents': 50000},
            ],
            tagBreakdown: const [
              {
                'category_id': 'c1',
                'category_name': 'Hotel',
                'category_color': '#FF0000',
                'category_icon': 'hotel',
                'kind': 'expense',
                'amount_cents': 60000,
              },
              {
                'category_id': 'c2',
                'category_name': 'Comida',
                'category_color': '#00FF00',
                'category_icon': 'restaurant',
                'kind': 'expense',
                'amount_cents': 20000,
              },
            ],
          ),
          budgetLocal: _FakeBudgetLocalStore(),
        );

        final h = await repo.getTagHistory(
          tagName: 'vacaciones_merida_2026',
          currencyCode: 'MXN',
          from: '2026-03-01',
          to: '2026-05-31',
        );

        // 3 months in window: Mar, Apr, May → zero-fill April.
        expect(h.points.map((p) => p.yearMonth).toList(),
            ['2026-03', '2026-04', '2026-05']);
        expect(h.points.map((p) => p.amountCents).toList(),
            [30000, 0, 50000]);

        // Total comes from breakdown (60k + 20k), avg = total / 3 months.
        expect(h.totalCents, 80000);
        expect(h.avgMonthlyCents, 80000 ~/ 3);
        expect(h.currentMonthCents, 50000);

        // Breakdown order preserved from local store.
        expect(h.categoryBreakdown.map((s) => s.categoryId).toList(),
            ['c1', 'c2']);
        expect(h.categoryBreakdown[0].categoryName, 'Hotel');
      },
    );

    test('empty data returns zero-filled points and zero totals', () async {
      final repo = StatisticsRepository(
        local: _FakeLocalStore(),
        budgetLocal: _FakeBudgetLocalStore(),
      );

      final h = await repo.getTagHistory(
        tagName: 'unused',
        currencyCode: 'MXN',
        from: '2026-04-01',
        to: '2026-04-30',
      );

      expect(h.totalCents, 0);
      expect(h.avgMonthlyCents, 0);
      expect(h.currentMonthCents, 0);
      expect(h.points, hasLength(1));
      expect(h.points.first.amountCents, 0);
      expect(h.categoryBreakdown, isEmpty);
    });
  });

  group('StatisticsRepository.listTagsWithTotals', () {
    test('maps rows to TagSummaryDTO preserving order', () async {
      final repo = StatisticsRepository(
        local: _FakeLocalStore(
          allTagsRows: const [
            {
              'tag_name': 'vacaciones_merida_2026',
              'currency_code': 'MXN',
              'amount_cents': 120000,
            },
            {
              'tag_name': 'casa',
              'currency_code': 'MXN',
              'amount_cents': 80000,
            },
          ],
        ),
        budgetLocal: _FakeBudgetLocalStore(),
      );

      final tags = await repo.listTagsWithTotals(
        from: '2026-01-01',
        to: '2026-05-31',
      );

      expect(tags, hasLength(2));
      expect(tags[0].tagName, 'vacaciones_merida_2026');
      expect(tags[0].totalCents, 120000);
      expect(tags[0].currencyCode, 'MXN');
      expect(tags[1].tagName, 'casa');
    });
  });
}

// ---- fakes ---------------------------------------------------------

class _FakeLocalStore extends StatisticsLocalStore {
  final List<Map<String, dynamic>> categorySeries;
  final List<Map<String, dynamic>> monthlySeries;
  final List<Map<String, dynamic>> tagMonthlySeries;
  final List<Map<String, dynamic>> tagBreakdown;
  final List<Map<String, dynamic>> allTagsRows;

  _FakeLocalStore({
    this.categorySeries = const [],
    this.monthlySeries = const [],
    this.tagMonthlySeries = const [],
    this.tagBreakdown = const [],
    this.allTagsRows = const [],
  }) : super(db: DatabaseHelper());

  @override
  Future<List<Map<String, dynamic>>> getCategorySeries({
    required String currencyCode,
    required String windowStart,
    required String windowEnd,
    required String windowMid,
    required String currentYm,
    Set<String>? accountIds,
  }) async =>
      categorySeries;

  @override
  Future<List<Map<String, dynamic>>> getMonthlySeries({
    required String categoryId,
    required String currencyCode,
    required String windowStart,
    required String windowEnd,
    Set<String>? accountIds,
  }) async =>
      monthlySeries;

  @override
  Future<List<Map<String, dynamic>>> getTagMonthlySeries({
    required String tagName,
    required String currencyCode,
    required String windowStart,
    required String windowEnd,
    Set<String>? accountIds,
  }) async =>
      tagMonthlySeries;

  @override
  Future<List<Map<String, dynamic>>> getTagCategoryBreakdown({
    required String tagName,
    required String currencyCode,
    required String windowStart,
    required String windowEnd,
    Set<String>? accountIds,
  }) async =>
      tagBreakdown;

  @override
  Future<List<Map<String, dynamic>>> getAllTagsWithTotals({
    required String windowStart,
    required String windowEnd,
    Set<String>? accountIds,
    String? currencyCode,
  }) async =>
      allTagsRows;
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
