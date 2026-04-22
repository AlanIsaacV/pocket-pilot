import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/common.pb.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/investment_lot_service.pbgrpc.dart';

class InvestmentLotRemoteService {
  late final InvestmentLotServiceClient _client;

  InvestmentLotRemoteService() {
    _client = InvestmentLotServiceClient(
      GrpcClient.channel,
      interceptors: GrpcClient.interceptors,
    );
  }

  Future<ListInvestmentLotsResponse> listLots({
    DateTime? updatedSince,
    String? pageToken,
    int pageSize = 100,
  }) async {
    try {
      final request = ListInvestmentLotsRequest(
        page: PageRequest(pageSize: pageSize, pageToken: pageToken ?? ''),
      );
      if (updatedSince != null) {
        request.updatedSince = Timestamp.fromDateTime(updatedSince.toUtc());
      }
      return await _client.listInvestmentLots(request);
    } on GrpcError catch (e) {
      throw Exception('gRPC listInvestmentLots error: ${e.message}');
    }
  }

  Future<UpsertInvestmentLotResponse> upsertLot(
    Map<String, dynamic> map,
  ) async {
    try {
      final now = DateTime.now().toUtc();
      final lot = InvestmentLot(
        id: map['id'] as String,
        holdingId: map['holding_id'] as String,
        accountId: (map['account_id'] as String?) ?? '',
        kind: (map['kind'] as String).toLowerCase(),
        quantity: (map['quantity'] as num).toDouble(),
        price: (map['price'] as num).toDouble(),
        feeCents: Int64(map['fee_cents'] as int),
        occurredAt: _dateOnly(map['occurred_at'] as String),
        validity: ((map['validity'] as String?) ?? 'valid').toLowerCase(),
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
      if (map['fx_rate'] != null) {
        lot.fxRate = (map['fx_rate'] as num).toDouble();
      }
      if (map['notes'] != null) {
        lot.notes = map['notes'] as String;
      }
      return await _client.upsertInvestmentLot(
        UpsertInvestmentLotRequest(lot: lot),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC upsertInvestmentLot error: ${e.message}');
    }
  }

  Future<void> deleteLot({
    required String id,
    required DateTime deletedAt,
  }) async {
    try {
      await _client.deleteInvestmentLot(
        DeleteInvestmentLotRequest(
          id: id,
          deletedAt: Timestamp.fromDateTime(deletedAt.toUtc()),
        ),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC deleteInvestmentLot error: ${e.message}');
    }
  }

  static String _dateOnly(String v) => v.length >= 10 ? v.substring(0, 10) : v;
}
