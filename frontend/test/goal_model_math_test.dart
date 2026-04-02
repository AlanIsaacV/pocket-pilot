import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/src/features/goals/domain/goal.dart';

void main() {
  final now = DateTime(2026, 4, 10);

  GoalModel makeGoal({
    required int target,
    required String targetDate,
    DateTime? createdAt,
  }) {
    return GoalModel(
      id: 'g1',
      name: 'Laptop',
      targetAmountCents: target,
      currencyCode: 'MXN',
      targetDate: targetDate,
      createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
  }

  test('progress percentage based on elapsed time', () {
    // Created Jan 2026, target Dec 2026 = 11 months total
    // At Apr 10 2026, 3 months elapsed => 3/11 * 100 = ~27.27%
    final g = makeGoal(target: 4800000, targetDate: '2026-12-31');
    expect(g.progressPercentageAt(now), closeTo(27.27, 0.1));
  });

  test('months remaining uses calendar diff with minimum 1', () {
    final future = makeGoal(target: 1000, targetDate: '2026-07-01');
    final currentMonth = makeGoal(target: 1000, targetDate: '2026-04-30');
    final past = makeGoal(target: 1000, targetDate: '2026-03-15');

    expect(future.monthsRemainingAt(now), 3);
    expect(currentMonth.monthsRemainingAt(now), 1);
    expect(past.monthsRemainingAt(now), 1);
  });

  test('monthly required cents uses ceil over full target', () {
    final g = makeGoal(target: 10000, targetDate: '2026-07-01');
    // remaining = 10000 (full target), 3 months => ceil(10000/3) = 3334
    expect(g.monthlyRequiredCentsAt(now), 3334);
  });

  test('monthly required is zero when target is zero', () {
    final g = makeGoal(target: 0, targetDate: '2026-07-01');
    expect(g.monthlyRequiredCentsAt(now), 0);
  });

  test('overdue is true only for past target date', () {
    final overdue = makeGoal(target: 10000, targetDate: '2026-03-10');
    final notOverdueCurrent = makeGoal(
      target: 10000,
      targetDate: '2026-04-25',
    );

    expect(overdue.isOverdueAt(now), isTrue);
    expect(notOverdueCurrent.isOverdueAt(now), isFalse);
  });

  test('dashboard aggregate sums active goals only', () {
    final g1 = makeGoal(target: 10000, targetDate: '2026-07-01');
    final g2 = makeGoal(target: 6000, targetDate: '2026-05-01');
    final deleted = GoalModel(
      id: 'g3',
      name: 'Deleted',
      targetAmountCents: 10000,
      currencyCode: 'MXN',
      targetDate: '2026-07-01',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      deletedAt: DateTime.utc(2026, 2, 1),
    );

    final total = GoalMath.totalMonthlyRequiredCents([
      g1,
      g2,
      deleted,
    ], now: now);
    // g1: ceil(10000/3) = 3334, g2: ceil(6000/1) = 6000
    expect(total, 3334 + 6000);
  });
}
