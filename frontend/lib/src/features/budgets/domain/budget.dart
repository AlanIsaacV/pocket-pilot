import 'package:fixnum/fixnum.dart';

import 'package:pocket_pilot/src/generated/pocket_pilot/v1/budget_service.pbgrpc.dart';

class BudgetModel {
  final String id;
  final String categoryId;
  final int limitAmountCents;
  final String currencyCode;
  final String period; // 'MONTHLY' o 'YEARLY'
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const BudgetModel({
    required this.id,
    required this.categoryId,
    required this.limitAmountCents,
    required this.currencyCode,
    required this.period,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory BudgetModel.fromProto(Budget proto) {
    return BudgetModel(
      id: proto.id,
      categoryId: proto.categoryId,
      limitAmountCents: proto.limitAmountCents.toInt(),
      currencyCode: proto.currencyCode,
      period: proto.period.toUpperCase(),
      createdAt: proto.createdAt.toDateTime().toUtc(),
      updatedAt: proto.updatedAt.toDateTime().toUtc(),
      deletedAt:
          proto.hasDeletedAt() ? proto.deletedAt.toDateTime().toUtc() : null,
    );
  }

  factory BudgetModel.fromMap(Map<String, dynamic> map) {
    return BudgetModel(
      id: map['id'] as String,
      categoryId: map['category_id'] as String,
      limitAmountCents: _asInt(map['limit_amount_cents']),
      currencyCode: map['currency_code'] as String,
      period: (map['period'] as String).toUpperCase(),
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String).toUtc()
          : null,
    );
  }

  BudgetModel normalized() {
    return BudgetModel(
      id: id,
      categoryId: categoryId,
      limitAmountCents: limitAmountCents,
      currencyCode: currencyCode,
      period: period.toUpperCase(),
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
      deletedAt: deletedAt?.toUtc(),
    );
  }

  Map<String, dynamic> toMap() {
    final n = normalized();
    return {
      'id': n.id,
      'category_id': n.categoryId,
      'limit_amount_cents': n.limitAmountCents,
      'currency_code': n.currencyCode,
      'period': n.period,
      'created_at': n.createdAt.toIso8601String(),
      'updated_at': n.updatedAt.toIso8601String(),
      'deleted_at': n.deletedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toServerMap() {
    final n = normalized();
    return {
      'id': n.id,
      'category_id': n.categoryId,
      'limit_amount_cents': n.limitAmountCents,
      'currency_code': n.currencyCode,
      'period': n.period,
      'created_at': n.createdAt.toIso8601String(),
      'updated_at': n.updatedAt.toIso8601String(),
      'deleted_at': n.deletedAt?.toIso8601String(),
    };
  }

  Budget toProto() {
    final n = normalized();
    return Budget(
      id: n.id,
      categoryId: n.categoryId,
      limitAmountCents: Int64(n.limitAmountCents),
      currencyCode: n.currencyCode,
      period: n.period,
    );
  }

  static int _asInt(Object raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.parse(raw.toString());
  }
}
