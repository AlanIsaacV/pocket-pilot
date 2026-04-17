import 'package:grpc/grpc.dart';
import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/sync_service.pbgrpc.dart';

/// Thin wrapper around the SyncService.GetSyncStatus RPC.
///
/// Returns the server's per-entity cursors (keys are the same strings
/// returned by SyncHandler.entityType). Missing entities are filled
/// server-side with 1970-01-01T00:00:00Z so callers never see null.
class SyncStatusRemoteService {
  late final SyncServiceClient _client;

  SyncStatusRemoteService() {
    _client = SyncServiceClient(
      GrpcClient.channel,
      interceptors: GrpcClient.interceptors,
    );
  }

  Future<Map<String, DateTime>> getSyncStatus() async {
    try {
      final response = await _client.getSyncStatus(GetSyncStatusRequest());
      return {
        for (final entry in response.cursors.entries)
          entry.key: entry.value.toDateTime().toUtc(),
      };
    } on GrpcError catch (e) {
      throw Exception('gRPC getSyncStatus error: ${e.message}');
    }
  }
}
