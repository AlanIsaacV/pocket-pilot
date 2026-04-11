import 'package:fixnum/fixnum.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/generated/pocket_pilot/v1/transaction_template_service.pbgrpc.dart';

class TransactionTemplateRemoteService {
  late final TransactionTemplateServiceClient _client;

  TransactionTemplateRemoteService() {
    _client = TransactionTemplateServiceClient(
      GrpcClient.channel,
      interceptors: GrpcClient.interceptors,
    );
  }

  Future<ListTransactionTemplatesResponse> listTemplates({
    DateTime? updatedSince,
  }) async {
    final request = ListTransactionTemplatesRequest();
    if (updatedSince != null) {
      request.updatedSince = Timestamp.fromDateTime(updatedSince.toUtc());
    }
    return _client.listTransactionTemplates(request);
  }

  Future<UpsertTransactionTemplateResponse> upsertTemplate(
    Map<String, dynamic> map,
  ) async {
    final now = DateTime.now().toUtc();
    final template = TransactionTemplate(
      id: map['id'] as String,
      name: map['name'] as String,
      accountId: map['account_id'] as String,
      type: map['type'] as String,
      nature: CategoryModel.stringToFinancialNature(
          map['nature'] as String? ?? ''),
      currencyCode: map['currency_code'] as String,
      description: map['description'] as String? ?? '',
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
      tags: _toTags(map['tags']),
    );

    final amountCents = map['amount_cents'] as int?;
    if (amountCents != null) {
      template.amountCents = Int64(amountCents);
    }

    final categoryId = map['category_id'] as String?;
    if (categoryId != null && categoryId.isNotEmpty) {
      template.categoryId = categoryId;
    }

    final toAccountId = map['to_account_id'] as String?;
    if (toAccountId != null && toAccountId.isNotEmpty) {
      template.toAccountId = toAccountId;
    }

    final frequency = map['frequency'] as String?;
    if (frequency != null && frequency.isNotEmpty) {
      template.frequency = frequency;
    }

    final nextDate = map['next_date'] as String?;
    if (nextDate != null && nextDate.isNotEmpty) {
      template.nextDate = _dateOnly(nextDate);
    }

    final endDate = map['end_date'] as String?;
    if (endDate != null && endDate.isNotEmpty) {
      template.endDate = _dateOnly(endDate);
    }

    return _client.upsertTransactionTemplate(
      UpsertTransactionTemplateRequest(template: template),
    );
  }

  Future<void> deleteTemplate({
    required String id,
    required DateTime deletedAt,
  }) async {
    await _client.deleteTransactionTemplate(
      DeleteTransactionTemplateRequest(
        id: id,
        deletedAt: Timestamp.fromDateTime(deletedAt.toUtc()),
      ),
    );
  }

  static List<String> _toTags(Object? raw) {
    if (raw == null) return const <String>[];
    if (raw is List) {
      return raw.map((e) => e.toString()).toList(growable: false);
    }
    return const <String>[];
  }

  static String _dateOnly(String value) {
    return value.length >= 10 ? value.substring(0, 10) : value;
  }
}
