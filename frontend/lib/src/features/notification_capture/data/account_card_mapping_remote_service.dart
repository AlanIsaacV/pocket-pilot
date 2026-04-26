import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/account_card_mapping_service.pbgrpc.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/common.pb.dart';

class AccountCardMappingRemoteService {
  late final AccountCardMappingServiceClient _client;

  AccountCardMappingRemoteService() {
    _client = AccountCardMappingServiceClient(
      GrpcClient.channel,
      interceptors: GrpcClient.interceptors,
    );
  }

  Future<ListAccountCardMappingsResponse> listMappings({
    DateTime? updatedSince,
    String? pageToken,
    int pageSize = 100,
  }) async {
    try {
      final request = ListAccountCardMappingsRequest(
        page: PageRequest(pageSize: pageSize, pageToken: pageToken ?? ''),
      );
      if (updatedSince != null) {
        request.updatedSince = Timestamp.fromDateTime(updatedSince.toUtc());
      }
      return await _client.listAccountCardMappings(request);
    } on GrpcError catch (e) {
      throw Exception('gRPC listAccountCardMappings error: ${e.message}');
    }
  }

  Future<UpsertAccountCardMappingResponse> upsertMapping(
    Map<String, dynamic> map,
  ) async {
    try {
      final now = DateTime.now().toUtc();
      final mapping = AccountCardMapping(
        id: map['id'] as String,
        bankId: map['bank_id'] as String,
        lastDigits: map['last_digits'] as String,
        accountId: map['account_id'] as String,
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
        mapping.deletedAt = Timestamp.fromDateTime(
          DateTime.parse(map['deleted_at'] as String).toUtc(),
        );
      }
      return await _client.upsertAccountCardMapping(
        UpsertAccountCardMappingRequest(mapping: mapping),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC upsertAccountCardMapping error: ${e.message}');
    }
  }

  Future<void> deleteMapping({
    required String id,
    required DateTime deletedAt,
  }) async {
    try {
      await _client.deleteAccountCardMapping(
        DeleteAccountCardMappingRequest(
          id: id,
          deletedAt: Timestamp.fromDateTime(deletedAt.toUtc()),
        ),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC deleteAccountCardMapping error: ${e.message}');
    }
  }
}
