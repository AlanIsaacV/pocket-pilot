// ============================================================
// PendingTransactionModel — sugerencia derivada de una notificación
// ============================================================
//
// Tabla local-only: vive solo en el dispositivo Android donde se capturó la
// notificación origen. Al aprobarse se materializa como un `Transaction`
// regular (que SÍ se sincroniza vía outbox).
//
// `source` indica de dónde provino la sugerencia:
//   parser_local  → un parser cacheado en el device hizo match
//   parser_server → backend tenía un parser más nuevo que el del device
//   llm           → backend invocó al LLM y extrajo los campos

class PendingTransactionModel {
  final String id;
  final String? capturedNotificationId;
  final String? suggestedAccountId;
  final String? suggestedCategoryId;
  final int amountCents;
  final String currencyCode;
  final String? merchantDescription;
  final String? cardLastDigits;

  /// 'income' | 'expense'
  final String transactionType;
  final DateTime occurredAt;

  /// 'parser_local' | 'parser_server' | 'llm'
  final String source;
  final String? parserId;
  final int? parserVersion;
  final double? confidence;

  /// 'pending' | 'approved' | 'dismissed'
  final String status;
  final DateTime createdAt;

  const PendingTransactionModel({
    required this.id,
    required this.amountCents,
    required this.currencyCode,
    required this.transactionType,
    required this.occurredAt,
    required this.source,
    required this.status,
    required this.createdAt,
    this.capturedNotificationId,
    this.suggestedAccountId,
    this.suggestedCategoryId,
    this.merchantDescription,
    this.cardLastDigits,
    this.parserId,
    this.parserVersion,
    this.confidence,
  });

  factory PendingTransactionModel.fromMap(Map<String, dynamic> map) {
    return PendingTransactionModel(
      id: map['id'] as String,
      capturedNotificationId: map['captured_notification_id'] as String?,
      suggestedAccountId: map['suggested_account_id'] as String?,
      suggestedCategoryId: map['suggested_category_id'] as String?,
      amountCents: map['amount_cents'] as int,
      currencyCode: map['currency_code'] as String,
      merchantDescription: map['merchant_description'] as String?,
      cardLastDigits: map['card_last_digits'] as String?,
      transactionType: map['transaction_type'] as String,
      occurredAt: DateTime.parse(map['occurred_at'] as String).toUtc(),
      source: map['source'] as String,
      parserId: map['parser_id'] as String?,
      parserVersion: map['parser_version'] as int?,
      confidence: (map['confidence'] as num?)?.toDouble(),
      status: map['status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'captured_notification_id': capturedNotificationId,
        'suggested_account_id': suggestedAccountId,
        'suggested_category_id': suggestedCategoryId,
        'amount_cents': amountCents,
        'currency_code': currencyCode,
        'merchant_description': merchantDescription,
        'card_last_digits': cardLastDigits,
        'transaction_type': transactionType,
        'occurred_at': occurredAt.toIso8601String(),
        'source': source,
        'parser_id': parserId,
        'parser_version': parserVersion,
        'confidence': confidence,
        'status': status,
        'created_at': createdAt.toIso8601String(),
      };

  PendingTransactionModel copyWith({
    String? suggestedAccountId,
    String? suggestedCategoryId,
    int? amountCents,
    String? currencyCode,
    String? merchantDescription,
    String? cardLastDigits,
    String? transactionType,
    DateTime? occurredAt,
    String? status,
  }) {
    return PendingTransactionModel(
      id: id,
      capturedNotificationId: capturedNotificationId,
      suggestedAccountId: suggestedAccountId ?? this.suggestedAccountId,
      suggestedCategoryId: suggestedCategoryId ?? this.suggestedCategoryId,
      amountCents: amountCents ?? this.amountCents,
      currencyCode: currencyCode ?? this.currencyCode,
      merchantDescription: merchantDescription ?? this.merchantDescription,
      cardLastDigits: cardLastDigits ?? this.cardLastDigits,
      transactionType: transactionType ?? this.transactionType,
      occurredAt: occurredAt ?? this.occurredAt,
      source: source,
      parserId: parserId,
      parserVersion: parserVersion,
      confidence: confidence,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }
}
