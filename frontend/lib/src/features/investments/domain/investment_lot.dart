import 'package:fixnum/fixnum.dart';

import 'package:pocket_pilot/src/generated/pocket_pilot/v1/investment_lot_service.pbgrpc.dart';

/// A single buy or sell event for a holding. The InvestmentTransactionGenerator
/// derives the corresponding Transaction from this lot deterministically.
class InvestmentLotModel {
  final String id;
  final String holdingId;
  final String accountId;
  final String kind; // 'buy' | 'sell'
  final double quantity;
  final double price; // per unit, in holding currency
  final int feeCents; // in holding currency
  final double? fxRate; // holding currency → account currency
  final String occurredAt; // YYYY-MM-DD
  final String validity; // 'valid' | 'invalid'
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const InvestmentLotModel({
    required this.id,
    required this.holdingId,
    required this.accountId,
    required this.kind,
    required this.quantity,
    required this.price,
    required this.feeCents,
    this.fxRate,
    required this.occurredAt,
    required this.validity,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  bool get isBuy => kind == 'buy';
  bool get isSell => kind == 'sell';

  factory InvestmentLotModel.fromProto(InvestmentLot p) {
    return InvestmentLotModel(
      id: p.id,
      holdingId: p.holdingId,
      accountId: p.accountId,
      kind: _normalizeLower(p.kind),
      quantity: p.quantity,
      price: p.price,
      feeCents: p.feeCents.toInt(),
      fxRate: p.hasFxRate() ? p.fxRate : null,
      occurredAt: _dateOnly(p.occurredAt),
      validity: _normalizeLower(p.validity.isEmpty ? 'valid' : p.validity),
      notes: p.hasNotes() ? p.notes : null,
      createdAt: p.createdAt.toDateTime().toUtc(),
      updatedAt: p.updatedAt.toDateTime().toUtc(),
      deletedAt: p.hasDeletedAt() ? p.deletedAt.toDateTime().toUtc() : null,
    );
  }

  factory InvestmentLotModel.fromMap(Map<String, dynamic> map) {
    return InvestmentLotModel(
      id: map['id'] as String,
      holdingId: map['holding_id'] as String,
      accountId: (map['account_id'] as String?) ?? '',
      kind: _normalizeLower(map['kind'] as String),
      quantity: _asDouble(map['quantity']!),
      price: _asDouble(map['price']!),
      feeCents: _asInt(map['fee_cents']),
      fxRate: map['fx_rate'] == null ? null : _asDouble(map['fx_rate']!),
      occurredAt: _dateOnly(map['occurred_at'] as String),
      validity: _normalizeLower(
        ((map['validity'] as String?) ?? 'valid'),
      ),
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String).toUtc()
          : null,
    );
  }

  InvestmentLotModel normalized() {
    return InvestmentLotModel(
      id: id,
      holdingId: holdingId,
      accountId: accountId,
      kind: _normalizeLower(kind),
      quantity: quantity,
      price: price,
      feeCents: feeCents,
      fxRate: fxRate,
      occurredAt: _dateOnly(occurredAt),
      validity: _normalizeLower(validity),
      notes: notes,
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
      deletedAt: deletedAt?.toUtc(),
    );
  }

  InvestmentLotModel copyWith({
    String? holdingId,
    String? accountId,
    String? kind,
    double? quantity,
    double? price,
    int? feeCents,
    double? fxRate,
    String? occurredAt,
    String? validity,
    String? notes,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return InvestmentLotModel(
      id: id,
      holdingId: holdingId ?? this.holdingId,
      accountId: accountId ?? this.accountId,
      kind: kind ?? this.kind,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      feeCents: feeCents ?? this.feeCents,
      fxRate: fxRate ?? this.fxRate,
      occurredAt: occurredAt ?? this.occurredAt,
      validity: validity ?? this.validity,
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
      'account_id': n.accountId,
      'kind': n.kind,
      'quantity': n.quantity,
      'price': n.price,
      'fee_cents': n.feeCents,
      'fx_rate': n.fxRate,
      'occurred_at': n.occurredAt,
      'validity': n.validity,
      'notes': n.notes,
      'created_at': n.createdAt.toIso8601String(),
      'updated_at': n.updatedAt.toIso8601String(),
      'deleted_at': n.deletedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toServerMap() => toMap();

  InvestmentLot toProto() {
    final n = normalized();
    final proto = InvestmentLot(
      id: n.id,
      holdingId: n.holdingId,
      accountId: n.accountId,
      kind: n.kind,
      quantity: n.quantity,
      price: n.price,
      feeCents: Int64(n.feeCents),
      occurredAt: n.occurredAt,
      validity: n.validity,
    );
    if (n.fxRate != null) proto.fxRate = n.fxRate!;
    if (n.notes != null) proto.notes = n.notes!;
    return proto;
  }

  static String _normalizeLower(String v) => v.trim().toLowerCase();
  static String _dateOnly(String v) => v.length >= 10 ? v.substring(0, 10) : v;
  static double _asDouble(Object v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.parse(v.toString());
  }

  static int _asInt(Object? v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.parse(v.toString());
  }
}
