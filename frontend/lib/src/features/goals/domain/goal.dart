import 'package:fixnum/fixnum.dart';

import 'package:pocket_pilot/src/generated/pocket_pilot/v1/goal_service.pbgrpc.dart';

class GoalModel {
  final String id;
  final String name;
  final int targetAmountCents;
  final String currencyCode;
  final String targetDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const GoalModel({
    required this.id,
    required this.name,
    required this.targetAmountCents,
    required this.currencyCode,
    required this.targetDate,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory GoalModel.fromProto(Goal proto) {
    return GoalModel(
      id: proto.id,
      name: proto.name,
      targetAmountCents: proto.targetAmountCents.toInt(),
      currencyCode: proto.currencyCode,
      targetDate: _dateOnly(proto.targetDate),
      createdAt: proto.createdAt.toDateTime().toUtc(),
      updatedAt: proto.updatedAt.toDateTime().toUtc(),
      deletedAt: proto.hasDeletedAt()
          ? proto.deletedAt.toDateTime().toUtc()
          : null,
    );
  }

  factory GoalModel.fromMap(Map<String, dynamic> map) {
    return GoalModel(
      id: map['id'] as String,
      name: map['name'] as String,
      targetAmountCents: _asInt(map['target_amount_cents']),
      currencyCode: map['currency_code'] as String,
      targetDate: _dateOnly(map['target_date'] as String),
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String).toUtc()
          : null,
    );
  }

  GoalModel normalized() {
    return GoalModel(
      id: id,
      name: name.trim(),
      targetAmountCents: targetAmountCents,
      currencyCode: currencyCode,
      targetDate: _dateOnly(targetDate),
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
      deletedAt: deletedAt?.toUtc(),
    );
  }

  Map<String, dynamic> toMap() {
    final n = normalized();
    return {
      'id': n.id,
      'name': n.name,
      'target_amount_cents': n.targetAmountCents,
      'currency_code': n.currencyCode,
      'target_date': n.targetDate,
      'created_at': n.createdAt.toIso8601String(),
      'updated_at': n.updatedAt.toIso8601String(),
      'deleted_at': n.deletedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toServerMap() {
    final n = normalized();
    return {
      'id': n.id,
      'name': n.name,
      'target_amount_cents': n.targetAmountCents,
      'currency_code': n.currencyCode,
      'target_date': n.targetDate,
      'created_at': n.createdAt.toIso8601String(),
      'updated_at': n.updatedAt.toIso8601String(),
      'deleted_at': n.deletedAt?.toIso8601String(),
    };
  }

  Goal toProto() {
    final n = normalized();
    return Goal(
      id: n.id,
      name: n.name,
      targetAmountCents: Int64(n.targetAmountCents),
      currencyCode: n.currencyCode,
      targetDate: n.targetDate,
    );
  }

  // ----------------------------------------------------------
  // Propiedades computadas
  // ----------------------------------------------------------

  int _totalMonths() {
    final created = DateTime(createdAt.year, createdAt.month, 1);
    final target = DateTime.parse(_dateOnly(targetDate));
    final targetMonth = DateTime(target.year, target.month, 1);
    final months =
        (targetMonth.year - created.year) * 12 +
        (targetMonth.month - created.month);
    return months < 1 ? 1 : months;
  }

  int monthsElapsedAt(DateTime nowLocal) {
    final created = DateTime(createdAt.year, createdAt.month, 1);
    final nowMonth = DateTime(nowLocal.year, nowLocal.month, 1);
    final elapsed =
        (nowMonth.year - created.year) * 12 +
        (nowMonth.month - created.month);
    final total = _totalMonths();
    if (elapsed < 0) return 0;
    return elapsed > total ? total : elapsed;
  }

  double progressPercentageAt(
    DateTime nowLocal, {
    int liquidityAssignedCents = 0,
  }) {
    if (targetAmountCents <= 0) return 0;
    return (liquidityAssignedCents / targetAmountCents) * 100;
  }

  double get progressPercentage => progressPercentageAt(DateTime.now());

  int monthsRemainingAt(DateTime nowLocal) {
    final nowMonthStart = DateTime(nowLocal.year, nowLocal.month, 1);
    final targetLocal = DateTime.parse(_dateOnly(targetDate));
    final targetMonthStart = DateTime(targetLocal.year, targetLocal.month, 1);
    final months =
        (targetMonthStart.year - nowMonthStart.year) * 12 +
        (targetMonthStart.month - nowMonthStart.month);

    if (months <= 0) {
      return 1;
    }

    return months;
  }

  int get monthsRemaining => monthsRemainingAt(DateTime.now());

  int monthlyRequiredCentsAt(
    DateTime nowLocal, {
    int liquidityAssignedCents = 0,
  }) {
    final remaining = targetAmountCents - liquidityAssignedCents;
    if (remaining <= 0) {
      return 0;
    }

    final months = monthsRemainingAt(nowLocal);
    return (remaining + months - 1) ~/ months;
  }

  int get monthlyRequiredCents => monthlyRequiredCentsAt(DateTime.now());

  bool isOverdueAt(
    DateTime nowLocal, {
    int liquidityAssignedCents = 0,
  }) {
    if (liquidityAssignedCents >= targetAmountCents) return false;
    final nowMonthStart = DateTime(nowLocal.year, nowLocal.month, 1);
    final targetLocal = DateTime.parse(_dateOnly(targetDate));
    final targetMonthStart = DateTime(targetLocal.year, targetLocal.month, 1);
    return targetMonthStart.isBefore(nowMonthStart);
  }

  bool get isOverdue => isOverdueAt(DateTime.now());

  static String _dateOnly(String value) {
    return value.length >= 10 ? value.substring(0, 10) : value;
  }

  static int _asInt(Object raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.parse(raw.toString());
  }
}

class GoalMath {
  /// Reparte la liquidez por moneda entre las metas activas usando FIFO por
  /// `targetDate` ascendente (desempate estable por `createdAt`).
  /// Devuelve `Map<goalId, liquidityAssignedCents>`. Las metas en una moneda
  /// sin entrada en [liquidByCurrency] reciben 0.
  static Map<String, int> allocateLiquidity(
    Iterable<GoalModel> goals,
    Map<String, int> liquidByCurrency,
  ) {
    final result = <String, int>{};
    final grouped = <String, List<GoalModel>>{};
    for (final goal in goals) {
      if (goal.deletedAt != null) continue;
      grouped.putIfAbsent(goal.currencyCode, () => []).add(goal);
    }

    grouped.forEach((currency, currencyGoals) {
      currencyGoals.sort((a, b) {
        final byDate = a.targetDate.compareTo(b.targetDate);
        if (byDate != 0) return byDate;
        return a.createdAt.compareTo(b.createdAt);
      });

      var pool = liquidByCurrency[currency] ?? 0;
      if (pool < 0) pool = 0;

      for (final goal in currencyGoals) {
        if (pool <= 0 || goal.targetAmountCents <= 0) {
          result[goal.id] = 0;
          continue;
        }
        final take = pool >= goal.targetAmountCents
            ? goal.targetAmountCents
            : pool;
        result[goal.id] = take;
        pool -= take;
      }
    });

    return result;
  }

  static int totalMonthlyRequiredCents(
    Iterable<GoalModel> goals, {
    DateTime? now,
    Map<String, int> liquidByCurrency = const {},
  }) {
    final current = now ?? DateTime.now();
    final active = goals.where((goal) => goal.deletedAt == null).toList();
    final allocation = liquidByCurrency.isEmpty
        ? const <String, int>{}
        : allocateLiquidity(active, liquidByCurrency);

    return active.fold(0, (sum, goal) {
      final liquidity = allocation[goal.id] ?? 0;
      return sum +
          goal.monthlyRequiredCentsAt(
            current,
            liquidityAssignedCents: liquidity,
          );
    });
  }
}
