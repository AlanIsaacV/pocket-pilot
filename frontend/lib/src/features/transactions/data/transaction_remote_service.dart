// ============================================================
// TransactionRemoteService — wrapper delgado de gRPC para transacciones
// ============================================================

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:pocket_pilot/src/generated/pocket_pilot/v1/transaction_service.pbgrpc.dart';
import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';

class TransactionRemoteService {
  late final TransactionServiceClient _client;

  TransactionRemoteService() {
    _client = TransactionServiceClient(GrpcClient.channel);
  }

  /// Lista transacciones del usuario. Si [updatedSince] está definido,
  /// solo retorna las modificadas después de ese timestamp.
  Future<ListTransactionsResponse> listTransactions(
    String userId, {
    DateTime? updatedSince,
  }) async {
    try {
      final request = ListTransactionsRequest(userId: userId);
      if (updatedSince != null) {
        request.updatedSince = Timestamp.fromDateTime(updatedSince.toUtc());
      }
      return await _client.listTransactions(request);
    } on GrpcError catch (e) {
      throw Exception('gRPC listTransactions error: ${e.message}');
    }
  }

  /// Crea o actualiza una transacción en el servidor.
  ///
  /// [date] debe ser un string ISO 8601: "YYYY-MM-DD". Ejemplo: "2026-03-14".
  Future<UpsertTransactionResponse> upsertTransaction({
    required String id,
    required String userId,
    required String accountId,
    required String categoryId,
    required TransactionType type,
    required int amountCents,
    required String currencyCode,
    required String status,
    required String description,
    required String date, // YYYY-MM-DD
  }) async {
    try {
      final transaction = Transaction(
        id: id,
        userId: userId,
        accountId: accountId,
        categoryId: categoryId,
        type: type,
        amountCents: Int64(amountCents),
        currencyCode: currencyCode,
        status: status,
        description: description,
        date: Timestamp.fromDateTime(DateTime.parse(date).toUtc()),
        updatedAt: Timestamp.fromDateTime(DateTime.now().toUtc()),
      );
      return await _client.upsertTransaction(
          UpsertTransactionRequest(transaction: transaction));
    } on GrpcError catch (e) {
      throw Exception('gRPC upsertTransaction error: ${e.message}');
    }
  }

  /// Elimina lógicamente una transacción.
  Future<void> deleteTransaction({
    required String id,
    required String userId,
    DateTime? deletedAt,
  }) async {
    try {
      await _client.deleteTransaction(
        DeleteTransactionRequest(
          id: id,
          userId: userId,
          deletedAt: Timestamp.fromDateTime(
              (deletedAt ?? DateTime.now()).toUtc()),
        ),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC deleteTransaction error: ${e.message}');
    }
  }
}
