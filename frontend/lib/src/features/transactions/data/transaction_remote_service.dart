import 'dart:convert';

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:pocket_pilot/src/generated/pocket_pilot/v1/transaction_service.pbgrpc.dart';
import 'package:pocket_pilot/src/core/grpc/auth_interceptor.dart';
import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
import 'package:pocket_pilot/src/features/transactions/domain/transaction.dart';

class TransactionRemoteService {
  late final TransactionServiceClient _client;

  TransactionRemoteService() {
    _client = TransactionServiceClient(
      GrpcClient.channel,
      interceptors: [const AuthInterceptor()],
    );
  }

  Future<ListTransactionsResponse> listTransactions({
    DateTime? updatedSince,
  }) async {
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

  Future<UpsertTransactionResponse> upsertTransaction(
    Map<String, dynamic> map,
  ) async {
    try {
      final now = DateTime.now().toUtc();
      final installmentsCount = (map['installments_count'] as int?) ?? 1;
      if (installmentsCount < 1) {
        throw ArgumentError.value(
          installmentsCount,
          'installments_count',
          'installments_count must be >= 1',
        );
      }
      final transaction = Transaction(
        id: map['id'] as String,
        accountId: map['account_id'] as String,
        type: TransactionModel.stringToTransactionType(map['type'] as String),
        amountCents: Int64(map['amount_cents'] as int),
        installmentsCount: installmentsCount,
        currencyCode: map['currency_code'] as String,
        status: map['status'] as String? ?? 'cleared',
        tags: _toTags(map['tags']),
        description: map['description'] as String,
        date: Timestamp.fromDateTime(
          DateTime.parse(map['date'] as String).toUtc(),
        ),
        updatedAt: Timestamp.fromDateTime(
          map['updated_at'] != null
              ? DateTime.parse(map['updated_at'] as String).toUtc()
              : now,
        ),
      );
      if (map['category_id'] != null) {
        transaction.categoryId = map['category_id'] as String;
      }
      if (map['linked_transaction_id'] != null) {
        transaction.linkedTransactionId =
            map['linked_transaction_id'] as String;
      }
      if (map['template_id'] != null) {
        transaction.templateId = map['template_id'] as String;
      }
      if (map['yield_id'] != null) {
        transaction.yieldId = map['yield_id'] as String;
      }
      return await _client.upsertTransaction(
        UpsertTransactionRequest(transaction: transaction),
      );
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

  static List<String> _toTags(Object? raw) {
    if (raw == null) return const <String>[];
    if (raw is List) {
      return raw.map((e) => e.toString()).toList(growable: false);
    }
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList(growable: false);
        }
      } catch (_) {
        return const <String>[];
      }
    }
    return const <String>[];
  }
}
