import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:pocket_pilot/src/core/grpc/auth_interceptor.dart';
import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/user_preferences_service.pbgrpc.dart';

class UserPreferenceRemoteService {
  late final UserPreferenceServiceClient _client;

  UserPreferenceRemoteService() {
    _client = UserPreferenceServiceClient(
      GrpcClient.channel,
      interceptors: [const AuthInterceptor()],
    );
  }

  Future<ListUserPreferencesResponse> listPreferences({
    DateTime? updatedSince,
  }) async {
    try {
      final request = ListUserPreferencesRequest();
      if (updatedSince != null) {
        request.updatedSince = Timestamp.fromDateTime(updatedSince.toUtc());
      }
      return await _client.listUserPreferences(request);
    } on GrpcError catch (e) {
      throw Exception('gRPC listUserPreferences error: ${e.message}');
    }
  }

  Future<UpsertUserPreferenceResponse> upsertPreference(
    Map<String, dynamic> map,
  ) async {
    try {
      final now = DateTime.now().toUtc();
      final preference = UserPreference(
        prefKey: map['pref_key'] as String,
        prefValue: map['pref_value'] as String,
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
      return await _client.upsertUserPreference(
        UpsertUserPreferenceRequest(preference: preference),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC upsertUserPreference error: ${e.message}');
    }
  }

  Future<void> deletePreference({
    required String prefKey,
    required DateTime deletedAt,
  }) async {
    try {
      await _client.deleteUserPreference(
        DeleteUserPreferenceRequest(
          prefKey: prefKey,
          deletedAt: Timestamp.fromDateTime(deletedAt.toUtc()),
        ),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC deleteUserPreference error: ${e.message}');
    }
  }
}
