import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_account_cycle_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_movement_dto.dart';
import 'package:pocket_pilot/src/features/dashboard/domain/credit_card_oracle.dart';

void main() {
  test('cycle mode includes one-shot + MSI and nets applied payments', () {
    // statement_day=20, payment_due_day=5, targetMonth=May
    // Cycle: (Apr 20, May 20].  Previous due date: May 5.
    // Charges dated after Apr 20 land in this cycle.
    // Payments after May 5 reduce the obligation.
    final oracle = CreditCardOracle();
    final result = oracle.estimateNetMonthlyObligation(
      targetMonth: DateTime.utc(2026, 5, 1),
      now: DateTime.utc(2026, 5, 10),
      accounts: const [
        CreditCardAccountCycleDTO(
          accountId: 'card-1',
          currencyCode: 'MXN',
          statementDay: 20,
          paymentDueDay: 5,
        ),
      ],
      movements: const [
        // One-shot charge in current cycle (after Apr 20)
        CreditCardMovementDTO(
          accountId: 'card-1',
          type: 'expense',
          amountCents: 30000,
          installmentsCount: 1,
          date: '2026-04-25',
        ),
        // 3-MSI charge in current cycle (after Apr 20)
        CreditCardMovementDTO(
          accountId: 'card-1',
          type: 'expense',
          amountCents: 12000,
          installmentsCount: 3,
          date: '2026-04-28',
        ),
        // Payment after previous due date (May 5)
        CreditCardMovementDTO(
          accountId: 'card-1',
          type: 'transfer_in',
          amountCents: 2000,
          installmentsCount: 1,
          date: '2026-05-06',
        ),
      ],
    );

    // gross = 30000 + 4000 (first installment of 12000/3) = 34000
    // payments = 2000
    // net = 32000
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
    // 3-MSI purchase after Apr 20 → first installment in May cycle,
    // second in June cycle.
    const movements = [
      CreditCardMovementDTO(
        accountId: 'card-1',
        type: 'expense',
        amountCents: 1000,
        installmentsCount: 3,
        date: '2026-04-25',
      ),
    ];

    final may = oracle.estimateNetMonthlyObligation(
      targetMonth: DateTime.utc(2026, 5, 1),
      now: DateTime.utc(2026, 5, 22),
      accounts: accounts,
      movements: movements,
    );
    final jun = oracle.estimateNetMonthlyObligation(
      targetMonth: DateTime.utc(2026, 6, 1),
      now: DateTime.utc(2026, 6, 22),
      accounts: accounts,
      movements: movements,
    );

    // 1000 / 3 = 333 base, residual 1 → first installment 334, rest 333
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

  test('income adjustment is not counted as payment', () {
    final oracle = CreditCardOracle();
    final result = oracle.estimateNetMonthlyObligation(
      targetMonth: DateTime.utc(2026, 4, 1),
      now: DateTime.utc(2026, 4, 15),
      accounts: const [
        CreditCardAccountCycleDTO(
          accountId: 'card-1',
          currencyCode: 'MXN',
          statementDay: 24,
          paymentDueDay: 14,
        ),
      ],
      movements: const [
        // Charge in the current cycle (after Mar 24)
        CreditCardMovementDTO(
          accountId: 'card-1',
          type: 'expense',
          amountCents: 50000,
          installmentsCount: 1,
          date: '2026-03-28',
        ),
        // Positive adjustment — should NOT reduce obligation
        CreditCardMovementDTO(
          accountId: 'card-1',
          type: 'income',
          amountCents: 100000,
          installmentsCount: 1,
          date: '2026-04-14',
          nature: 'adjustment',
        ),
      ],
    );

    // gross = 50000, payments = 0 (adjustment excluded)
    expect(result.netByAccountId['card-1'], 50000);
  });

  test('expense adjustment IS counted as charge', () {
    final oracle = CreditCardOracle();
    final result = oracle.estimateNetMonthlyObligation(
      targetMonth: DateTime.utc(2026, 4, 1),
      now: DateTime.utc(2026, 4, 15),
      accounts: const [
        CreditCardAccountCycleDTO(
          accountId: 'card-1',
          currencyCode: 'MXN',
          statementDay: 24,
          paymentDueDay: 14,
        ),
      ],
      movements: const [
        CreditCardMovementDTO(
          accountId: 'card-1',
          type: 'expense',
          amountCents: 50000,
          installmentsCount: 1,
          date: '2026-03-28',
        ),
        // Negative adjustment = unregistered charge, should be counted
        CreditCardMovementDTO(
          accountId: 'card-1',
          type: 'expense',
          amountCents: 10000,
          installmentsCount: 1,
          date: '2026-04-01',
          nature: 'adjustment',
        ),
      ],
    );

    expect(result.netByAccountId['card-1'], 60000);
  });

  test('payment for previous cycle is not subtracted', () {
    // statement_day=24, payment_due_day=14, April
    // Cycle: (Mar 24, Apr 24].  Previous due date: Apr 14.
    // A transfer_in on Mar 25 is BEFORE the previous due date,
    // so it belongs to the prior cycle and should not reduce the
    // current obligation.
    final oracle = CreditCardOracle();
    final result = oracle.estimateNetMonthlyObligation(
      targetMonth: DateTime.utc(2026, 4, 1),
      now: DateTime.utc(2026, 4, 14),
      accounts: const [
        CreditCardAccountCycleDTO(
          accountId: 'bbva',
          currencyCode: 'MXN',
          statementDay: 24,
          paymentDueDay: 14,
        ),
      ],
      movements: const [
        // Charge in current cycle
        CreditCardMovementDTO(
          accountId: 'bbva',
          type: 'expense',
          amountCents: 8000000,
          installmentsCount: 1,
          date: '2026-04-01',
        ),
        // Payment for the PREVIOUS statement (before due date Apr 14)
        CreditCardMovementDTO(
          accountId: 'bbva',
          type: 'transfer_in',
          amountCents: 2752040,
          installmentsCount: 1,
          date: '2026-03-25',
        ),
      ],
    );

    // Only the charge counts; the payment is for a prior cycle
    expect(result.netByAccountId['bbva'], 8000000);
  });

  test('BBVA TC real-world: cycle charges + MSI + adjustment ignored', () {
    // Reproduces the BBVA TC scenario:
    //   statement_day=24, payment_due_day=14, April 2026
    //   Cycle: (Mar 24, Apr 24].  now = Apr 14 (mid-cycle).
    final oracle = CreditCardOracle();
    final result = oracle.estimateNetMonthlyObligation(
      targetMonth: DateTime.utc(2026, 4, 1),
      now: DateTime.utc(2026, 4, 14),
      accounts: const [
        CreditCardAccountCycleDTO(
          accountId: 'bbva-tc',
          currencyCode: 'MXN',
          statementDay: 24,
          paymentDueDay: 14,
        ),
      ],
      movements: const [
        // --- Charges in current cycle (after Mar 24, up to now Apr 14) ---
        CreditCardMovementDTO(
          accountId: 'bbva-tc',
          type: 'expense',
          amountCents: 6550801,
          installmentsCount: 1,
          date: '2026-03-25',
          nature: 'obligation',
        ),
        CreditCardMovementDTO(
          accountId: 'bbva-tc',
          type: 'expense',
          amountCents: 42100,
          installmentsCount: 1,
          date: '2026-03-25',
          nature: 'obligation',
        ),
        CreditCardMovementDTO(
          accountId: 'bbva-tc',
          type: 'expense',
          amountCents: 273753,
          installmentsCount: 1,
          date: '2026-03-25',
          nature: 'lifestyle',
        ),
        CreditCardMovementDTO(
          accountId: 'bbva-tc',
          type: 'expense',
          amountCents: 1652730,
          installmentsCount: 12,
          date: '2026-03-26',
          nature: 'lifestyle',
        ),
        CreditCardMovementDTO(
          accountId: 'bbva-tc',
          type: 'expense',
          amountCents: 1040262,
          installmentsCount: 1,
          date: '2026-03-27',
          nature: 'lifestyle',
        ),
        CreditCardMovementDTO(
          accountId: 'bbva-tc',
          type: 'expense',
          amountCents: 986300,
          installmentsCount: 1,
          date: '2026-03-30',
          nature: 'lifestyle',
        ),
        CreditCardMovementDTO(
          accountId: 'bbva-tc',
          type: 'expense',
          amountCents: 1033986,
          installmentsCount: 1,
          date: '2026-04-01',
          nature: 'lifestyle',
        ),
        CreditCardMovementDTO(
          accountId: 'bbva-tc',
          type: 'expense',
          amountCents: 65686,
          installmentsCount: 1,
          date: '2026-04-01',
          nature: 'lifestyle',
        ),
        CreditCardMovementDTO(
          accountId: 'bbva-tc',
          type: 'expense',
          amountCents: 676019,
          installmentsCount: 1,
          date: '2026-04-02',
          nature: 'lifestyle',
        ),
        CreditCardMovementDTO(
          accountId: 'bbva-tc',
          type: 'expense',
          amountCents: 93600,
          installmentsCount: 1,
          date: '2026-04-02',
          nature: 'lifestyle',
        ),
        CreditCardMovementDTO(
          accountId: 'bbva-tc',
          type: 'expense',
          amountCents: 12000,
          installmentsCount: 1,
          date: '2026-04-03',
          nature: 'lifestyle',
        ),
        CreditCardMovementDTO(
          accountId: 'bbva-tc',
          type: 'expense',
          amountCents: 75000,
          installmentsCount: 1,
          date: '2026-04-07',
          nature: 'obligation',
        ),
        CreditCardMovementDTO(
          accountId: 'bbva-tc',
          type: 'expense',
          amountCents: 31900,
          installmentsCount: 1,
          date: '2026-04-07',
          nature: 'lifestyle',
        ),
        CreditCardMovementDTO(
          accountId: 'bbva-tc',
          type: 'expense',
          amountCents: 133430,
          installmentsCount: 1,
          date: '2026-04-07',
          nature: 'lifestyle',
        ),
        CreditCardMovementDTO(
          accountId: 'bbva-tc',
          type: 'expense',
          amountCents: 108900,
          installmentsCount: 1,
          date: '2026-04-10',
          nature: 'lifestyle',
        ),
        CreditCardMovementDTO(
          accountId: 'bbva-tc',
          type: 'expense',
          amountCents: 187832,
          installmentsCount: 1,
          date: '2026-04-13',
          nature: 'required',
        ),
        CreditCardMovementDTO(
          accountId: 'bbva-tc',
          type: 'expense',
          amountCents: 300805,
          installmentsCount: 1,
          date: '2026-04-13',
          nature: 'lifestyle',
        ),
        CreditCardMovementDTO(
          accountId: 'bbva-tc',
          type: 'expense',
          amountCents: 201852,
          installmentsCount: 1,
          date: '2026-04-13',
          nature: 'required',
        ),
        CreditCardMovementDTO(
          accountId: 'bbva-tc',
          type: 'expense',
          amountCents: 18975,
          installmentsCount: 1,
          date: '2026-04-13',
          nature: 'lifestyle',
        ),
        CreditCardMovementDTO(
          accountId: 'bbva-tc',
          type: 'expense',
          amountCents: 172418,
          installmentsCount: 1,
          date: '2026-04-13',
          nature: 'lifestyle',
        ),
        // --- Should NOT affect: previous cycle payment ---
        CreditCardMovementDTO(
          accountId: 'bbva-tc',
          type: 'transfer_in',
          amountCents: 2752040,
          installmentsCount: 1,
          date: '2026-03-25',
        ),
        // --- Should NOT affect: positive income adjustment ---
        CreditCardMovementDTO(
          accountId: 'bbva-tc',
          type: 'income',
          amountCents: 6032909,
          installmentsCount: 1,
          date: '2026-04-14',
          nature: 'adjustment',
        ),
      ],
    );

    // One-shot charges: 6550801 + 42100 + 273753 + 1040262 + 986300
    //   + 1033986 + 65686 + 676019 + 93600 + 12000 + 75000 + 31900
    //   + 133430 + 108900 + 187832 + 300805 + 201852 + 18975 + 172418
    //   = 12005619
    // MSI 1652730 / 12: base 137727, residual 6 → first installment 137733
    // Total gross: 12005619 + 137733 = 12143352
    // Payments: 0 (transfer_in before due date; adjustment excluded)
    expect(result.netByAccountId['bbva-tc'], 12143352);
    expect(result.netByCurrency['MXN'], 12143352);
  });

  test('charges beyond now are not counted in mid-cycle projection', () {
    final oracle = CreditCardOracle();
    final result = oracle.estimateNetMonthlyObligation(
      targetMonth: DateTime.utc(2026, 4, 1),
      now: DateTime.utc(2026, 4, 5),
      accounts: const [
        CreditCardAccountCycleDTO(
          accountId: 'card-1',
          currencyCode: 'MXN',
          statementDay: 24,
          paymentDueDay: 14,
        ),
      ],
      movements: const [
        CreditCardMovementDTO(
          accountId: 'card-1',
          type: 'expense',
          amountCents: 10000,
          installmentsCount: 1,
          date: '2026-04-01',
        ),
        // This charge is after now (Apr 5) but before cycle close (Apr 24).
        // It should NOT be counted yet.
        CreditCardMovementDTO(
          accountId: 'card-1',
          type: 'expense',
          amountCents: 20000,
          installmentsCount: 1,
          date: '2026-04-10',
        ),
      ],
    );

    expect(result.netByAccountId['card-1'], 10000);
  });
}
