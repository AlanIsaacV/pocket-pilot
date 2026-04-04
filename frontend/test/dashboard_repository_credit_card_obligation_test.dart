import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/dashboard/data/dashboard_local_store.dart';
import 'package:pocket_pilot/src/features/dashboard/data/dashboard_repository.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/account_balance_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_account_cycle_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_movement_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/goal_target_dto.dart';

void main() {
  test('safe_to_spend subtracts net card obligation', () async {
    final local = _FakeDashboardLocalStore();
    final repository = DashboardRepository(
      local: local,
      nowProvider: () => DateTime.utc(2026, 5, 4),
    );

    final metricsByCurrency = await repository.calculateAllMetrics();
    final mxn = metricsByCurrency['MXN']!;

    expect(mxn.liquidAssetsCents, 100000);
    expect(
      mxn.safeToSpendCents,
      50000,
    ); // 100000 - 20000 goals - 30000 card net
    expect(mxn.buyingPowerCents, 90000); // safe 50000 + revolving 40000
  });
}

class _FakeDashboardLocalStore extends DashboardLocalStore {
  _FakeDashboardLocalStore() : super(db: DatabaseHelper());

  @override
  Future<List<AccountBalanceDTO>> getBalancesPerAccount({
    Set<String>? accountIds,
  }) async {
    return const [
      AccountBalanceDTO(
        accountId: 'bank-1',
        accountName: 'Bank',
        accountType: 'bank',
        currencyCode: 'MXN',
        balanceCents: 100000,
      ),
      AccountBalanceDTO(
        accountId: 'card-1',
        accountName: 'Card',
        accountType: 'credit_card',
        currencyCode: 'MXN',
        balanceCents: -10000,
        creditLimitCents: 50000,
      ),
    ];
  }

  @override
  Future<List<GoalTargetDTO>> getTotalTargetInGoals() async {
    return const [GoalTargetDTO(currencyCode: 'MXN', totalTargetCents: 20000)];
  }

  @override
  Future<List<CreditCardAccountCycleDTO>> getCreditCardAccounts({
    Set<String>? accountIds,
  }) async {
    return const [
      CreditCardAccountCycleDTO(
        accountId: 'card-1',
        currencyCode: 'MXN',
        statementDay: 20,
        paymentDueDay: 5,
      ),
    ];
  }

  @override
  Future<List<CreditCardMovementDTO>> getCreditCardMovementsForProjection(
    String maxDate, {
    Set<String>? accountIds,
    String? currencyCode,
  }) async {
    return const [
      CreditCardMovementDTO(
        accountId: 'card-1',
        type: 'expense',
        amountCents: 28000,
        installmentsCount: 1,
        date: '2026-04-10',
      ),
      CreditCardMovementDTO(
        accountId: 'card-1',
        type: 'expense',
        amountCents: 6000,
        installmentsCount: 3,
        date: '2026-04-15',
      ),
      CreditCardMovementDTO(
        accountId: 'card-1',
        type: 'transfer_in',
        amountCents: 0,
        installmentsCount: 1,
        date: '2026-05-02',
      ),
    ];
  }
}
