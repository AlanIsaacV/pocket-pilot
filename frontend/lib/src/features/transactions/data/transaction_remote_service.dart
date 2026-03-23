import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:pocket_pilot/src/generated/pocket_pilot/v1/transaction_service.pbgrpc.dart';
import 'package:pocket_pilot/src/core/grpc/auth_interceptor.dart';
import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';

class TransactionRemoteService {
  late final TransactionServiceClient _client;

  TransactionRemoteService() {
    _client = TransactionServiceClient(
      GrpcClient.channel,
      interceptors: [const AuthInterceptor()],
    );
  }

  Future<ListTransactionsResponse> listTransactions({DateTime? updatedSince}) async {
    try {
      final request = ListTransactionsRequest();
      if (updatedSince != null) {
        request.updatedSince = Timestamp.fromDateTime(updatedSince.toUtc());
      }
      return await _client.listTransactions(request);
    } on GrpcError catch (e) {
      throw Exception('gRPC listTransactions error: ${e.message}');
    }
  }

  Future<UpsertTransactionResponse> upsertTransaction(Map<String, dynamic> map) async {
    try {
      final now = DateTime.now().toUtc();
      final transaction = Transaction(
        id: map['id'] as String,
        accountId: map['account_id'] as String,
        categoryId: map['category_id'] as String,
        type: TransactionType.TRANSACTION_TYPE_UNSPECIFIED,
        amountCents: Int64(map['amount'] as int),
        currencyCode: map['currency_code'] as String,
        status: map['status'] as String? ?? 'confirmed',
        description: map['description'] as String,
        date: Timestamp.fromDateTime(DateTime.parse(map['date'] as String).toUtc()),
        updatedAt: Timestamp.fromDateTime(
            map['updated_at'] != null
                ? DateTime.parse(map['updated_at'] as String).toUtc()
                : now),
      );
      return await _client.upsertTransaction(
          UpsertTransactionRequest(transaction: transaction));
    } on GrpcError catch (e) {
      throw Exception('gRPC upsertTransaction error: ${e.message}');
    }
  }

  Future<void> deleteTransaction({
    required String id,
    required DateTime deletedAt,
  }) async {
    try {
      await _client.deleteTransaction(
        DeleteTransactionRequest(
          id: id,
          deletedAt: Timestamp.fromDateTime(deletedAt.toUtc()),
        ),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC deleteTransaction error: ${e.message}');
    }
  }
}
