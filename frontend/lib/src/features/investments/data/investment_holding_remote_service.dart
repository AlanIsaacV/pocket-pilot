import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/common.pb.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/investment_holding_service.pbgrpc.dart';

class InvestmentHoldingRemoteService {
  late final InvestmentHoldingServiceClient _client;

  InvestmentHoldingRemoteService() {
    _client = InvestmentHoldingServiceClient(
      GrpcClient.channel,
      interceptors: GrpcClient.interceptors,
    );
  }

  Future<ListInvestmentHoldingsResponse> listHoldings({
    DateTime? updatedSince,
    String? pageToken,
    int pageSize = 100,
  }) async {
    try {
      final request = ListInvestmentHoldingsRequest(
        page: PageRequest(pageSize: pageSize, pageToken: pageToken ?? ''),
      );
      if (updatedSince != null) {
        request.updatedSince = Timestamp.fromDateTime(updatedSince.toUtc());
      }
      return await _client.listInvestmentHoldings(request);
    } on GrpcError catch (e) {
      throw Exception('gRPC listInvestmentHoldings error: ${e.message}');
    }
  }

  Future<UpsertInvestmentHoldingResponse> upsertHolding(
    Map<String, dynamic> map,
  ) async {
    try {
      final now = DateTime.now().toUtc();
      final holding = InvestmentHolding(
        id: map['id'] as String,
        symbol: (map['symbol'] as String).toUpperCase(),
        exchange: (map['exchange'] as String).toUpperCase(),
        displayName: (map['display_name'] as String?) ?? '',
        currencyCode: (map['currency_code'] as String).toUpperCase(),
        assetType: (map['asset_type'] as String).toLowerCase(),
        status: (map['status'] as String).toLowerCase(),
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
      if (map['manual_price'] != null) {
        holding.manualPrice = (map['manual_price'] as num).toDouble();
      }
      if (map['notes'] != null) {
        holding.notes = map['notes'] as String;
      }
      return await _client.upsertInvestmentHolding(
        UpsertInvestmentHoldingRequest(holding: holding),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC upsertInvestmentHolding error: ${e.message}');
    }
  }

  Future<void> deleteHolding({
    required String id,
    required DateTime deletedAt,
  }) async {
    try {
      await _client.deleteInvestmentHolding(
        DeleteInvestmentHoldingRequest(
          id: id,
          deletedAt: Timestamp.fromDateTime(deletedAt.toUtc()),
        ),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC deleteInvestmentHolding error: ${e.message}');
    }
  }
}
