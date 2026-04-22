import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/common.pb.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/market_price_service.pbgrpc.dart';

class MarketPriceRemoteService {
  late final MarketPriceServiceClient _client;

  MarketPriceRemoteService() {
    _client = MarketPriceServiceClient(
      GrpcClient.channel,
      interceptors: GrpcClient.interceptors,
    );
  }

  Future<ListMarketPricesResponse> listPrices({
    DateTime? updatedSince,
    String? pageToken,
    int pageSize = 100,
  }) async {
    try {
      final request = ListMarketPricesRequest(
        page: PageRequest(pageSize: pageSize, pageToken: pageToken ?? ''),
      );
      if (updatedSince != null) {
        request.updatedSince = Timestamp.fromDateTime(updatedSince.toUtc());
      }
      return await _client.listMarketPrices(request);
    } on GrpcError catch (e) {
      throw Exception('gRPC listMarketPrices error: ${e.message}');
    }
  }
}
