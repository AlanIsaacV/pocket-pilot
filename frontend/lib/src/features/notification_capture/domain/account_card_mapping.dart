// ============================================================
// AccountCardMappingModel — (banco, últimos 4 dígitos o patrón) → cuenta
// ============================================================
//
// Sincronizable. Se popula automáticamente al aprobar PendingTransactions:
// el usuario nunca crea estas filas manualmente. Si reaprueba con cuenta
// distinta, se inserta una fila nueva (la más reciente por updated_at gana
// en la resolución, ver `findActiveLatest`).

import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:pocket_pilot/src/generated/pocket_pilot/v1/account_card_mapping_service.pb.dart';

class AccountCardMappingModel {
  final String id;
  final String bankId;
  // Nullable: notificaciones sin dígitos de tarjeta (ej. BBVA "COMPRA TDC")
  // resuelven solo por (bank_id, pattern_id). El backend garantiza (CHECK)
  // que al menos uno de los dos esté presente.
  final String? lastDigits;
  final String? patternId;
  final String accountId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isActive => deletedAt == null;

  const AccountCardMappingModel({
    required this.id,
    required this.bankId,
    required this.accountId,
    required this.createdAt,
    required this.updatedAt,
    this.lastDigits,
    this.patternId,
    this.deletedAt,
  });

  factory AccountCardMappingModel.fromProto(AccountCardMapping proto) {
    return AccountCardMappingModel(
      id: proto.id,
      bankId: proto.bankId,
      lastDigits: proto.lastDigits.isEmpty ? null : proto.lastDigits,
      patternId: proto.hasPatternId() ? proto.patternId : null,
      accountId: proto.accountId,
      createdAt: proto.createdAt.toDateTime().toUtc(),
      updatedAt: proto.updatedAt.toDateTime().toUtc(),
      deletedAt: proto.hasDeletedAt()
          ? proto.deletedAt.toDateTime().toUtc()
          : null,
    );
  }

  factory AccountCardMappingModel.fromMap(Map<String, dynamic> map) {
    return AccountCardMappingModel(
      id: map['id'] as String,
      bankId: map['bank_id'] as String,
      lastDigits: map['last_digits'] as String?,
      patternId: map['pattern_id'] as String?,
      accountId: map['account_id'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String).toUtc()
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'bank_id': bankId,
    'last_digits': lastDigits,
    'pattern_id': patternId,
    'account_id': accountId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };

  AccountCardMapping toProto() {
    final proto =
        AccountCardMapping(id: id, bankId: bankId, accountId: accountId)
          ..createdAt = Timestamp.fromDateTime(createdAt)
          ..updatedAt = Timestamp.fromDateTime(updatedAt);
    if (lastDigits != null) proto.lastDigits = lastDigits!;
    if (patternId != null) proto.patternId = patternId!;
    if (deletedAt != null) {
      proto.deletedAt = Timestamp.fromDateTime(deletedAt!);
    }
    return proto;
  }

  Map<String, dynamic> toServerMap() => toMap();
}
