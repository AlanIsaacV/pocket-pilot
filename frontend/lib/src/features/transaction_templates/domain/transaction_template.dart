import 'dart:convert';

import 'package:pocket_pilot/src/generated/pocket_pilot/v1/transaction_template_service.pbgrpc.dart';

class TransactionTemplateModel {
  final String id;
  final String name;
  final String accountId;
  final String? toAccountId;
  final String? categoryId;
  final String type;
  final int? amountCents;
  final String currencyCode;
  final List<String> tags;
  final String description;
  final String? frequency;
  final String? nextDate;
  final String? endDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const TransactionTemplateModel({
    required this.id,
    required this.name,
    required this.accountId,
    this.toAccountId,
    this.categoryId,
    required this.type,
    this.amountCents,
    required this.currencyCode,
    required this.tags,
    required this.description,
    this.frequency,
    this.nextDate,
    this.endDate,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory TransactionTemplateModel.fromProto(TransactionTemplate proto) {
    return TransactionTemplateModel(
      id: proto.id,
      name: proto.name,
      accountId: proto.accountId,
      toAccountId: proto.hasToAccountId() ? proto.toAccountId : null,
      categoryId: proto.hasCategoryId() ? proto.categoryId : null,
      type: proto.type,
      amountCents: proto.hasAmountCents() ? proto.amountCents.toInt() : null,
      currencyCode: proto.currencyCode,
      tags: List<String>.unmodifiable(proto.tags),
      description: proto.description,
      frequency: proto.hasFrequency() ? proto.frequency : null,
      nextDate: proto.hasNextDate() ? _dateOnly(proto.nextDate) : null,
      endDate: proto.hasEndDate() ? _dateOnly(proto.endDate) : null,
      createdAt: proto.createdAt.toDateTime().toUtc(),
      updatedAt: proto.updatedAt.toDateTime().toUtc(),
      deletedAt: proto.hasDeletedAt()
          ? proto.deletedAt.toDateTime().toUtc()
          : null,
    );
  }

  factory TransactionTemplateModel.fromMap(Map<String, dynamic> map) {
    return TransactionTemplateModel(
      id: map['id'] as String,
      name: map['name'] as String,
      accountId: map['account_id'] as String,
      toAccountId: map['to_account_id'] as String?,
      categoryId: map['category_id'] as String?,
      type: map['type'] as String,
      amountCents: map['amount_cents'] as int?,
      currencyCode: map['currency_code'] as String,
      tags: _decodeTags(map['tags']),
      description: map['description'] as String? ?? '',
      frequency: map['frequency'] as String?,
      nextDate: map['next_date'] != null
          ? _dateOnly(map['next_date'] as String)
          : null,
      endDate: map['end_date'] != null
          ? _dateOnly(map['end_date'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String).toUtc()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'account_id': accountId,
      'to_account_id': toAccountId,
      'category_id': categoryId,
      'type': type,
      'amount_cents': amountCents,
      'currency_code': currencyCode,
      'tags': jsonEncode(tags),
      'description': description,
      'frequency': frequency,
      'next_date': nextDate == null ? null : _dateOnly(nextDate!),
      'end_date': endDate == null ? null : _dateOnly(endDate!),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toServerMap() {
    return {
      'id': id,
      'name': name,
      'account_id': accountId,
      'to_account_id': toAccountId,
      'category_id': categoryId,
      'type': type,
      'amount_cents': amountCents,
      'currency_code': currencyCode,
      'tags': tags,
      'description': description,
      'frequency': frequency,
      'next_date': nextDate == null ? null : _dateOnly(nextDate!),
      'end_date': endDate == null ? null : _dateOnly(endDate!),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  static List<String> _decodeTags(Object? raw) {
    if (raw == null) return const <String>[];

    if (raw is String && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList(growable: false);
      }
    }

    if (raw is List) {
      return raw.map((e) => e.toString()).toList(growable: false);
    }

    return const <String>[];
  }

  static String _dateOnly(String value) {
    return value.length >= 10 ? value.substring(0, 10) : value;
  }
}
