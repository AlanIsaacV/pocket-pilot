// ============================================================
// Modelo de dominio: Transacción
// ============================================================

// pbgrpc re-exporta transaction_service.pb.dart (Transaction).
import 'dart:convert';

import 'package:pocket_pilot/src/generated/pocket_pilot/v1/common.pb.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/transaction_service.pbgrpc.dart';

class TransactionModel {
  final String id;
  final String accountId;
  final String? categoryId;
  final String? linkedTransactionId;
  final String? templateId;
  final String? yieldId;

  /// Monto en unidades menores (centavos).
  final int amount;
  final int installmentsCount;

  final String currencyCode;
  final String description;

  /// Naturaleza financiera del movimiento.
  final String nature;

  /// Fecha de la transacción como string ISO 8601 (YYYY-MM-DD).
  final String date;
  final String type;
  final String status;
  final List<String> tags;

  final DateTime createdAt;
  final DateTime updatedAt;

  TransactionModel({
    required this.id,
    required this.accountId,
    this.categoryId,
    this.linkedTransactionId,
    this.templateId,
    this.yieldId,
    required this.amount,
    required int installmentsCount,
    required this.currencyCode,
    required this.description,
    this.nature = '',
    required this.date,
    required this.type,
    required this.status,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
  }) : installmentsCount = _ensureInstallmentsCount(installmentsCount);

  // ----------------------------------------------------------
  // Factory: desde proto gRPC
  // ----------------------------------------------------------
  factory TransactionModel.fromProto(Transaction proto) {
    return TransactionModel(
      id: proto.id,
      accountId: proto.accountId,
      categoryId: proto.hasCategoryId() ? proto.categoryId : null,
      linkedTransactionId: proto.hasLinkedTransactionId()
          ? proto.linkedTransactionId
          : null,
      templateId: proto.hasTemplateId() ? proto.templateId : null,
      yieldId: proto.hasYieldId() ? proto.yieldId : null,
      amount: proto.amountCents.toInt(),
      installmentsCount: proto.installmentsCount,
      currencyCode: proto.currencyCode,
      description: proto.description,
      nature: _financialNatureToString(proto.nature),
      date: proto.date.toDateTime().toIso8601String().substring(0, 10),
      type: _transactionTypeToString(proto.type),
      status: proto.status,
      tags: List<String>.from(proto.tags),
      createdAt: proto.createdAt.toDateTime(),
      updatedAt: proto.updatedAt.toDateTime(),
    );
  }

  // ----------------------------------------------------------
  // Factory: desde fila SQLite (Map<String, dynamic>)
  // ----------------------------------------------------------
  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'] as String,
      accountId: map['account_id'] as String,
      categoryId: map['category_id'] as String?,
      linkedTransactionId: map['linked_transaction_id'] as String?,
      templateId: map['template_id'] as String?,
      yieldId: map['yield_id'] as String?,
      amount: map['amount_cents'] as int,
      installmentsCount: map['installments_count'] as int,
      currencyCode: map['currency_code'] as String,
      description: map['description'] as String,
      nature: map['nature'] as String? ?? '',
      date: map['date'] as String,
      type: map['type'] as String,
      status: map['status'] as String,
      tags: _decodeTags(map['tags']),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  // ----------------------------------------------------------
  // Serialización: hacia SQLite
  // ----------------------------------------------------------
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'account_id': accountId,
      'category_id': categoryId,
      'linked_transaction_id': linkedTransactionId,
      'template_id': templateId,
      'yield_id': yieldId,
      'amount_cents': amount,
      'installments_count': installmentsCount,
      'currency_code': currencyCode,
      'tags': jsonEncode(tags),
      'description': description,
      'nature': nature,
      'date': date,
      'type': type,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Payload para el outbox. Incluye type y status que el servidor necesita.
  /// No incluye user_id: el servidor lo lee del token.
  Map<String, dynamic> toServerMap() {
    return {
      'id': id,
      'account_id': accountId,
      'category_id': categoryId,
      'linked_transaction_id': linkedTransactionId,
      'template_id': templateId,
      'yield_id': yieldId,
      'amount_cents': amount,
      'installments_count': installmentsCount,
      'currency_code': currencyCode,
      'tags': tags,
      'description': description,
      'nature': nature,
      'date': date,
      'type': type,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static int _ensureInstallmentsCount(int value) {
    if (value < 1) {
      throw ArgumentError.value(
        value,
        'installmentsCount',
        'installmentsCount must be >= 1',
      );
    }
    return value;
  }

  // ----------------------------------------------------------
  // Helpers para la UI
  // ----------------------------------------------------------

  bool get isExpense => type == 'expense';
  bool get isIncome => type == 'income';
  bool get isTransferOut => type == 'transfer_out';
  bool get isTransferIn => type == 'transfer_in';
  bool get isTransfer => isTransferOut || isTransferIn;

  /// Monto formateado con signo para mostrar en listas.
  String get formattedAmount {
    final sign = (isIncome || isTransferIn) ? '+' : '-';
    final value = amount / 100.0;
    return '$sign\$${value.toStringAsFixed(2)} $currencyCode';
  }

  /// Parsea [date] (YYYY-MM-DD) a un objeto DateTime para formatear en la UI.
  DateTime get parsedDate => DateTime.parse(date);

  static List<String> _decodeTags(Object? raw) {
    if (raw == null) return const <String>[];

    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList(growable: false);
        }
      } catch (_) {
        return const <String>[];
      }
    }

    if (raw is List) {
      return raw.map((e) => e.toString()).toList(growable: false);
    }

    return const <String>[];
  }

  static String _financialNatureToString(FinancialNature nature) {
    switch (nature) {
      case FinancialNature.NATURE_REQUIRED:
        return 'required';
      case FinancialNature.NATURE_OBLIGATION:
        return 'obligation';
      case FinancialNature.NATURE_LIFESTYLE:
        return 'lifestyle';
      case FinancialNature.NATURE_ACTIVE:
        return 'active';
      case FinancialNature.NATURE_PASSIVE:
        return 'passive';
      case FinancialNature.NATURE_WINDFALL:
        return 'windfall';
      default:
        return '';
    }
  }

  static FinancialNature stringToFinancialNature(String s) {
    switch (s) {
      case 'required':
        return FinancialNature.NATURE_REQUIRED;
      case 'obligation':
        return FinancialNature.NATURE_OBLIGATION;
      case 'lifestyle':
        return FinancialNature.NATURE_LIFESTYLE;
      case 'active':
        return FinancialNature.NATURE_ACTIVE;
      case 'passive':
        return FinancialNature.NATURE_PASSIVE;
      case 'windfall':
        return FinancialNature.NATURE_WINDFALL;
      default:
        return FinancialNature.NATURE_UNSPECIFIED;
    }
  }

  static String _transactionTypeToString(TransactionType type) {
    switch (type) {
      case TransactionType.TRANSACTION_TYPE_INCOME:
        return 'income';
      case TransactionType.TRANSACTION_TYPE_EXPENSE:
        return 'expense';
      case TransactionType.TRANSACTION_TYPE_TRANSFER_OUT:
        return 'transfer_out';
      case TransactionType.TRANSACTION_TYPE_TRANSFER_IN:
        return 'transfer_in';
      default:
        return 'unspecified';
    }
  }

  static TransactionType stringToTransactionType(String type) {
    switch (type) {
      case 'income':
        return TransactionType.TRANSACTION_TYPE_INCOME;
      case 'expense':
        return TransactionType.TRANSACTION_TYPE_EXPENSE;
      case 'transfer_out':
        return TransactionType.TRANSACTION_TYPE_TRANSFER_OUT;
      case 'transfer_in':
        return TransactionType.TRANSACTION_TYPE_TRANSFER_IN;
      default:
        return TransactionType.TRANSACTION_TYPE_UNSPECIFIED;
    }
  }
}
