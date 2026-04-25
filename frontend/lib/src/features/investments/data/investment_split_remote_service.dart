import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/common.pb.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/investment_split_service.pbgrpc.dart';

class InvestmentSplitRemoteService {
  late final InvestmentSplitServiceClient _client;

  InvestmentSplitRemoteService() {
    _client = InvestmentSplitServiceClient(
      GrpcClient.channel,
      interceptors: GrpcClient.interceptors,
    );
  }

  Future<ListInvestmentSplitsResponse> listSplits({
    DateTime? updatedSince,
    String? pageToken,
    int pageSize = 100,
  }) async {
    try {
      final request = ListInvestmentSplitsRequest(
        page: PageRequest(pageSize: pageSize, pageToken: pageToken ?? ''),
      );
      if (updatedSince != null) {
        request.updatedSince = Timestamp.fromDateTime(updatedSince.toUtc());
      }
      return await _client.listInvestmentSplits(request);
    } on GrpcError catch (e) {
      throw Exception('gRPC listInvestmentSplits error: ${e.message}');
    }
  }

  Future<UpsertInvestmentSplitResponse> upsertSplit(
    Map<String, dynamic> map,
  ) async {
    try {
      final now = DateTime.now().toUtc();
      final split = InvestmentSplit(
        id: map['id'] as String,
        holdingId: map['holding_id'] as String,
        ratioNum: (map['ratio_num'] as num).toDouble(),
        ratioDen: (map['ratio_den'] as num).toDouble(),
        occurredAt: _dateOnly(map['occurred_at'] as String),
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
      if (map['notes'] != null) {
        split.notes = map['notes'] as String;
      }
      return await _client.upsertInvestmentSplit(
        UpsertInvestmentSplitRequest(split: split),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC upsertInvestmentSplit error: ${e.message}');
    }
  }

  Future<void> deleteSplit({
    required String id,
    required DateTime deletedAt,
  }) async {
    try {
      await _client.deleteInvestmentSplit(
        DeleteInvestmentSplitRequest(
          id: id,
          deletedAt: Timestamp.fromDateTime(deletedAt.toUtc()),
        ),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC deleteInvestmentSplit error: ${e.message}');
    }
  }

  static String _dateOnly(String v) => v.length >= 10 ? v.substring(0, 10) : v;
}
