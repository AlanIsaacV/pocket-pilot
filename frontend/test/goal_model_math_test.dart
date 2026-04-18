import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/src/features/goals/domain/goal.dart';

void main() {
  final now = DateTime(2026, 4, 10);

  GoalModel makeGoal({
    String id = 'g1',
    required int target,
    required String targetDate,
    String currencyCode = 'MXN',
    DateTime? createdAt,
  }) {
    return GoalModel(
      id: id,
      name: 'Laptop',
      targetAmountCents: target,
      currencyCode: currencyCode,
      targetDate: targetDate,
      createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
  }

  group('GoalModel (liquidity-based)', () {
    test('progress percentage is zero when no liquidity assigned', () {
      final g = makeGoal(target: 10000, targetDate: '2026-12-31');
      expect(g.progressPercentageAt(now), 0);
    });

    test('progress percentage reflects liquidity ratio', () {
      final g = makeGoal(target: 10000, targetDate: '2026-12-31');
      expect(
        g.progressPercentageAt(now, liquidityAssignedCents: 5000),
        closeTo(50, 0.0001),
      );
      expect(
        g.progressPercentageAt(now, liquidityAssignedCents: 10000),
        closeTo(100, 0.0001),
      );
    });

    test('months remaining uses calendar diff with minimum 1', () {
      final future = makeGoal(target: 1000, targetDate: '2026-07-01');
      final currentMonth = makeGoal(target: 1000, targetDate: '2026-04-30');
      final past = makeGoal(target: 1000, targetDate: '2026-03-15');

      expect(future.monthsRemainingAt(now), 3);
      expect(currentMonth.monthsRemainingAt(now), 1);
      expect(past.monthsRemainingAt(now), 1);
    });

    test('monthly required cents uses ceil over full target when no liquidity', () {
      final g = makeGoal(target: 10000, targetDate: '2026-07-01');
      // remaining = 10000 (full target), 3 months => ceil(10000/3) = 3334
      expect(g.monthlyRequiredCentsAt(now), 3334);
    });

    test('monthly required cents subtracts assigned liquidity', () {
      final g = makeGoal(target: 10000, targetDate: '2026-07-01');
      // remaining = 10000 - 4000 = 6000, 3 months => ceil(6000/3) = 2000
      expect(
        g.monthlyRequiredCentsAt(now, liquidityAssignedCents: 4000),
        2000,
      );
    });

    test('monthly required is zero when liquidity covers the target', () {
      final g = makeGoal(target: 10000, targetDate: '2026-07-01');
      expect(
        g.monthlyRequiredCentsAt(now, liquidityAssignedCents: 10000),
        0,
      );
      expect(
        g.monthlyRequiredCentsAt(now, liquidityAssignedCents: 15000),
        0,
      );
    });

    test('monthly required is zero when target is zero', () {
      final g = makeGoal(target: 0, targetDate: '2026-07-01');
      expect(g.monthlyRequiredCentsAt(now), 0);
    });

    test('overdue is true only for past target date when uncovered', () {
      final overdue = makeGoal(target: 10000, targetDate: '2026-03-10');
      final notOverdueCurrent = makeGoal(
        target: 10000,
        targetDate: '2026-04-25',
      );

      expect(overdue.isOverdueAt(now), isTrue);
      expect(notOverdueCurrent.isOverdueAt(now), isFalse);
    });

    test('overdue is false if liquidity covers target even if date passed', () {
      final overdue = makeGoal(target: 10000, targetDate: '2026-03-10');
      expect(
        overdue.isOverdueAt(now, liquidityAssignedCents: 10000),
        isFalse,
      );
      expect(
        overdue.isOverdueAt(now, liquidityAssignedCents: 9999),
        isTrue,
      );
    });
  });

  group('GoalMath.allocateLiquidity', () {
    test('distributes pool FIFO by targetDate ascending', () {
      final g1 = makeGoal(id: 'g1', target: 5000, targetDate: '2026-06-01');
      final g2 = makeGoal(id: 'g2', target: 8000, targetDate: '2026-05-01');
      final g3 = makeGoal(id: 'g3', target: 3000, targetDate: '2026-07-01');

      final allocation = GoalMath.allocateLiquidity([g1, g2, g3], {
        'MXN': 10000,
      });

      // Orden: g2 (May), g1 (June), g3 (July)
      // g2 consume 8000 → pool=2000
      // g1 consume 2000 → pool=0
      // g3 recibe 0
      expect(allocation['g2'], 8000);
      expect(allocation['g1'], 2000);
      expect(allocation['g3'], 0);
    });

    test('does not share pool between currencies', () {
      final mxn = makeGoal(id: 'm', target: 5000, targetDate: '2026-06-01');
      final usd = makeGoal(
        id: 'u',
        target: 5000,
        targetDate: '2026-06-01',
        currencyCode: 'USD',
      );
      final allocation = GoalMath.allocateLiquidity([mxn, usd], {
        'MXN': 3000,
        'USD': 5000,
      });
      expect(allocation['m'], 3000);
      expect(allocation['u'], 5000);
    });

    test('ignores deleted goals', () {
      final active = makeGoal(id: 'a', target: 5000, targetDate: '2026-06-01');
      final deleted = GoalModel(
        id: 'd',
        name: 'Deleted',
        targetAmountCents: 10000,
        currencyCode: 'MXN',
        targetDate: '2026-05-01',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        deletedAt: DateTime.utc(2026, 2, 1),
      );
      final allocation = GoalMath.allocateLiquidity(
        [active, deleted],
        {'MXN': 4000},
      );
      expect(allocation['a'], 4000);
      expect(allocation.containsKey('d'), isFalse);
    });

    test('uses createdAt as tiebreaker when targetDate matches', () {
      final older = makeGoal(
        id: 'older',
        target: 3000,
        targetDate: '2026-06-01',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      final newer = makeGoal(
        id: 'newer',
        target: 3000,
        targetDate: '2026-06-01',
        createdAt: DateTime.utc(2026, 2, 1),
      );
      final allocation = GoalMath.allocateLiquidity(
        [newer, older],
        {'MXN': 4000},
      );
      expect(allocation['older'], 3000);
      expect(allocation['newer'], 1000);
    });

    test('goals with currency absent from pool receive zero', () {
      final g = makeGoal(target: 5000, targetDate: '2026-06-01');
      final allocation = GoalMath.allocateLiquidity([g], const {});
      expect(allocation['g1'], 0);
    });
  });

  group('GoalMath.totalMonthlyRequiredCents', () {
    test('sums active goals only, no liquidity', () {
      final g1 = makeGoal(id: 'g1', target: 10000, targetDate: '2026-07-01');
      final g2 = makeGoal(id: 'g2', target: 6000, targetDate: '2026-05-01');
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

      final total = GoalMath.totalMonthlyRequiredCents(
        [g1, g2, deleted],
        now: now,
      );
      // g1: ceil(10000/3) = 3334, g2: ceil(6000/1) = 6000
      expect(total, 3334 + 6000);
    });

    test('applies FIFO liquidity to reduce monthly obligations', () {
      final g1 = makeGoal(id: 'g1', target: 10000, targetDate: '2026-07-01');
      final g2 = makeGoal(id: 'g2', target: 6000, targetDate: '2026-05-01');

      // pool = 6000 → g2 (May) cubre full → 0; g1 recibe 0 → ceil(10000/3)=3334
      final total = GoalMath.totalMonthlyRequiredCents(
        [g1, g2],
        now: now,
        liquidByCurrency: {'MXN': 6000},
      );
      expect(total, 3334);
    });
  });
}
