// ============================================================
// BankAliasModel — alias per-user de un package marcado como banco
// ============================================================
//
// Sincronizable (push+pull, LWW), mismo patrón que AccountCardMappingModel.
// bankId es opcional: si el package está en bank_packages global, el
// cliente lo prefilla; si no, queda null y el alias queda libre
// (display-only, sin pickup automático de parser).

import 'package:pocket_pilot/src/generated/pocket_pilot/v1/bank_alias_service.pb.dart';

class BankAliasModel {
  final String id;
  final String packageName;
  final String? bankId;
  final String displayLabel;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isActive => deletedAt == null;

  const BankAliasModel({
    required this.id,
    required this.packageName,
    required this.bankId,
    required this.displayLabel,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory BankAliasModel.fromProto(BankAlias proto) {
    final rawBankId = proto.bankId.trim();
    return BankAliasModel(
      id: proto.id,
      packageName: proto.packageName,
      bankId: rawBankId.isEmpty ? null : rawBankId,
      displayLabel: proto.displayLabel,
      createdAt: proto.createdAt.toDateTime().toUtc(),
      updatedAt: proto.updatedAt.toDateTime().toUtc(),
      deletedAt: proto.hasDeletedAt()
          ? proto.deletedAt.toDateTime().toUtc()
          : null,
    );
  }

  factory BankAliasModel.fromMap(Map<String, dynamic> map) {
    return BankAliasModel(
      id: map['id'] as String,
      packageName: map['package_name'] as String,
      bankId: map['bank_id'] as String?,
      displayLabel: map['display_label'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String).toUtc()
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'package_name': packageName,
        'bank_id': bankId,
        'display_label': displayLabel,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
      };

  Map<String, dynamic> toServerMap() => toMap();

  BankAliasModel copyWith({
    String? bankId,
    String? displayLabel,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return BankAliasModel(
      id: id,
      packageName: packageName,
      bankId: bankId ?? this.bankId,
      displayLabel: displayLabel ?? this.displayLabel,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }
}
