// ============================================================
// Modelo de dominio: Cuenta
// ============================================================
//
// Los modelos de dominio son objetos Dart puros (PODOs) que
// no dependen de Flutter ni de librerías externas. Esto hace
// que sean fáciles de testear y de reutilizar.
//
// Tienen dos constructores factory:
//   fromProto() → convierte la respuesta gRPC al modelo
//   fromMap()   → convierte una fila SQLite (Map<String,dynamic>) al modelo
//
// También exponen toMap() para insertar/actualizar en SQLite.
// Así la UI NUNCA toca los objetos generados directamente.

// pbgrpc re-exporta account_service.pb.dart (Account) y pbenum.dart (AccountType).
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/account_service.pbgrpc.dart';

class AccountModel {
  final String id;
  final String userId;
  final String name;

  /// Tipo de cuenta como string: 'checking', 'savings', 'credit_card',
  /// 'cash', 'investment'. Normalizado desde el enum proto.
  final String type;

  /// Saldo inicial en unidades menores (centavos).
  /// Ejemplo: $1,050.00 MXN → 105000
  final int initialBalance;

  final String currencyCode;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AccountModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    required this.initialBalance,
    required this.currencyCode,
    required this.createdAt,
    required this.updatedAt,
  });

  // ----------------------------------------------------------
  // Factory: desde proto gRPC
  // ----------------------------------------------------------
  /// Convierte el mensaje protobuf [Account] (respuesta del servidor)
  /// en nuestro modelo de dominio limpio.
  factory AccountModel.fromProto(Account proto) {
    return AccountModel(
      id: proto.id,
      userId: proto.userId,
      name: proto.name,
      type: _accountTypeToString(proto.type),
      // proto.initialBalance es de tipo Money (mensaje anidado).
      // Verificamos con hasInitialBalance() antes de acceder para
      // no causar un error si el campo es opcional y no fue enviado.
      initialBalance: proto.hasInitialBalance()
          ? proto.initialBalance.amountMinor.toInt()
          : 0,
      // Int64 (del paquete fixnum) es el tipo Dart para int64 en proto.
      // .toInt() lo convierte al tipo nativo int de Dart.
      currencyCode: proto.hasInitialBalance()
          ? proto.initialBalance.currencyCode
          : 'MXN',
      // Los Timestamps de proto se convierten a DateTime con .toDateTime().
      // El método toDateTime() devuelve UTC; la UI formateará en local.
      createdAt: proto.createdAt.toDateTime(),
      updatedAt: proto.updatedAt.toDateTime(),
    );
  }

  // ----------------------------------------------------------
  // Factory: desde fila SQLite (Map<String, dynamic>)
  // ----------------------------------------------------------
  /// Convierte un Map devuelto por sqflite en nuestro modelo de dominio.
  ///
  /// Las fechas se guardan como strings ISO 8601 en SQLite y se parsean
  /// con DateTime.parse() al leer.
  factory AccountModel.fromMap(Map<String, dynamic> map) {
    return AccountModel(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      name: map['name'] as String,
      type: map['type'] as String,
      initialBalance: map['initial_balance'] as int,
      currencyCode: map['currency_code'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  // ----------------------------------------------------------
  // Serialización: hacia SQLite
  // ----------------------------------------------------------
  /// Convierte el modelo a Map para insertar o actualizar en sqflite.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'type': type,
      'initial_balance': initialBalance,
      'currency_code': currencyCode,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // ----------------------------------------------------------
  // Helpers para la UI
  // ----------------------------------------------------------

  /// Saldo formateado para mostrar en pantalla.
  /// Ejemplo: "$1,050.00 MXN"
  String get formattedBalance {
    final amount = initialBalance / 100.0;
    // toStringAsFixed(2) garantiza siempre 2 decimales: 1050.0 → "1050.00"
    return '\$${amount.toStringAsFixed(2)} $currencyCode';
  }

  // ----------------------------------------------------------
  // Conversión interna: enum proto → string
  // ----------------------------------------------------------
  static String _accountTypeToString(AccountType type) {
    switch (type) {
      case AccountType.ACCOUNT_TYPE_CHECKING:
        return 'checking';
      case AccountType.ACCOUNT_TYPE_SAVINGS:
        return 'savings';
      case AccountType.ACCOUNT_TYPE_CREDIT_CARD:
        return 'credit_card';
      case AccountType.ACCOUNT_TYPE_CASH:
        return 'cash';
      case AccountType.ACCOUNT_TYPE_INVESTMENT:
        return 'investment';
      default:
        return 'checking';
    }
  }
}
