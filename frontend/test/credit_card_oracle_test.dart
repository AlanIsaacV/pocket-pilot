import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_account_cycle_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_movement_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_oracle.dart';

void main() {
  test('cycle mode includes one-shot + MSI and nets applied payments', () {
    final oracle = CreditCardOracle();
    final result = oracle.estimateNetMonthlyObligation(
      targetMonth: DateTime.utc(2026, 5, 1),
      now: DateTime.utc(2026, 5, 4),
      accounts: const [
        CreditCardAccountCycleDTO(
          accountId: 'card-1',
          currencyCode: 'MXN',
          statementDay: 20,
          paymentDueDay: 5,
        ),
      ],
      movements: const [
        CreditCardMovementDTO(
          accountId: 'card-1',
          type: 'expense',
          amountCents: 30000,
          installmentsCount: 1,
          date: '2026-04-10',
        ),
        CreditCardMovementDTO(
          accountId: 'card-1',
          type: 'expense',
          amountCents: 12000,
          installmentsCount: 3,
          date: '2026-04-15',
        ),
        CreditCardMovementDTO(
          accountId: 'card-1',
          type: 'transfer_in',
          amountCents: 2000,
          installmentsCount: 1,
          date: '2026-05-02',
        ),
      ],
    );

    expect(result.netByCurrency['MXN'], 32000);
    expect(result.netByAccountId['card-1'], 32000);
  });

  test('residual goes to first installment only', () {
    final oracle = CreditCardOracle();
    final accounts = const [
      CreditCardAccountCycleDTO(
        accountId: 'card-1',
        currencyCode: 'MXN',
        statementDay: 20,
        paymentDueDay: 5,
      ),
    ];
    const movements = [
      CreditCardMovementDTO(
        accountId: 'card-1',
        type: 'expense',
        amountCents: 1000,
        installmentsCount: 3,
        date: '2026-04-15',
      ),
    ];

    final may = oracle.estimateNetMonthlyObligation(
      targetMonth: DateTime.utc(2026, 5, 1),
      now: DateTime.utc(2026, 5, 3),
      accounts: accounts,
      movements: movements,
    );
    final jun = oracle.estimateNetMonthlyObligation(
      targetMonth: DateTime.utc(2026, 6, 1),
      now: DateTime.utc(2026, 6, 3),
      accounts: accounts,
      movements: movements,
    );

    expect(may.netByCurrency['MXN'], 334);
    expect(jun.netByCurrency['MXN'], 333);
  });

  test('fallback mode uses calendar and floors net at zero', () {
    final oracle = CreditCardOracle();
    final result = oracle.estimateNetMonthlyObligation(
      targetMonth: DateTime.utc(2026, 6, 1),
      now: DateTime.utc(2026, 6, 10),
      accounts: const [
        CreditCardAccountCycleDTO(
          accountId: 'card-2',
          currencyCode: 'USD',
          statementDay: null,
          paymentDueDay: null,
        ),
      ],
      movements: const [
        CreditCardMovementDTO(
          accountId: 'card-2',
          type: 'expense',
          amountCents: 4000,
          installmentsCount: 1,
          date: '2026-05-12',
        ),
        CreditCardMovementDTO(
          accountId: 'card-2',
          type: 'expense',
          amountCents: 1001,
          installmentsCount: 2,
          date: '2026-05-15',
        ),
        CreditCardMovementDTO(
          accountId: 'card-2',
          type: 'income',
          amountCents: 6000,
          installmentsCount: 1,
          date: '2026-06-03',
        ),
      ],
    );

    expect(result.netByCurrency['USD'], 0);
  });
}
