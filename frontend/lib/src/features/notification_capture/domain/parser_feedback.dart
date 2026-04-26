// ============================================================
// ParserFeedbackModel — señal de calidad por sugerencia
// ============================================================
//
// Push-only: se inserta en cada decisión final del usuario en
// PendingReviewSheet (aprobar O descartar). Combina un thumb explícito
// opcional (was_helpful, tri-estado: null/true/false) con flags derivados
// que comparan los valores sugeridos por el parser vs los finales.
//
// La trazabilidad (bank_id, pattern_id, parser_version, extraction_method)
// permite agregar señales por parser/pattern para guiar al admin que
// promueve regex desde candidate_parsers.

import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:protobuf/well_known_types/google/protobuf/wrappers.pb.dart';

import 'package:pocket_pilot/src/generated/pocket_pilot/v1/parser_feedback_service.pb.dart';

class ParserFeedbackModel {
  final String id;
  final String pendingTransactionId;
  final String? capturedNotificationId;
  final String? bankId;
  final String? patternId;
  final int? parserVersion;
  final String? extractionMethod; // 'local' | 'llm' | null
  final bool? wasHelpful; // null = sin opinión explícita
  final bool accountChanged;
  final bool categoryChanged;
  final bool amountChanged;
  final bool descriptionChanged;
  final bool wasDismissed;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const ParserFeedbackModel({
    required this.id,
    required this.pendingTransactionId,
    this.capturedNotificationId,
    this.bankId,
    this.patternId,
    this.parserVersion,
    this.extractionMethod,
    this.wasHelpful,
    required this.accountChanged,
    required this.categoryChanged,
    required this.amountChanged,
    required this.descriptionChanged,
    required this.wasDismissed,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory ParserFeedbackModel.fromMap(Map<String, dynamic> map) {
    int? readInt(Object? v) => v == null ? null : (v as num).toInt();
    bool? readBool(Object? v) => v == null ? null : (v as num).toInt() == 1;
    bool readBoolOrFalse(Object? v) => v != null && (v as num).toInt() == 1;

    return ParserFeedbackModel(
      id: map['id'] as String,
      pendingTransactionId: map['pending_transaction_id'] as String,
      capturedNotificationId: map['captured_notification_id'] as String?,
      bankId: map['bank_id'] as String?,
      patternId: map['pattern_id'] as String?,
      parserVersion: readInt(map['parser_version']),
      extractionMethod: map['extraction_method'] as String?,
      wasHelpful: readBool(map['was_helpful']),
      accountChanged: readBoolOrFalse(map['account_changed']),
      categoryChanged: readBoolOrFalse(map['category_changed']),
      amountChanged: readBoolOrFalse(map['amount_changed']),
      descriptionChanged: readBoolOrFalse(map['description_changed']),
      wasDismissed: readBoolOrFalse(map['was_dismissed']),
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String).toUtc()
          : null,
    );
  }

  /// Map para SQLite local — booleans como INTEGER 0|1|NULL.
  Map<String, dynamic> toMap() => {
        'id': id,
        'pending_transaction_id': pendingTransactionId,
        'captured_notification_id': capturedNotificationId,
        'bank_id': bankId,
        'pattern_id': patternId,
        'parser_version': parserVersion,
        'extraction_method': extractionMethod,
        'was_helpful': wasHelpful == null ? null : (wasHelpful! ? 1 : 0),
        'account_changed': accountChanged ? 1 : 0,
        'category_changed': categoryChanged ? 1 : 0,
        'amount_changed': amountChanged ? 1 : 0,
        'description_changed': descriptionChanged ? 1 : 0,
        'was_dismissed': wasDismissed ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
      };

  /// Payload para outbox. Mismo shape que toMap() — el remote service lo
  /// consume y construye el proto.
  Map<String, dynamic> toServerMap() => {
        'id': id,
        'pending_transaction_id': pendingTransactionId,
        'captured_notification_id': capturedNotificationId,
        'bank_id': bankId,
        'pattern_id': patternId,
        'parser_version': parserVersion,
        'extraction_method': extractionMethod,
        'was_helpful': wasHelpful, // bool? — se serializa como true/false/null
        'account_changed': accountChanged,
        'category_changed': categoryChanged,
        'amount_changed': amountChanged,
        'description_changed': descriptionChanged,
        'was_dismissed': wasDismissed,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
      };

  factory ParserFeedbackModel.fromProto(ParserFeedback proto) {
    return ParserFeedbackModel(
      id: proto.id,
      pendingTransactionId: proto.pendingTransactionId,
      capturedNotificationId: proto.capturedNotificationId.isEmpty
          ? null
          : proto.capturedNotificationId,
      bankId: proto.bankId.isEmpty ? null : proto.bankId,
      patternId: proto.patternId.isEmpty ? null : proto.patternId,
      parserVersion: proto.parserVersion == 0 ? null : proto.parserVersion,
      extractionMethod:
          proto.extractionMethod.isEmpty ? null : proto.extractionMethod,
      wasHelpful: proto.hasWasHelpful() ? proto.wasHelpful.value : null,
      accountChanged: proto.accountChanged,
      categoryChanged: proto.categoryChanged,
      amountChanged: proto.amountChanged,
      descriptionChanged: proto.descriptionChanged,
      wasDismissed: proto.wasDismissed,
      createdAt: proto.createdAt.toDateTime().toUtc(),
      updatedAt: proto.updatedAt.toDateTime().toUtc(),
      deletedAt:
          proto.hasDeletedAt() ? proto.deletedAt.toDateTime().toUtc() : null,
    );
  }

  ParserFeedback toProto() {
    final proto = ParserFeedback(
      id: id,
      pendingTransactionId: pendingTransactionId,
      capturedNotificationId: capturedNotificationId ?? '',
      bankId: bankId ?? '',
      patternId: patternId ?? '',
      parserVersion: parserVersion ?? 0,
      extractionMethod: extractionMethod ?? '',
      accountChanged: accountChanged,
      categoryChanged: categoryChanged,
      amountChanged: amountChanged,
      descriptionChanged: descriptionChanged,
      wasDismissed: wasDismissed,
      createdAt: Timestamp.fromDateTime(createdAt),
      updatedAt: Timestamp.fromDateTime(updatedAt),
    );
    if (wasHelpful != null) {
      proto.wasHelpful = BoolValue(value: wasHelpful);
    }
    if (deletedAt != null) {
      proto.deletedAt = Timestamp.fromDateTime(deletedAt!);
    }
    return proto;
  }
}
