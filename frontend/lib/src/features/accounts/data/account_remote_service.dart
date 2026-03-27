import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:pocket_pilot/src/generated/pocket_pilot/v1/account_service.pbgrpc.dart';
import 'package:pocket_pilot/src/core/grpc/auth_interceptor.dart';
import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';

class AccountRemoteService {
  late final AccountServiceClient _client;

  AccountRemoteService() {
    _client = AccountServiceClient(
      GrpcClient.channel,
      interceptors: [const AuthInterceptor()],
    );
  }

  Future<ListAccountsResponse> listAccounts({DateTime? updatedSince}) async {
    try {
      final request = ListAccountsRequest();
      if (updatedSince != null) {
        request.updatedSince = Timestamp.fromDateTime(updatedSince.toUtc());
      }
      return await _client.listAccounts(request);
    } on GrpcError catch (e) {
      throw Exception('gRPC listAccounts error: ${e.message}');
    }
  }

  Future<UpsertAccountResponse> upsertAccount(Map<String, dynamic> map) async {
    try {
      final account = _buildProto(map);
      return await _client.upsertAccount(
        UpsertAccountRequest(account: account),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC upsertAccount error: ${e.message}');
    }
  }

  Future<void> deleteAccount({
    required String id,
    required DateTime deletedAt,
  }) async {
    try {
      await _client.deleteAccount(
        DeleteAccountRequest(
          id: id,
          deletedAt: Timestamp.fromDateTime(deletedAt.toUtc()),
        ),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC deleteAccount error: ${e.message}');
    }
  }

  Account _buildProto(Map<String, dynamic> map) {
    final creditLimitCents = map['credit_limit_cents'] as int?;
    final statementDay = map['statement_day'] as int?;
    final paymentDueDay = map['payment_due_day'] as int?;
    final interestRateApr = map['interest_rate_apr'] as int?;
    final termMonths = map['term_months'] as int?;

    return Account(
      id: map['id'] as String,
      name: map['name'] as String,
      type: AccountModel.stringToAccountType(map['type'] as String),
      currencyCode: map['currency_code'] as String,
      creditLimitCents: creditLimitCents != null
          ? Int64(creditLimitCents)
          : null,
      statementDay: statementDay,
      paymentDueDay: paymentDueDay,
      interestRateApr: interestRateApr,
      termMonths: termMonths,
      createdAt: Timestamp.fromDateTime(
        DateTime.parse(map['created_at'] as String).toUtc(),
      ),
      updatedAt: Timestamp.fromDateTime(
        DateTime.parse(map['updated_at'] as String).toUtc(),
      ),
    );
  }
}
