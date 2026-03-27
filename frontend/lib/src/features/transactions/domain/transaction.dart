// ============================================================
// Modelo de dominio: Transacción
// ============================================================
//
// Una transacción no lleva su propio "tipo" (ingreso/gasto) —
// ese dato viene de la categoría asociada. Para poder mostrar
// el color correcto en la UI sin cargar la categoría completa,
// guardamos el tipo de categoría como campo derivado al momento
// de construir el modelo desde el repositorio.

// pbgrpc re-exporta transaction_service.pb.dart (Transaction).
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/transaction_service.pbgrpc.dart';

class TransactionModel {
  final String id;
  final String accountId;
  final String categoryId;

  /// Monto en unidades menores (centavos).
  final int amount;

  final String currencyCode;
  final String description;

  /// Fecha de la transacción como string ISO 8601 (YYYY-MM-DD).
  /// Ej: "2026-03-14"
  final String date;
  final String type;
  final String status;

  final DateTime createdAt;
  final DateTime updatedAt;

  const TransactionModel({
    required this.id,
    required this.accountId,
    required this.categoryId,
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
  /// [type] debe ser pasado desde afuera porque el proto
  /// de Transaction no incluye el tipo de su categoría.
  factory TransactionModel.fromProto(Transaction proto) {
    return TransactionModel(
      id: proto.id,
      accountId: proto.accountId,
      categoryId: proto.categoryId,
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
      categoryId: map['category_id'] as String,
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
      'amount_cents': amount,
      'currency_code': currencyCode,
      'description': description,
      'date': date,
      "type": type,
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

  /// true si esta transacción es un gasto.
  bool get isExpense => type == 'expense';

  /// true si esta transacción es un ingreso.
  bool get isIncome => type == 'income';

  /// true si esta transacción es una transferencia.
  bool get isTransfer => type == 'transfer';

  /// Monto formateado con signo para mostrar en listas.
  /// Ejemplos: "+$1,050.00 MXN" / "-$250.00 MXN"
  String get formattedAmount {
    final sign = isIncome ? '+' : '-';
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
      case TransactionType.TRANSACTION_TYPE_TRANSFER:
        return 'transfer';
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
      case 'transfer':
        return TransactionType.TRANSACTION_TYPE_TRANSFER;
      default:
        return TransactionType.TRANSACTION_TYPE_UNSPECIFIED;
    }
  }
}
