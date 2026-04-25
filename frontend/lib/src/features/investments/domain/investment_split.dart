import 'package:pocket_pilot/src/generated/pocket_pilot/v1/investment_split_service.pbgrpc.dart';

/// A stock split (forward or reverse) on a holding. Math walks the union of
/// `(lots ∪ splits)` chronologically and adjusts the FIFO state in flight:
/// at a split with ratio = num/den, every queued lot gets `qty *= ratio` and
/// `price /= ratio`. Splits do not generate transactions.
class InvestmentSplitModel {
  final String id;
  final String holdingId;
  final double ratioNum;
  final double ratioDen;
  final String occurredAt; // YYYY-MM-DD
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const InvestmentSplitModel({
    required this.id,
    required this.holdingId,
    required this.ratioNum,
    required this.ratioDen,
    required this.occurredAt,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  bool get isForward => ratioNum > ratioDen;
  bool get isReverse => ratioNum < ratioDen;

  factory InvestmentSplitModel.fromProto(InvestmentSplit p) {
    return InvestmentSplitModel(
      id: p.id,
      holdingId: p.holdingId,
      ratioNum: p.ratioNum,
      ratioDen: p.ratioDen,
      occurredAt: _dateOnly(p.occurredAt),
      notes: p.hasNotes() ? p.notes : null,
      createdAt: p.createdAt.toDateTime().toUtc(),
      updatedAt: p.updatedAt.toDateTime().toUtc(),
      deletedAt: p.hasDeletedAt() ? p.deletedAt.toDateTime().toUtc() : null,
    );
  }

  factory InvestmentSplitModel.fromMap(Map<String, dynamic> map) {
    return InvestmentSplitModel(
      id: map['id'] as String,
      holdingId: map['holding_id'] as String,
      ratioNum: _asDouble(map['ratio_num']!),
      ratioDen: _asDouble(map['ratio_den']!),
      occurredAt: _dateOnly(map['occurred_at'] as String),
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String).toUtc()
          : null,
    );
  }

  InvestmentSplitModel normalized() {
    return InvestmentSplitModel(
      id: id,
      holdingId: holdingId,
      ratioNum: ratioNum,
      ratioDen: ratioDen,
      occurredAt: _dateOnly(occurredAt),
      notes: notes,
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
      deletedAt: deletedAt?.toUtc(),
    );
  }

  InvestmentSplitModel copyWith({
    String? holdingId,
    double? ratioNum,
    double? ratioDen,
    String? occurredAt,
    String? notes,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return InvestmentSplitModel(
      id: id,
      holdingId: holdingId ?? this.holdingId,
      ratioNum: ratioNum ?? this.ratioNum,
      ratioDen: ratioDen ?? this.ratioDen,
      occurredAt: occurredAt ?? this.occurredAt,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  Map<String, dynamic> toMap() {
    final n = normalized();
    return {
      'id': n.id,
      'holding_id': n.holdingId,
      'ratio_num': n.ratioNum,
      'ratio_den': n.ratioDen,
      'occurred_at': n.occurredAt,
      'notes': n.notes,
      'created_at': n.createdAt.toIso8601String(),
      'updated_at': n.updatedAt.toIso8601String(),
      'deleted_at': n.deletedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toServerMap() => toMap();

  InvestmentSplit toProto() {
    final n = normalized();
    final proto = InvestmentSplit(
      id: n.id,
      holdingId: n.holdingId,
      ratioNum: n.ratioNum,
      ratioDen: n.ratioDen,
      occurredAt: n.occurredAt,
    );
    if (n.notes != null) proto.notes = n.notes!;
    return proto;
  }

  static String _dateOnly(String v) => v.length >= 10 ? v.substring(0, 10) : v;
  static double _asDouble(Object v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.parse(v.toString());
  }
}
