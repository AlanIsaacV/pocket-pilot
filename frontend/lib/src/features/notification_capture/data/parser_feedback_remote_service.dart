import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:protobuf/well_known_types/google/protobuf/wrappers.pb.dart';

import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/parser_feedback_service.pbgrpc.dart';

class ParserFeedbackRemoteService {
  late final ParserFeedbackServiceClient _client;

  ParserFeedbackRemoteService() {
    _client = ParserFeedbackServiceClient(
      GrpcClient.channel,
      interceptors: GrpcClient.interceptors,
    );
  }

  Future<UpsertParserFeedbackResponse> upsertFeedback(
    Map<String, dynamic> map,
  ) async {
    try {
      final now = DateTime.now().toUtc();
      final feedback = ParserFeedback(
        id: map['id'] as String,
        pendingTransactionId: map['pending_transaction_id'] as String,
        capturedNotificationId:
            (map['captured_notification_id'] as String?) ?? '',
        bankId: (map['bank_id'] as String?) ?? '',
        patternId: (map['pattern_id'] as String?) ?? '',
        parserVersion: (map['parser_version'] as num?)?.toInt() ?? 0,
        extractionMethod: (map['extraction_method'] as String?) ?? '',
        accountChanged: (map['account_changed'] as bool?) ?? false,
        categoryChanged: (map['category_changed'] as bool?) ?? false,
        amountChanged: (map['amount_changed'] as bool?) ?? false,
        descriptionChanged: (map['description_changed'] as bool?) ?? false,
        wasDismissed: (map['was_dismissed'] as bool?) ?? false,
        createdAt: Timestamp.fromDateTime(
          map['created_at'] != null
              ? DateTime.parse(map['created_at'] as String).toUtc()
              : now,
        ),
        updatedAt: Timestamp.fromDateTime(
          map['updated_at'] != null
              ? DateTime.parse(map['updated_at'] as String).toUtc()
              : now,
        ),
      );
      final wasHelpful = map['was_helpful'];
      if (wasHelpful is bool) {
        feedback.wasHelpful = BoolValue(value: wasHelpful);
      }
      if (map['deleted_at'] != null) {
        feedback.deletedAt = Timestamp.fromDateTime(
          DateTime.parse(map['deleted_at'] as String).toUtc(),
        );
      }
      return await _client.upsertParserFeedback(
        UpsertParserFeedbackRequest(feedback: feedback),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC upsertParserFeedback error: ${e.message}');
    }
  }
}
