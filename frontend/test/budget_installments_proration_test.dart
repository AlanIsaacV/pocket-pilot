import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/features/budgets/data/budget_local_store.dart';

void main() {
  test('one-shot contributes full amount when month overlaps', () {
    final amount = BudgetLocalStore.proratedAmountForPeriod(
      amountCents: 1000,
      installmentsCount: 1,
      purchaseMonthIndex: 2026 * 12 + 3, // 2026-04
      periodStartMonthIndex: 2026 * 12 + 3,
      periodEndMonthIndex: 2026 * 12 + 3,
    );

    expect(amount, 1000);
  });

  test('residual goes to first month only', () {
    final april = BudgetLocalStore.proratedAmountForPeriod(
      amountCents: 1000,
      installmentsCount: 3,
      purchaseMonthIndex: 2026 * 12 + 3,
      periodStartMonthIndex: 2026 * 12 + 3,
      periodEndMonthIndex: 2026 * 12 + 3,
    );
    final may = BudgetLocalStore.proratedAmountForPeriod(
      amountCents: 1000,
      installmentsCount: 3,
      purchaseMonthIndex: 2026 * 12 + 3,
      periodStartMonthIndex: 2026 * 12 + 4,
      periodEndMonthIndex: 2026 * 12 + 4,
    );

    expect(april, 334);
    expect(may, 333);
  });

  test('yearly overlap includes only months inside target year', () {
    final amount = BudgetLocalStore.proratedAmountForPeriod(
      amountCents: 1001,
      installmentsCount: 3,
      purchaseMonthIndex: 2025 * 12 + 11, // 2025-12
      periodStartMonthIndex: 2026 * 12 + 0, // 2026-01
      periodEndMonthIndex: 2026 * 12 + 11, // 2026-12
    );

    expect(amount, 666); // Jan+Feb only, residual was in Dec 2025
  });
}
