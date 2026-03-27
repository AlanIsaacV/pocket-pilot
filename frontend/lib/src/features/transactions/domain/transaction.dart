// ============================================================
// Modelo de dominio: Transacción
// ============================================================

// pbgrpc re-exporta transaction_service.pb.dart (Transaction).
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/transaction_service.pbgrpc.dart';

class TransactionModel {
  final String id;
  final String accountId;
  final String? categoryId;
  final String? linkedTransactionId;

  /// Monto en unidades menores (centavos).
  final int amount;

  final String currencyCode;
  final String description;

  /// Fecha de la transacción como string ISO 8601 (YYYY-MM-DD).
  final String date;
  final String type;
  final String status;

  final DateTime createdAt;
  final DateTime updatedAt;

  const TransactionModel({
    required this.id,
    required this.accountId,
    this.categoryId,
    this.linkedTransactionId,
    required this.amount,
    required this.currencyCode,
    required this.description,
    required this.date,
    required this.type,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  // ----------------------------------------------------------
  // Factory: desde proto gRPC
  // ----------------------------------------------------------
  factory TransactionModel.fromProto(Transaction proto) {
    return TransactionModel(
      id: proto.id,
      accountId: proto.accountId,
      categoryId: proto.hasCategoryId() ? proto.categoryId : null,
      linkedTransactionId:
          proto.hasLinkedTransactionId() ? proto.linkedTransactionId : null,
      amount: proto.amountCents.toInt(),
      currencyCode: proto.currencyCode,
      description: proto.description,
      date: proto.date.toDateTime().toIso8601String().substring(0, 10),
      type: _transactionTypeToString(proto.type),
      status: proto.status,
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
      amount: map['amount_cents'] as int,
      currencyCode: map['currency_code'] as String,
      description: map['description'] as String,
      date: map['date'] as String,
      type: map['type'] as String,
      status: map['status'] as String,
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
      'amount_cents': amount,
      'currency_code': currencyCode,
      'description': description,
      'date': date,
      'type': type,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Payload para el outbox. Incluye type y status que el servidor necesita.
  /// No incluye user_id: el servidor lo lee del token.
  Map<String, dynamic> toServerMap() => toMap();

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
