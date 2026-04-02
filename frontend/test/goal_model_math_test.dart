import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/src/features/goals/domain/goal.dart';

void main() {
  final now = DateTime(2026, 4, 10);

  GoalModel makeGoal({
    required int target,
    required int saved,
    required String targetDate,
  }) {
    return GoalModel(
      id: 'g1',
      name: 'Laptop',
      targetAmountCents: target,
      savedAmountCents: saved,
      targetDate: targetDate,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
  }

  test('progress percentage', () {
    final g = makeGoal(
      target: 4800000,
      saved: 1200000,
      targetDate: '2026-12-31',
    );
    expect(g.progressPercentage, closeTo(25.0, 0.0001));
  });

  test('months remaining uses calendar diff with minimum 1', () {
    final future = makeGoal(target: 1000, saved: 0, targetDate: '2026-07-01');
    final currentMonth = makeGoal(
      target: 1000,
      saved: 0,
      targetDate: '2026-04-30',
    );
    final past = makeGoal(target: 1000, saved: 0, targetDate: '2026-03-15');

    expect(future.monthsRemainingAt(now), 3);
    expect(currentMonth.monthsRemainingAt(now), 1);
    expect(past.monthsRemainingAt(now), 1);
  });

  test('monthly required cents uses ceil', () {
    final g = makeGoal(target: 10000, saved: 0, targetDate: '2026-07-01');
    expect(g.monthlyRequiredCentsAt(now), 3334);
  });

  test('monthly required is zero when goal already completed', () {
    final g = makeGoal(target: 10000, saved: 10000, targetDate: '2026-07-01');
    expect(g.monthlyRequiredCentsAt(now), 0);
  });

  test('overdue is true only for past month and incomplete goal', () {
    final overdue = makeGoal(
      target: 10000,
      saved: 2000,
      targetDate: '2026-03-10',
    );
    final notOverdueCurrent = makeGoal(
      target: 10000,
      saved: 2000,
      targetDate: '2026-04-25',
    );
    final completedPast = makeGoal(
      target: 10000,
      saved: 10000,
      targetDate: '2026-03-10',
    );

    expect(overdue.isOverdueAt(now), isTrue);
    expect(notOverdueCurrent.isOverdueAt(now), isFalse);
    expect(completedPast.isOverdueAt(now), isFalse);
  });

  test('dashboard aggregate sums active goals only', () {
    final g1 = makeGoal(target: 10000, saved: 0, targetDate: '2026-07-01');
    final g2 = makeGoal(target: 6000, saved: 0, targetDate: '2026-05-01');
    final deleted = GoalModel(
      id: 'g3',
      name: 'Deleted',
      targetAmountCents: 10000,
      savedAmountCents: 0,
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
    expect(total, 3334 + 6000);
  });
}
