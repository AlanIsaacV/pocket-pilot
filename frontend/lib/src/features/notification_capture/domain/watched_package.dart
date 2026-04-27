// ============================================================
// WatchedPackageModel — per-device toggle "capturar este package aquí"
// ============================================================
//
// Local-only, sin outbox. La decisión de qué packages procesa el NLS Kotlin
// es per-device porque la captura es device-side. El alias para mostrar
// vive en BankAliasModel (esa sí sincroniza per-user).

class WatchedPackageModel {
  final String id;
  final String packageName;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  const WatchedPackageModel({
    required this.id,
    required this.packageName,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WatchedPackageModel.fromMap(Map<String, dynamic> map) {
    return WatchedPackageModel(
      id: map['id'] as String,
      packageName: map['package_name'] as String,
      enabled: ((map['enabled'] as num?) ?? 0).toInt() == 1,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'package_name': packageName,
        'enabled': enabled ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  WatchedPackageModel copyWith({bool? enabled, DateTime? updatedAt}) =>
      WatchedPackageModel(
        id: id,
        packageName: packageName,
        enabled: enabled ?? this.enabled,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
