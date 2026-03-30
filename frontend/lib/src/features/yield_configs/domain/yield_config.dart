import 'package:fixnum/fixnum.dart';

import 'package:pocket_pilot/src/generated/pocket_pilot/v1/yield_config_service.pbgrpc.dart';

class YieldConfigModel {
  final String id;
  final String accountId;
  final String name;
  final int amountCents;
  final double apyRate;
  final String payoutFrequency;
  final String nextDate;
  final String? maturityDate;
  final int? termDays;
  final bool autoRenew;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const YieldConfigModel({
    required this.id,
    required this.accountId,
    required this.name,
    required this.amountCents,
    required this.apyRate,
    required this.payoutFrequency,
    required this.nextDate,
    this.maturityDate,
    this.termDays,
    required this.autoRenew,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory YieldConfigModel.fromProto(YieldConfig proto) {
    return YieldConfigModel(
      id: proto.id,
      accountId: proto.accountId,
      name: proto.name,
      amountCents: proto.amountCents.toInt(),
      apyRate: proto.apyRate,
      payoutFrequency: _normalizeLower(proto.payoutFrequency),
      nextDate: _dateOnly(proto.nextDate),
      maturityDate: proto.hasMaturityDate()
          ? _dateOnly(proto.maturityDate)
          : null,
      termDays: proto.hasTermDays() ? proto.termDays : null,
      autoRenew: proto.autoRenew,
      status: _normalizeLower(proto.status),
      createdAt: proto.createdAt.toDateTime().toUtc(),
      updatedAt: proto.updatedAt.toDateTime().toUtc(),
      deletedAt: proto.hasDeletedAt()
          ? proto.deletedAt.toDateTime().toUtc()
          : null,
    );
  }

  factory YieldConfigModel.fromMap(Map<String, dynamic> map) {
    return YieldConfigModel(
      id: map['id'] as String,
      accountId: map['account_id'] as String,
      name: map['name'] as String,
      amountCents: _asInt(map['amount_cents']),
      apyRate: _asDouble(map['apy_rate']),
      payoutFrequency: _normalizeLower(
        map['payout_frequency'] as String? ?? '',
      ),
      nextDate: _dateOnly(map['next_date'] as String),
      maturityDate: map['maturity_date'] != null
          ? _dateOnly(map['maturity_date'] as String)
          : null,
      termDays: map['term_days'] == null ? null : _asInt(map['term_days']),
      autoRenew: _asBool(map['auto_renew']),
      status: _normalizeLower(map['status'] as String? ?? ''),
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String).toUtc()
          : null,
    );
  }

  YieldConfigModel copyWith({
    String? nextDate,
    String? maturityDate,
    int? termDays,
    bool? autoRenew,
    String? status,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return YieldConfigModel(
      id: id,
      accountId: accountId,
      name: name,
      amountCents: amountCents,
      apyRate: apyRate,
      payoutFrequency: payoutFrequency,
      nextDate: nextDate ?? this.nextDate,
      maturityDate: maturityDate ?? this.maturityDate,
      termDays: termDays ?? this.termDays,
      autoRenew: autoRenew ?? this.autoRenew,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  YieldConfigModel normalized() {
    return YieldConfigModel(
      id: id,
      accountId: accountId,
      name: name,
      amountCents: amountCents,
      apyRate: apyRate,
      payoutFrequency: _normalizeLower(payoutFrequency),
      nextDate: _dateOnly(nextDate),
      maturityDate: maturityDate == null ? null : _dateOnly(maturityDate!),
      termDays: termDays,
      autoRenew: autoRenew,
      status: _normalizeLower(status),
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
      deletedAt: deletedAt?.toUtc(),
    );
  }

  Map<String, dynamic> toMap() {
    final n = normalized();
    return {
      'id': n.id,
      'account_id': n.accountId,
      'name': n.name,
      'amount_cents': n.amountCents,
      'apy_rate': n.apyRate,
      'payout_frequency': n.payoutFrequency,
      'next_date': n.nextDate,
      'maturity_date': n.maturityDate,
      'term_days': n.termDays,
      'auto_renew': n.autoRenew ? 1 : 0,
      'status': n.status,
      'created_at': n.createdAt.toIso8601String(),
      'updated_at': n.updatedAt.toIso8601String(),
      'deleted_at': n.deletedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toServerMap() {
    final n = normalized();
    return {
      'id': n.id,
      'account_id': n.accountId,
      'name': n.name,
      'amount_cents': n.amountCents,
      'apy_rate': n.apyRate,
      'payout_frequency': n.payoutFrequency,
      'next_date': n.nextDate,
      'maturity_date': n.maturityDate,
      'term_days': n.termDays,
      'auto_renew': n.autoRenew,
      'status': n.status,
      'created_at': n.createdAt.toIso8601String(),
      'updated_at': n.updatedAt.toIso8601String(),
      'deleted_at': n.deletedAt?.toIso8601String(),
    };
  }

  YieldConfig toProto() {
    final n = normalized();
    return YieldConfig(
      id: n.id,
      accountId: n.accountId,
      name: n.name,
      amountCents: Int64(n.amountCents),
      apyRate: n.apyRate,
      payoutFrequency: n.payoutFrequency,
      nextDate: n.nextDate,
      maturityDate: n.maturityDate,
      termDays: n.termDays,
      autoRenew: n.autoRenew,
      status: n.status,
    );
  }

  static String _normalizeLower(String value) {
    return value.trim().toLowerCase();
  }

  static String _dateOnly(String value) {
    return value.length >= 10 ? value.substring(0, 10) : value;
  }

  static bool _asBool(Object? raw) {
    if (raw == null) return false;
    if (raw is bool) return raw;
    if (raw is int) return raw != 0;
    if (raw is String) {
      final v = raw.toLowerCase();
      return v == '1' || v == 'true';
    }
    return false;
  }

  static int _asInt(Object raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.parse(raw.toString());
  }

  static double _asDouble(Object raw) {
    if (raw is double) return raw;
    if (raw is num) return raw.toDouble();
    return double.parse(raw.toString());
  }
}
