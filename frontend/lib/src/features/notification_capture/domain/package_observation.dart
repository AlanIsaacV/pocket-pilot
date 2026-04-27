// ============================================================
// PackageObservationModel — log local sin PII de packages observados
// ============================================================
//
// Cada vez que el NLS Kotlin recibe una notificación (de cualquier app),
// hace UPSERT incrementando `noti_count` y actualizando `last_seen_at`.
// El picker "Mis bancos" consulta esta tabla para listar los packages
// que de hecho notifican en el dispositivo, sin requerir QUERY_ALL_PACKAGES.

class PackageObservationModel {
  final String packageName;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final int notiCount;
  final DateTime? purgedAt;

  const PackageObservationModel({
    required this.packageName,
    required this.firstSeenAt,
    required this.lastSeenAt,
    required this.notiCount,
    this.purgedAt,
  });

  factory PackageObservationModel.fromMap(Map<String, dynamic> map) {
    return PackageObservationModel(
      packageName: map['package_name'] as String,
      firstSeenAt: DateTime.parse(map['first_seen_at'] as String).toUtc(),
      lastSeenAt: DateTime.parse(map['last_seen_at'] as String).toUtc(),
      notiCount: (map['noti_count'] as num).toInt(),
      purgedAt: map['purged_at'] != null
          ? DateTime.parse(map['purged_at'] as String).toUtc()
          : null,
    );
  }
}
