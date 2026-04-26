import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/common.pb.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/notification_parser_service.pbgrpc.dart';

/// Cliente gRPC pull-only para `notification_parsers`. La app nunca empuja
/// parsers — el operador hace updates server-side y el cliente los recoge en
/// el siguiente sync.
class ParserRemoteService {
  late final NotificationParserServiceClient _client;

  ParserRemoteService() {
    _client = NotificationParserServiceClient(
      GrpcClient.channel,
      interceptors: GrpcClient.interceptors,
    );
  }

  Future<ListNotificationParsersResponse> listParsers({
    DateTime? updatedSince,
    String? pageToken,
    int pageSize = 100,
  }) async {
    try {
      final request = ListNotificationParsersRequest(
        page: PageRequest(pageSize: pageSize, pageToken: pageToken ?? ''),
      );
      if (updatedSince != null) {
        request.updatedSince = Timestamp.fromDateTime(updatedSince.toUtc());
      }
      return await _client.listNotificationParsers(request);
    } on GrpcError catch (e) {
      throw Exception('gRPC listNotificationParsers error: ${e.message}');
    }
  }
}
