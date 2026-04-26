// ============================================================
// CapturedNotificationModel — notificación raw capturada por el NLS Android
// ============================================================
//
// Vive 100 % en SQLite local del device que la capturó. Nunca se sincroniza
// con backend (su contenido es PII potencialmente sensible).
//
// Ciclo de vida del campo `status` (ver migrations/007.sql):
//   received        → recién insertada por el NLS, esperando procesamiento
//   matched_local   → un parser local extrajo campos válidos (Fase 2)
//   matched_server  → backend extrajo campos con un parser más nuevo (Fase 4)
//   llm_used        → backend invocó LLM y extrajo campos (Fase 4)
//   ignored         → identificada como no-transacción (OTP, promo)
//   unparseable     → ningún flujo produjo una sugerencia válida
//   consumed        → la PendingTransaction asociada fue aprobada por el user

class CapturedNotificationModel {
  final String id;
  final String packageName;
  final String? title;
  final String? text;
  final String? bigText;
  final DateTime postedAt;
  final String status;
  final String? pendingTxId;
  final DateTime createdAt;

  const CapturedNotificationModel({
    required this.id,
    required this.packageName,
    required this.postedAt,
    required this.status,
    required this.createdAt,
    this.title,
    this.text,
    this.bigText,
    this.pendingTxId,
  });

  factory CapturedNotificationModel.fromMap(Map<String, dynamic> map) {
    return CapturedNotificationModel(
      id: map['id'] as String,
      packageName: map['package_name'] as String,
      title: map['title'] as String?,
      text: map['text'] as String?,
      bigText: map['big_text'] as String?,
      postedAt: DateTime.parse(map['posted_at'] as String).toUtc(),
      status: map['status'] as String,
      pendingTxId: map['pending_tx_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    );
  }

  /// Texto efectivo para mostrar/parsear: prefiere bigText (más completo)
  /// y cae a text para notificaciones colapsadas.
  String get effectiveText {
    final big = bigText?.trim() ?? '';
    if (big.isNotEmpty) return big;
    return text?.trim() ?? '';
  }
}
