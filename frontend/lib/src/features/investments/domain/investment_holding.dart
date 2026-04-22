import 'package:pocket_pilot/src/generated/pocket_pilot/v1/investment_holding_service.pbgrpc.dart';

/// Domain model for an investment position. Mirrors the investment_holdings
/// table in SQLite and the InvestmentHolding proto message. Holdings are
/// globals — they describe the asset (symbol+exchange+currency) and are not
/// tied to any account. Each lot settles against its own account_id.
class InvestmentHoldingModel {
  final String id;
  final String symbol;
  final String exchange;
  final String displayName;
  final String currencyCode;
  final String assetType;
  final String status;
  final double? manualPrice;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const InvestmentHoldingModel({
    required this.id,
    required this.symbol,
    required this.exchange,
    required this.displayName,
    required this.currencyCode,
    required this.assetType,
    required this.status,
    this.manualPrice,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  bool get isArchived => deletedAt != null;

  factory InvestmentHoldingModel.fromProto(InvestmentHolding p) {
    return InvestmentHoldingModel(
      id: p.id,
      symbol: _normalizeUpper(p.symbol),
      exchange: _normalizeUpper(p.exchange),
      displayName: p.displayName,
      currencyCode: p.currencyCode.toUpperCase(),
      assetType: _normalizeLower(p.assetType),
      status: _normalizeLower(p.status),
      manualPrice: p.hasManualPrice() ? p.manualPrice : null,
      notes: p.hasNotes() ? p.notes : null,
      createdAt: p.createdAt.toDateTime().toUtc(),
      updatedAt: p.updatedAt.toDateTime().toUtc(),
      deletedAt: p.hasDeletedAt() ? p.deletedAt.toDateTime().toUtc() : null,
    );
  }

  factory InvestmentHoldingModel.fromMap(Map<String, dynamic> map) {
    return InvestmentHoldingModel(
      id: map['id'] as String,
      symbol: _normalizeUpper(map['symbol'] as String),
      exchange: _normalizeUpper(map['exchange'] as String),
      displayName: (map['display_name'] as String?) ?? '',
      currencyCode: (map['currency_code'] as String).toUpperCase(),
      assetType: _normalizeLower(map['asset_type'] as String),
      status: _normalizeLower((map['status'] as String?) ?? 'active'),
      manualPrice: map['manual_price'] == null
          ? null
          : _asDouble(map['manual_price']!),
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String).toUtc()
          : null,
    );
  }

  InvestmentHoldingModel normalized() {
    return InvestmentHoldingModel(
      id: id,
      symbol: _normalizeUpper(symbol),
      exchange: _normalizeUpper(exchange),
      displayName: displayName,
      currencyCode: currencyCode.toUpperCase(),
      assetType: _normalizeLower(assetType),
      status: _normalizeLower(status),
      manualPrice: manualPrice,
      notes: notes,
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
      deletedAt: deletedAt?.toUtc(),
    );
  }

  InvestmentHoldingModel copyWith({
    String? displayName,
    String? currencyCode,
    String? status,
    double? manualPrice,
    String? notes,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return InvestmentHoldingModel(
      id: id,
      symbol: symbol,
      exchange: exchange,
      displayName: displayName ?? this.displayName,
      currencyCode: currencyCode ?? this.currencyCode,
      assetType: assetType,
      status: status ?? this.status,
      manualPrice: manualPrice ?? this.manualPrice,
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
      'symbol': n.symbol,
      'exchange': n.exchange,
      'display_name': n.displayName,
      'currency_code': n.currencyCode,
      'asset_type': n.assetType,
      'status': n.status,
      'manual_price': n.manualPrice,
      'notes': n.notes,
      'created_at': n.createdAt.toIso8601String(),
      'updated_at': n.updatedAt.toIso8601String(),
      'deleted_at': n.deletedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toServerMap() => toMap();

  InvestmentHolding toProto() {
    final n = normalized();
    final proto = InvestmentHolding(
      id: n.id,
      symbol: n.symbol,
      exchange: n.exchange,
      displayName: n.displayName,
      currencyCode: n.currencyCode,
      assetType: n.assetType,
      status: n.status,
    );
    if (n.manualPrice != null) proto.manualPrice = n.manualPrice!;
    if (n.notes != null) proto.notes = n.notes!;
    return proto;
  }

  static String _normalizeLower(String v) => v.trim().toLowerCase();
  static String _normalizeUpper(String v) => v.trim().toUpperCase();
  static double _asDouble(Object v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.parse(v.toString());
  }
}
