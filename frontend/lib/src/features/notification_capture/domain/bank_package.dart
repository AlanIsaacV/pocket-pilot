// ============================================================
// BankPackageModel — entrada del catálogo global pull-only
// ============================================================
//
// Mismo rol que NotificationParserDefinition: cache local de una tabla
// global del backend. El admin promueve sugerencias a este catálogo y
// el cliente las recibe en el siguiente sync.

class BankPackageModel {
  final String packageName;
  final String bankId;
  final String defaultLabel;
  final bool isActive;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isAvailable => isActive && deletedAt == null;

  const BankPackageModel({
    required this.packageName,
    required this.bankId,
    required this.defaultLabel,
    required this.isActive,
    required this.updatedAt,
    this.deletedAt,
  });

  factory BankPackageModel.fromMap(Map<String, dynamic> map) {
    return BankPackageModel(
      packageName: map['package_name'] as String,
      bankId: map['bank_id'] as String,
      defaultLabel: map['default_label'] as String,
      isActive: ((map['is_active'] as num?) ?? 1).toInt() == 1,
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String).toUtc()
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'package_name': packageName,
        'bank_id': bankId,
        'default_label': defaultLabel,
        'is_active': isActive ? 1 : 0,
        'updated_at': updatedAt.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
      };
}
