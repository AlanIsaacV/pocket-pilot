import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/common.pb.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/notification_parser_service.pbgrpc.dart';

/// Excepción que indica que el rate limit (cuota diaria/mensual) del feature
/// `notification_parser` se agotó server-side. El llamador debería tratarlo
/// como recoverable: marcar la noti como unparseable y reintentar más tarde
/// (la cuota diaria se reinicia y el botón "Reintentar no parseables"
/// vuelve a invocar el path).
class ParserQuotaExceededException implements Exception {
  final String message;
  const ParserQuotaExceededException(this.message);
  @override
  String toString() => 'ParserQuotaExceededException: $message';
}

/// Resultado decodificado de ParseNotification — un wrapper sobre el response
/// pb que oculta el detalle de protobuf al repositorio.
class ParseNotificationOutcome {
  final bool matched;
  final int amountCents;
  final String currencyCode;
  final String merchantDescription;
  final String cardLastDigits;
  final String transactionType;
  final String proposedPatternId;

  const ParseNotificationOutcome({
    required this.matched,
    required this.amountCents,
    required this.currencyCode,
    required this.merchantDescription,
    required this.cardLastDigits,
    required this.transactionType,
    required this.proposedPatternId,
  });

  const ParseNotificationOutcome.notMatched()
      : matched = false,
        amountCents = 0,
        currencyCode = '',
        merchantDescription = '',
        cardLastDigits = '',
        transactionType = '',
        proposedPatternId = '';
}

/// Cliente gRPC para `notification_parsers`. Pull-only para la lista; en
/// Fase 4 expone también `parseNotification` (LLM fallback server-side).
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

  /// Llama al fallback LLM server-side. Devuelve un outcome con `matched=false`
  /// si el LLM no reconoció la noti como transaccional. Lanza
  /// [ParserQuotaExceededException] si la cuota del usuario para este feature
  /// está agotada (RESOURCE_EXHAUSTED). Otros errores gRPC (red, 5xx) se
  /// propagan para que el repositorio los trate como fallo no-fatal y deje
  /// la noti unparseable.
  Future<ParseNotificationOutcome> parseNotification({
    required String packageName,
    required String title,
    required String text,
    required String bigText,
    required bool helpImproveApp,
  }) async {
    final request = ParseNotificationRequest(
      packageName: packageName,
      title: title,
      text: text,
      bigText: bigText,
      helpImproveApp: helpImproveApp,
    );
    try {
      final resp = await _client.parseNotification(request);
      if (!resp.matched) return const ParseNotificationOutcome.notMatched();
      return ParseNotificationOutcome(
        matched: true,
        amountCents: resp.amountCents.toInt(),
        currencyCode: resp.currencyCode,
        merchantDescription: resp.merchantDescription,
        cardLastDigits: resp.cardLastDigits,
        transactionType: resp.transactionType,
        proposedPatternId: resp.proposedPatternId,
      );
    } on GrpcError catch (e) {
      if (e.code == StatusCode.resourceExhausted) {
        throw ParserQuotaExceededException(e.message ?? 'quota exceeded');
      }
      rethrow;
    }
  }
}
