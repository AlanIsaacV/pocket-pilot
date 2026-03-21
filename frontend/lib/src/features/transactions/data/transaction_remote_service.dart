// ============================================================
// TransactionRemoteService — wrapper delgado de gRPC para transacciones
// ============================================================

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
// pbgrpc re-exporta pb.dart — cubre Transaction, CreateTransactionRequest, etc.
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/transaction_service.pbgrpc.dart';
// common.pb.dart no es re-exportado, necesario para Money.
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/common.pb.dart';

import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';

class TransactionRemoteService {
  late final TransactionServiceClient _client;

  TransactionRemoteService() {
    _client = TransactionServiceClient(GrpcClient.channel);
  }

  /// Lista todas las transacciones del usuario.
  /// El servidor soporta filtros opcionales (accountId, categoryId,
  /// dateFrom, dateTo) pero para el MVP pedimos todo sin filtros.
  Future<List<Transaction>> listTransactions(String userId) async {
    try {
      final response = await _client.listTransactions(
        ListTransactionsRequest(userId: userId),
      );
      return response.transactions;
    } on GrpcError catch (e) {
      throw Exception('gRPC listTransactions error: ${e.message}');
    }
  }

  /// Crea una nueva transacción en el servidor.
  ///
  /// [date] debe ser un string ISO 8601: "YYYY-MM-DD". Ejemplo: "2026-03-14".
  Future<Transaction> createTransaction({
    required String userId,
    required String accountId,
    required String categoryId,
    required int amountMinor,
    required String currencyCode,
    required String description,
    required String date,
  }) async {
    try {
      final response = await _client.createTransaction(
        CreateTransactionRequest(
          userId: userId,
          accountId: accountId,
          categoryId: categoryId,
          amount: Money(
            amountMinor: Int64(amountMinor),
            currencyCode: currencyCode,
          ),
          description: description,
          date: date,
        ),
      );
      return response.transaction;
    } on GrpcError catch (e) {
      throw Exception('gRPC createTransaction error: ${e.message}');
    }
  }

  /// Elimina una transacción.
  Future<void> deleteTransaction({
    required String userId,
    required String transactionId,
  }) async {
    try {
      await _client.deleteTransaction(
        DeleteTransactionRequest(
          userId: userId,
          transactionId: transactionId,
        ),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC deleteTransaction error: ${e.message}');
    }
  }
}
