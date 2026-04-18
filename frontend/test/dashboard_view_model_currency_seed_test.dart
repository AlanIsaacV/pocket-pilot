import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/features/dashboard/data/dashboard_local_store.dart';
import 'package:pocket_pilot/src/features/dashboard/data/dashboard_repository.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/account_balance_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/category_spend_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_payment_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/dashboard_metrics.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/nature_spend_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/tag_spend_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_filter_view_model.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_view_model.dart';
import 'package:pocket_pilot/src/core/db/database_helper.dart';

void main() {
  test('seeds DashboardFilterViewModel with first currency after load',
      () async {
    final filter = DashboardFilterViewModel();
    expect(filter.currencyCode, isNull);

    final vm = DashboardViewModel(
      repository: _FakeRepo(currencies: const ['USD', 'MXN']),
      filterViewModel: filter,
    );
    await vm.refresh();

    // Alphabetically sorted → 'MXN' is first.
    expect(filter.currencyCode, 'MXN');
  });

  test('does not overwrite currency already set by user', () async {
    final filter = DashboardFilterViewModel()..setCurrencyCode('USD');
    final vm = DashboardViewModel(
      repository: _FakeRepo(currencies: const ['USD', 'MXN']),
      filterViewModel: filter,
    );
    await vm.refresh();

    expect(filter.currencyCode, 'USD');
  });

  test('no currencies available leaves filter null', () async {
    final filter = DashboardFilterViewModel();
    final vm = DashboardViewModel(
      repository: _FakeRepo(currencies: const []),
      filterViewModel: filter,
    );
    await vm.refresh();

    expect(filter.currencyCode, isNull);
  });
}

class _FakeRepo extends DashboardRepository {
  final List<String> currencies;

  _FakeRepo({required this.currencies})
      : super(local: DashboardLocalStore(db: DatabaseHelper()));

  @override
  Future<Map<String, DashboardMetrics>> calculateAllMetrics({
    Set<String>? accountIds,
  }) async {
    return {
      for (final c in currencies) c: DashboardMetrics.empty(currencyCode: c),
    };
  }

  @override
  Future<List<AccountBalanceDTO>> getBalancesPerAccount({
    Set<String>? accountIds,
  }) async => const [];

  @override
  Future<List<CreditCardPaymentDTO>> getCreditCardPayments({
    Set<String>? accountIds,
  }) async => const [];

  @override
  Future<List<CategorySpendDTO>> getMonthlySpendByCategory(
    String startDate,
    String endDate, {
    Set<String>? accountIds,
    String? currencyCode,
  }) async => const [];

  @override
  Future<List<NatureSpendDTO>> getMonthlySpendByNature(
    String startDate,
    String endDate, {
    Set<String>? accountIds,
    String? currencyCode,
  }) async => const [];

  @override
  Future<List<TagSpendDTO>> getMonthlySpendByTag(
    String startDate,
    String endDate, {
    Set<String>? accountIds,
    String? currencyCode,
  }) async => const [];
}
