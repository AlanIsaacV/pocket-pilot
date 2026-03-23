// ============================================================
// Modelo de dominio: Cuenta
// ============================================================
//
// Los modelos de dominio son objetos Dart puros (PODOs) que
// no dependen de Flutter ni de librerías externas.
//
// Dos constructores factory:
//   fromProto() → convierte la respuesta gRPC al modelo
//   fromMap()   → convierte una fila SQLite al modelo
//
// Dos serializadores:
//   toMap()       → para SQLite local (sin user_id, no existe esa columna)
//   toServerMap() → para el outbox payload (incluye user_id para el server)

import 'package:fixnum/fixnum.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/account_service.pbgrpc.dart';

class AccountModel {
  final String id;

  /// ID del usuario al que pertenece esta cuenta.
  /// No se almacena localmente (la DB local es single-user).
  /// Solo se usa al construir protos para enviar al servidor.
  final String userId;

  final String name;

  /// Tipo de cuenta como string: 'bank', 'cash', 'credit_card',
  /// 'loan', 'investment', 'crypto', 'other'.
  final String type;

  final int? creditLimitCents;
  final int? statementDay;
  final int? paymentDueDay;

  /// Tasa de interés APR como entero (representación interna del servidor).
  final int? interestRateApr;
  final int? termMonths;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const AccountModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    this.creditLimitCents,
    this.statementDay,
    this.paymentDueDay,
    this.interestRateApr,
    this.termMonths,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  // ----------------------------------------------------------
  // Factory: desde proto gRPC
  // ----------------------------------------------------------
  factory AccountModel.fromProto(Account proto) {
    return AccountModel(
      id: proto.id,
      userId: proto.userId,
      name: proto.name,
      type: _accountTypeToString(proto.type),
      creditLimitCents: proto.creditLimitCents != Int64.ZERO
          ? proto.creditLimitCents.toInt()
          : null,
      statementDay: proto.statementDay != 0 ? proto.statementDay : null,
      paymentDueDay: proto.paymentDueDay != 0 ? proto.paymentDueDay : null,
      interestRateApr:
          proto.interestRateApr != 0 ? proto.interestRateApr : null,
      termMonths: proto.termMonths != 0 ? proto.termMonths : null,
      createdAt: proto.createdAt.toDateTime().toUtc(),
      updatedAt: proto.updatedAt.toDateTime().toUtc(),
      deletedAt: proto.hasDeletedAt() ? proto.deletedAt.toDateTime().toUtc() : null,
    );
  }

  // ----------------------------------------------------------
  // Factory: desde fila SQLite
  // ----------------------------------------------------------
  factory AccountModel.fromMap(Map<String, dynamic> map) {
    return AccountModel(
      id: map['id'] as String,
      // user_id no se almacena en SQLite local; se usa '' como fallback.
      userId: map['user_id'] as String? ?? '',
      name: map['name'] as String,
      type: map['type'] as String,
      creditLimitCents: map['credit_limit_cents'] as int?,
      statementDay: map['statement_day'] as int?,
      paymentDueDay: map['payment_due_day'] as int?,
      interestRateApr: map['interest_rate_apr'] as int?,
      termMonths: map['term_months'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String).toUtc()
          : null,
    );
  }

  // ----------------------------------------------------------
  // Serialización: hacia SQLite local (sin user_id)
  // ----------------------------------------------------------
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'credit_limit_cents': creditLimitCents,
      'statement_day': statementDay,
      'payment_due_day': paymentDueDay,
      'interest_rate_apr': interestRateApr,
      'term_months': termMonths,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  /// Map completo para el payload del outbox.
  /// Incluye user_id porque el servidor lo necesita al recibir el push.
  Map<String, dynamic> toServerMap() {
    return {
      ...toMap(),
      'user_id': userId,
    };
  }

  // ----------------------------------------------------------
  // Conversión entre string y enum proto (bidireccional)
  // ----------------------------------------------------------
  static String _accountTypeToString(AccountType type) {
    switch (type) {
      case AccountType.ACCOUNT_TYPE_BANK:
        return 'bank';
      case AccountType.ACCOUNT_TYPE_CASH:
        return 'cash';
      case AccountType.ACCOUNT_TYPE_CREDIT_CARD:
        return 'credit_card';
      case AccountType.ACCOUNT_TYPE_LOAN:
        return 'loan';
      case AccountType.ACCOUNT_TYPE_INVESTMENT:
        return 'investment';
      case AccountType.ACCOUNT_TYPE_CRYPYO:
        return 'crypto';
      case AccountType.ACCOUNT_TYPE_OTHER:
        return 'other';
      default:
        return 'other';
    }
  }

  static AccountType stringToAccountType(String type) {
    switch (type) {
      case 'bank':
        return AccountType.ACCOUNT_TYPE_BANK;
      case 'cash':
        return AccountType.ACCOUNT_TYPE_CASH;
      case 'credit_card':
        return AccountType.ACCOUNT_TYPE_CREDIT_CARD;
      case 'loan':
        return AccountType.ACCOUNT_TYPE_LOAN;
      case 'investment':
        return AccountType.ACCOUNT_TYPE_INVESTMENT;
      case 'crypto':
        return AccountType.ACCOUNT_TYPE_CRYPYO;
      default:
        return AccountType.ACCOUNT_TYPE_OTHER;
    }
  }
}
