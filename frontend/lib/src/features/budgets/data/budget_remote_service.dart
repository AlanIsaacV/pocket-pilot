import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/budget_service.pbgrpc.dart';

class BudgetRemoteService {
  late final BudgetServiceClient _client;

  BudgetRemoteService() {
    _client = BudgetServiceClient(
      GrpcClient.channel,
      interceptors: GrpcClient.interceptors,
    );
  }

  Future<ListBudgetsResponse> listBudgets({DateTime? updatedSince}) async {
    try {
      final request = ListBudgetsRequest();
      if (updatedSince != null) {
        request.updatedSince = Timestamp.fromDateTime(updatedSince.toUtc());
      }
      return await _client.listBudgets(request);
    } on GrpcError catch (e) {
      throw Exception('gRPC listBudgets error: ${e.message}');
    }
  }

  Future<UpsertBudgetResponse> upsertBudget(Map<String, dynamic> map) async {
    try {
      final now = DateTime.now().toUtc();
      final budget = Budget(
        id: map['id'] as String,
        categoryId: map['category_id'] as String,
        limitAmountCents: Int64(_asInt(map['limit_amount_cents'])),
        currencyCode: map['currency_code'] as String,
        period: map['period'] as String,
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

      return await _client.upsertBudget(UpsertBudgetRequest(budget: budget));
    } on GrpcError catch (e) {
      throw Exception('gRPC upsertBudget error: ${e.message}');
    }
  }

  Future<void> deleteBudget({
    required String id,
    required DateTime deletedAt,
  }) async {
    try {
      await _client.deleteBudget(
        DeleteBudgetRequest(
          id: id,
          deletedAt: Timestamp.fromDateTime(deletedAt.toUtc()),
        ),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC deleteBudget error: ${e.message}');
    }
  }

  static int _asInt(Object raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.parse(raw.toString());
  }
}
