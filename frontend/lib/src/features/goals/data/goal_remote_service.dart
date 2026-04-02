import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:pocket_pilot/src/core/grpc/auth_interceptor.dart';
import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/goal_service.pbgrpc.dart';

class GoalRemoteService {
  late final GoalServiceClient _client;

  GoalRemoteService() {
    _client = GoalServiceClient(
      GrpcClient.channel,
      interceptors: [const AuthInterceptor()],
    );
  }

  Future<ListGoalsResponse> listGoals({DateTime? updatedSince}) async {
    try {
      final request = ListGoalsRequest();
      if (updatedSince != null) {
        request.updatedSince = Timestamp.fromDateTime(updatedSince.toUtc());
      }
      return await _client.listGoals(request);
    } on GrpcError catch (e) {
      throw Exception('gRPC listGoals error: ${e.message}');
    }
  }

  Future<UpsertGoalResponse> upsertGoal(Map<String, dynamic> map) async {
    try {
      final now = DateTime.now().toUtc();
      final goal = Goal(
        id: map['id'] as String,
        name: map['name'] as String,
        targetAmountCents: Int64(_asInt(map['target_amount_cents'])),
        savedAmountCents: Int64(_asInt(map['saved_amount_cents'])),
        targetDate: _dateOnly(map['target_date'] as String),
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

      return await _client.upsertGoal(UpsertGoalRequest(goal: goal));
    } on GrpcError catch (e) {
      throw Exception('gRPC upsertGoal error: ${e.message}');
    }
  }

  Future<void> deleteGoal({
    required String id,
    required DateTime deletedAt,
  }) async {
    try {
      await _client.deleteGoal(
        DeleteGoalRequest(
          id: id,
          deletedAt: Timestamp.fromDateTime(deletedAt.toUtc()),
        ),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC deleteGoal error: ${e.message}');
    }
  }

  static int _asInt(Object raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.parse(raw.toString());
  }

  static String _dateOnly(String value) {
    return value.length >= 10 ? value.substring(0, 10) : value;
  }
}
