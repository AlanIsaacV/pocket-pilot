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

  // TODO(liquidity): reemplazar por liquidezAcumulada / targetAmountCents * 100
  double progressPercentageAt(DateTime nowLocal) {
    final total = _totalMonths();
    if (total <= 0) return 0;
    final elapsed = monthsElapsedAt(nowLocal);
    return (elapsed / total) * 100;
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

  // TODO(liquidity): remaining = targetAmountCents - liquidezAsignada
  int monthlyRequiredCentsAt(DateTime nowLocal) {
    final remaining = targetAmountCents;
    if (remaining <= 0) {
      return 0;
    }

    final months = monthsRemainingAt(nowLocal);
    return (remaining + months - 1) ~/ months;
  }

  int get monthlyRequiredCents => monthlyRequiredCentsAt(DateTime.now());

  // TODO(liquidity): no marcar overdue si liquidez ya cubre el target
  bool isOverdueAt(DateTime nowLocal) {
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
  static int totalMonthlyRequiredCents(
    Iterable<GoalModel> goals, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    return goals.where((goal) => goal.deletedAt == null).fold(0, (sum, goal) {
      return sum + goal.monthlyRequiredCentsAt(current);
    });
  }
}
