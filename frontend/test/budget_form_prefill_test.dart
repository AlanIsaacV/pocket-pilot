import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/features/budgets/ui/budget_form_screen.dart';

void main() {
  test('BudgetFormScreen accepts pre-fill params via constructor', () {
    const screen = BudgetFormScreen(
      initialCategoryId: 'cat-1',
      initialLimitCents: 450000,
      initialCurrencyCode: 'MXN',
    );

    expect(screen.initialCategoryId, 'cat-1');
    expect(screen.initialLimitCents, 450000);
    expect(screen.initialCurrencyCode, 'MXN');
    // Existing behavior preserved: no budget, default category route.
    expect(screen.budget, isNull);
    expect(screen.categoryRoute, '/accounts/budgets/new/category');
  });

  test('BudgetFormScreen keeps defaults when pre-fill params are omitted', () {
    const screen = BudgetFormScreen();
    expect(screen.initialCategoryId, isNull);
    expect(screen.initialLimitCents, isNull);
    expect(screen.initialCurrencyCode, isNull);
  });
}
