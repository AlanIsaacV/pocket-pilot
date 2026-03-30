import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:pocket_pilot/src/core/grpc/auth_interceptor.dart';
import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/yield_config_service.pbgrpc.dart';

class YieldConfigRemoteService {
  late final YieldConfigServiceClient _client;

  YieldConfigRemoteService() {
    _client = YieldConfigServiceClient(
      GrpcClient.channel,
      interceptors: [const AuthInterceptor()],
    );
  }

  Future<ListYieldConfigsResponse> listConfigs({DateTime? updatedSince}) async {
    try {
      final request = ListYieldConfigsRequest();
      if (updatedSince != null) {
        request.updatedSince = Timestamp.fromDateTime(updatedSince.toUtc());
      }
      return await _client.listYieldConfigs(request);
    } on GrpcError catch (e) {
      throw Exception('gRPC listYieldConfigs error: ${e.message}');
    }
  }

  Future<UpsertYieldConfigResponse> upsertConfig(
    Map<String, dynamic> map,
  ) async {
    try {
      final now = DateTime.now().toUtc();
      final config = YieldConfig(
        id: map['id'] as String,
        accountId: map['account_id'] as String,
        name: map['name'] as String,
        amountCents: Int64(map['amount_cents'] as int),
        apyRate: (map['apy_rate'] as num).toDouble(),
        payoutFrequency: (map['payout_frequency'] as String).toLowerCase(),
        nextDate: _dateOnly(map['next_date'] as String),
        autoRenew: _toBool(map['auto_renew']),
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

      final maturityDate = map['maturity_date'] as String?;
      if (maturityDate != null && maturityDate.isNotEmpty) {
        config.maturityDate = _dateOnly(maturityDate);
      }

      final termDays = map['term_days'] as int?;
      if (termDays != null) {
        config.termDays = termDays;
      }

      return await _client.upsertYieldConfig(
        UpsertYieldConfigRequest(config: config),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC upsertYieldConfig error: ${e.message}');
    }
  }

  Future<void> deleteConfig({
    required String id,
    required DateTime deletedAt,
  }) async {
    try {
      await _client.deleteYieldConfig(
        DeleteYieldConfigRequest(
          id: id,
          deletedAt: Timestamp.fromDateTime(deletedAt.toUtc()),
        ),
      );
    } on GrpcError catch (e) {
      throw Exception('gRPC deleteYieldConfig error: ${e.message}');
    }
  }

  static bool _toBool(Object? raw) {
    if (raw == null) return false;
    if (raw is bool) return raw;
    if (raw is int) return raw != 0;
    return raw.toString().toLowerCase() == 'true';
  }

  static String _dateOnly(String value) {
    return value.length >= 10 ? value.substring(0, 10) : value;
  }
}
