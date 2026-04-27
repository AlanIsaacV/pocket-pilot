import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/bank_alias_service.pbgrpc.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/common.pb.dart';

class BankAliasRemoteService {
  late final BankAliasServiceClient _client;

  BankAliasRemoteService() {
    _client = BankAliasServiceClient(
      GrpcClient.channel,
      interceptors: GrpcClient.interceptors,
    );
  }

  Future<ListBankAliasesResponse> listAliases({
    DateTime? updatedSince,
    String? pageToken,
    int pageSize = 100,
  }) async {
    try {
      final request = ListBankAliasesRequest(
        page: PageRequest(pageSize: pageSize, pageToken: pageToken ?? ''),
      );
      if (updatedSince != null) {
        request.updatedSince = Timestamp.fromDateTime(updatedSince.toUtc());
      }
      return await _client.listBankAliases(request);
    } on GrpcError catch (e) {
      throw Exception('gRPC listBankAliases error: ${e.message}');
    }
  }

  Future<UpsertBankAliasResponse> upsertAlias(Map<String, dynamic> map) async {
    try {
      final now = DateTime.now().toUtc();
      final alias = BankAlias(
        id: map['id'] as String,
        packageName: map['package_name'] as String,
        bankId: (map['bank_id'] as String?) ?? '',
        displayLabel: map['display_label'] as String,
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
        alias.deletedAt = Timestamp.fromDateTime(
          DateTime.parse(map['deleted_at'] as String).toUtc(),
        );
      }
      return await _client.upsertBankAlias(
        UpsertBankAliasRequest(alias: alias),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC upsertBankAlias error: ${e.message}');
    }
  }

  Future<void> deleteAlias({
    required String id,
    required DateTime deletedAt,
  }) async {
    try {
      await _client.deleteBankAlias(
        DeleteBankAliasRequest(
          id: id,
          deletedAt: Timestamp.fromDateTime(deletedAt.toUtc()),
        ),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC deleteBankAlias error: ${e.message}');
    }
  }
}
