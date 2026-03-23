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
  final String userId;
  final String accountId;
  final String categoryId;

  /// Monto en unidades menores (centavos).
  final int amount;

  final String currencyCode;
  final String description;

  /// Fecha de la transacción como string ISO 8601 (YYYY-MM-DD).
  /// Ej: "2026-03-14"
  /// El proto lo define como String porque es una fecha de calendario,
  /// no un instante con zona horaria.
  final String date;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Tipo derivado de la categoría: 'income' o 'expense'.
  /// Se debe pasar al construir el modelo desde el repositorio
  /// (el repositorio une transaction + category).
  final String categoryType;

  const TransactionModel({
    required this.id,
    required this.userId,
    required this.accountId,
    required this.categoryId,
    required this.amount,
    required this.currencyCode,
    required this.description,
    required this.date,
    required this.createdAt,
    required this.updatedAt,
    required this.categoryType,
  });

  // ----------------------------------------------------------
  // Factory: desde proto gRPC
  // ----------------------------------------------------------
  /// [categoryType] debe ser pasado desde afuera porque el proto
  /// de Transaction no incluye el tipo de su categoría.
  factory TransactionModel.fromProto(
    Transaction proto, {
    required String categoryType,
  }) {
    return TransactionModel(
      id: proto.id,
      userId: proto.userId,
      accountId: proto.accountId,
      categoryId: proto.categoryId,
      amount: proto.amountCents.toInt(),
      currencyCode: proto.currencyCode,
      description: proto.description,
      date: proto.date.toDateTime().toIso8601String().substring(0, 10),
      createdAt: proto.createdAt.toDateTime(),
      updatedAt: proto.updatedAt.toDateTime(),
      categoryType: categoryType,
    );
  }

  // ----------------------------------------------------------
  // Factory: desde fila SQLite (Map<String, dynamic>)
  // ----------------------------------------------------------
  factory TransactionModel.fromMap(
    Map<String, dynamic> map, {
    required String categoryType,
  }) {
    return TransactionModel(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      accountId: map['account_id'] as String,
      categoryId: map['category_id'] as String,
      amount: map['amount'] as int,
      currencyCode: map['currency_code'] as String,
      description: map['description'] as String,
      date: map['date'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      categoryType: categoryType,
    );
  }

  // ----------------------------------------------------------
  // Serialización: hacia SQLite
  // ----------------------------------------------------------
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'account_id': accountId,
      'category_id': categoryId,
      'amount': amount,
      'currency_code': currencyCode,
      'description': description,
      'date': date,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // ----------------------------------------------------------
  // Helpers para la UI
  // ----------------------------------------------------------

  /// true si esta transacción es un gasto.
  bool get isExpense => categoryType == 'expense';

  /// true si esta transacción es un ingreso.
  bool get isIncome => categoryType == 'income';

  /// Monto formateado con signo para mostrar en listas.
  /// Ejemplos: "+$1,050.00 MXN" / "-$250.00 MXN"
  String get formattedAmount {
    final sign = isIncome ? '+' : '-';
    final value = amount / 100.0;
    return '$sign\$${value.toStringAsFixed(2)} $currencyCode';
  }

  /// Parsea [date] (YYYY-MM-DD) a un objeto DateTime para formatear en la UI.
  DateTime get parsedDate => DateTime.parse(date);
}
