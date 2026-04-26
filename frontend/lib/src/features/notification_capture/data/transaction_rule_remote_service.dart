import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/common.pb.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/transaction_rule_service.pbgrpc.dart';

class TransactionRuleRemoteService {
  late final TransactionRuleServiceClient _client;

  TransactionRuleRemoteService() {
    _client = TransactionRuleServiceClient(
      GrpcClient.channel,
      interceptors: GrpcClient.interceptors,
    );
  }

  Future<ListTransactionRulesResponse> listRules({
    DateTime? updatedSince,
    String? pageToken,
    int pageSize = 100,
  }) async {
    try {
      final request = ListTransactionRulesRequest(
        page: PageRequest(pageSize: pageSize, pageToken: pageToken ?? ''),
      );
      if (updatedSince != null) {
        request.updatedSince = Timestamp.fromDateTime(updatedSince.toUtc());
      }
      return await _client.listTransactionRules(request);
    } on GrpcError catch (e) {
      throw Exception('gRPC listTransactionRules error: ${e.message}');
    }
  }

  Future<UpsertTransactionRuleResponse> upsertRule(
    Map<String, dynamic> map,
  ) async {
    try {
      final now = DateTime.now().toUtc();
      final rule = TransactionRule(
        id: map['id'] as String,
        matchText: map['match_text'] as String,
        categoryId: map['category_id'] as String,
        priority: (map['priority'] as int?) ?? 0,
        matchCount: (map['match_count'] as int?) ?? 0,
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
      if (map['deleted_at'] != null) {
        rule.deletedAt = Timestamp.fromDateTime(
          DateTime.parse(map['deleted_at'] as String).toUtc(),
        );
      }
      return await _client.upsertTransactionRule(
        UpsertTransactionRuleRequest(rule: rule),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC upsertTransactionRule error: ${e.message}');
    }
  }

  Future<void> deleteRule({
    required String id,
    required DateTime deletedAt,
  }) async {
    try {
      await _client.deleteTransactionRule(
        DeleteTransactionRuleRequest(
          id: id,
          deletedAt: Timestamp.fromDateTime(deletedAt.toUtc()),
        ),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC deleteTransactionRule error: ${e.message}');
    }
  }
}
