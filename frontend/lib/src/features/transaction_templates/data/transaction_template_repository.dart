import 'dart:convert';

import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/transaction_templates/data/transaction_template_local_store.dart';
import 'package:pocket_pilot/src/features/transaction_templates/domain/transaction_template.dart';

class TransactionTemplateRepository {
  final TransactionTemplateLocalStore _local;
  final SyncOutbox _outbox;

  TransactionTemplateRepository({
    required TransactionTemplateLocalStore local,
    required SyncOutbox outbox,
  }) : _local = local,
       _outbox = outbox;

  Future<List<TransactionTemplateModel>> getTemplates() async {
    final rows = await _local.queryRows();
    return rows.map((row) => TransactionTemplateModel.fromMap(row)).toList();
  }

  Future<List<TransactionTemplateModel>> getSchedulableTemplates({
    required String horizonDate,
  }) async {
    final rows = await _local.querySchedulableRows(horizonDate: horizonDate);
    return rows.map((row) => TransactionTemplateModel.fromMap(row)).toList();
  }

  Future<List<TransactionTemplateModel>> getAutoCharges() async {
    final rows = await _local.queryAutoChargeRows();
    return rows.map((row) => TransactionTemplateModel.fromMap(row)).toList();
  }

  Future<void> upsertTemplate(TransactionTemplateModel model) async {
    await _local.upsertRow(model.toMap());
    await _outbox.enqueue(
      entityType: 'transaction_template',
      entityId: model.id,
      operation: 'upsert',
      payload: jsonEncode(model.toServerMap()),
    );
  }

  Future<void> deleteTemplate(String id) async {
    final now = DateTime.now().toUtc();
    await _local.softDelete(id, now);
    await _outbox.enqueue(
      entityType: 'transaction_template',
      entityId: id,
      operation: 'delete',
      payload: jsonEncode({'deleted_at': now.toIso8601String()}),
    );
  }
}
