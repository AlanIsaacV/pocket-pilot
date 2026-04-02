import 'package:pocket_pilot/src/features/budgets/domain/budget.dart';

class BudgetStatus {
  final BudgetModel budget;
  final int spentAmountCents;

  const BudgetStatus({
    required this.budget,
    required this.spentAmountCents,
  });

  int get remainingAmountCents => budget.limitAmountCents - spentAmountCents;

  double get progressPercentage => budget.limitAmountCents > 0
      ? (spentAmountCents / budget.limitAmountCents) * 100
      : 0;
}
