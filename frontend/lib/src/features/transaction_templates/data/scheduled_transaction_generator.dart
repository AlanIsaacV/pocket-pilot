import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/core/ids/deterministic_namespace.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/transaction_templates/data/transaction_template_repository.dart';
import 'package:pocket_pilot/src/features/transaction_templates/domain/schedule_date_math.dart';
import 'package:pocket_pilot/src/features/transaction_templates/domain/transaction_template.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/core/sync/scheduled_generation_orchestrator.dart';

class GenerationReport {
  final int generatedTransactions;
  final int skippedOccurrences;
  final int reconciledTransfers;

  const GenerationReport({
    required this.generatedTransactions,
    required this.skippedOccurrences,
    required this.reconciledTransfers,
  });
}

abstract class TemplateScheduleStore {
  Future<List<TransactionTemplateModel>> getSchedulableTemplates({
    required String horizonDate,
  });

  Future<void> upsertTemplate(TransactionTemplateModel model);
}

abstract class TransactionOccurrenceStore {
  Future<bool> insertIgnore(Map<String, dynamic> row);

  Future<Map<String, dynamic>?> findById(String id);
}

abstract class OutboxWriter {
  Future<void> enqueueTransactionUpsert(
    String transactionId,
    String payloadJson,
  );
}

abstract class AccountLookup {
  Future<AccountModel?> getActiveById(String id);
}

abstract class CategoryLookup {
  Future<bool> isActiveById(String id);
}

class TemplateScheduleStoreAdapter implements TemplateScheduleStore {
  final TransactionTemplateRepository _repository;

  TemplateScheduleStoreAdapter({
    required TransactionTemplateRepository repository,
  }) : _repository = repository;

  @override
  Future<List<TransactionTemplateModel>> getSchedulableTemplates({
    required String horizonDate,
  }) => _repository.getSchedulableTemplates(horizonDate: horizonDate);

  @override
  Future<void> upsertTemplate(TransactionTemplateModel model) =>
      _repository.upsertTemplate(model);
}

class TransactionOccurrenceStoreAdapter implements TransactionOccurrenceStore {
  final TransactionLocalStore _local;

  TransactionOccurrenceStoreAdapter({required TransactionLocalStore local})
    : _local = local;

  @override
  Future<bool> insertIgnore(Map<String, dynamic> row) =>
      _local.insertRowIgnoreConflict(row);

  @override
  Future<Map<String, dynamic>?> findById(String id) => _local.findRowById(id);
}

class OutboxWriterAdapter implements OutboxWriter {
  final SyncOutbox _outbox;

  OutboxWriterAdapter({required SyncOutbox outbox}) : _outbox = outbox;

  @override
  Future<void> enqueueTransactionUpsert(
    String transactionId,
    String payloadJson,
  ) {
    return _outbox.enqueue(
      entityType: 'transaction',
      entityId: transactionId,
      operation: 'upsert',
      payload: payloadJson,
    );
  }
}

class AccountLookupAdapter implements AccountLookup {
  final AccountLocalStore _local;

  AccountLookupAdapter({required AccountLocalStore local}) : _local = local;

  @override
  Future<AccountModel?> getActiveById(String id) => _local.getById(id);
}

class CategoryLookupAdapter implements CategoryLookup {
  final CategoryLocalStore _local;

  CategoryLookupAdapter({required CategoryLocalStore local}) : _local = local;

  @override
  Future<bool> isActiveById(String id) async {
    final category = await _local.getCategoryById(id);
    return category != null && category.deletedAt == null;
  }
}

class ScheduledTransactionGenerator implements ScheduledGeneratorRunner {
  final TemplateScheduleStore _templates;
  final TransactionOccurrenceStore _transactions;
  final OutboxWriter _outbox;
  final AccountLookup _accounts;
  final CategoryLookup _categories;
  final Duration _horizon;
  final Uuid _uuid;

  ScheduledTransactionGenerator({
    required TemplateScheduleStore templates,
    required TransactionOccurrenceStore transactions,
    required OutboxWriter outbox,
    required AccountLookup accounts,
    required CategoryLookup categories,
    Duration horizon = const Duration(days: 30),
    Uuid? uuid,
  }) : _templates = templates,
       _transactions = transactions,
       _outbox = outbox,
       _accounts = accounts,
       _categories = categories,
       _horizon = horizon,
       _uuid = uuid ?? const Uuid();

  @override
  Future<GenerationReport> run({required DateTime nowUtc}) async {
    final now = nowUtc.toUtc();
    final today = _dateOnly(now);
    final horizonDate = _dateOnly(now.add(_horizon));

    final schedulable = await _templates.getSchedulableTemplates(
      horizonDate: horizonDate,
    );

    var generated = 0;
    var skipped = 0;
    var reconciled = 0;

    for (final template in schedulable) {
      final result = await _processTemplate(
        template: template,
        today: today,
        horizonDate: horizonDate,
      );
      generated += result.generated;
      skipped += result.skipped;
      reconciled += result.reconciled;
    }

    return GenerationReport(
      generatedTransactions: generated,
      skippedOccurrences: skipped,
      reconciledTransfers: reconciled,
    );
  }

  Future<({int generated, int skipped, int reconciled})> _processTemplate({
    required TransactionTemplateModel template,
    required String today,
    required String horizonDate,
  }) async {
    final startCursor = template.nextDate;
    if (startCursor == null) return (generated: 0, skipped: 0, reconciled: 0);

    var cursor = startCursor;
    var generated = 0;
    var skipped = 0;
    var reconciled = 0;
    var ended = false;

    while (_onOrBefore(cursor, horizonDate)) {
      if (_isEnded(template.endDate, cursor)) {
        ended = true;
        break;
      }

      final validation = await _validateAtCursor(template, cursor);
      if (validation == _TemplateValidation.referenceIntegrityError) {
        skipped += 1;
        break;
      }
      if (validation == _TemplateValidation.dataShapeError) {
        skipped += 1;
        cursor = nextScheduleDate(template.frequency!, cursor);
        continue;
      }

      if (template.type == 'transfer_out') {
        final transferResult = await _generateTransferOccurrence(
          template: template,
          date: cursor,
          today: today,
        );
        generated += transferResult.generated;
        reconciled += transferResult.reconciled;
      } else {
        final inserted = await _insertSingleOccurrence(
          template: template,
          date: cursor,
          today: today,
        );
        if (inserted) {
          generated += 1;
        }
      }

      cursor = nextScheduleDate(template.frequency!, cursor);
    }

    final changedCursor = cursor != startCursor;
    if (changedCursor || ended) {
      final updated = _copyWithNextDate(
        template,
        ended ? null : cursor,
        DateTime.now().toUtc(),
      );
      await _templates.upsertTemplate(updated);
    }

    return (generated: generated, skipped: skipped, reconciled: reconciled);
  }

  Future<_TemplateValidation> _validateAtCursor(
    TransactionTemplateModel template,
    String cursorDate,
  ) async {
    if (template.frequency == null || template.frequency!.isEmpty) {
      return _TemplateValidation.dataShapeError;
    }
    if (template.amountCents == null) {
      return _TemplateValidation.dataShapeError;
    }
    if (!_isSupportedType(template.type)) {
      return _TemplateValidation.dataShapeError;
    }

    final fromAccount = await _accounts.getActiveById(template.accountId);
    if (fromAccount == null) {
      return _TemplateValidation.referenceIntegrityError;
    }

    if (template.categoryId != null) {
      final categoryOk = await _categories.isActiveById(template.categoryId!);
      if (!categoryOk) {
        return _TemplateValidation.referenceIntegrityError;
      }
    }

    if (template.type == 'transfer_out') {
      final toAccountId = template.toAccountId;
      if (toAccountId == null || toAccountId.isEmpty) {
        return _TemplateValidation.referenceIntegrityError;
      }
      if (toAccountId == template.accountId) {
        return _TemplateValidation.referenceIntegrityError;
      }

      final toAccount = await _accounts.getActiveById(toAccountId);
      if (toAccount == null) {
        return _TemplateValidation.referenceIntegrityError;
      }

      final templateCurrency = template.currencyCode;
      if (fromAccount.currencyCode != templateCurrency ||
          toAccount.currencyCode != templateCurrency) {
        return _TemplateValidation.referenceIntegrityError;
      }
    }

    if (!_isIsoDate(cursorDate)) {
      return _TemplateValidation.dataShapeError;
    }

    return _TemplateValidation.valid;
  }

  Future<bool> _insertSingleOccurrence({
    required TransactionTemplateModel template,
    required String date,
    required String today,
  }) async {
    final transactionId = _uuid.v5(
      kDeterministicTemplateNamespace,
      '${template.id}-$date',
    );
    final status = _statusForDate(date: date, today: today);
    final nowIso = DateTime.now().toUtc().toIso8601String();

    final row = <String, dynamic>{
      'id': transactionId,
      'account_id': template.accountId,
      'category_id': template.categoryId,
      'linked_transaction_id': null,
      'template_id': template.id,
      'type': template.type,
      'amount_cents': template.amountCents!,
      'currency_code': template.currencyCode,
      'status': status,
      'tags': jsonEncode(template.tags),
      'description': template.description,
      'date': date,
      'created_at': nowIso,
      'updated_at': nowIso,
      'deleted_at': null,
    };

    final inserted = await _transactions.insertIgnore(row);
    if (inserted) {
      await _outbox.enqueueTransactionUpsert(transactionId, jsonEncode(row));
    }
    return inserted;
  }

  Future<({int generated, int reconciled})> _generateTransferOccurrence({
    required TransactionTemplateModel template,
    required String date,
    required String today,
  }) async {
    final outId = _uuid.v5(
      kDeterministicTemplateNamespace,
      '${template.id}-$date-out',
    );
    final inId = _uuid.v5(
      kDeterministicTemplateNamespace,
      '${template.id}-$date-in',
    );

    final existingOut = await _transactions.findById(outId);
    final existingIn = await _transactions.findById(inId);

    if (existingOut != null && existingIn != null) {
      return (generated: 0, reconciled: 0);
    }

    if (existingOut != null && !_hasExpectedLink(existingOut, inId)) {
      return (generated: 0, reconciled: 0);
    }
    if (existingIn != null && !_hasExpectedLink(existingIn, outId)) {
      return (generated: 0, reconciled: 0);
    }

    final status = _statusForDate(date: date, today: today);
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final common = <String, dynamic>{
      'category_id': null,
      'template_id': template.id,
      'amount_cents': template.amountCents!,
      'currency_code': template.currencyCode,
      'status': status,
      'tags': jsonEncode(template.tags),
      'description': template.description,
      'date': date,
      'created_at': nowIso,
      'updated_at': nowIso,
      'deleted_at': null,
    };

    var generated = 0;
    var reconciled = 0;

    if (existingOut == null) {
      final outRow = <String, dynamic>{
        ...common,
        'id': outId,
        'account_id': template.accountId,
        'linked_transaction_id': inId,
        'type': 'transfer_out',
      };
      final inserted = await _transactions.insertIgnore(outRow);
      if (inserted) {
        generated += 1;
        await _outbox.enqueueTransactionUpsert(outId, jsonEncode(outRow));
      }
    }

    if (existingIn == null) {
      final inRow = <String, dynamic>{
        ...common,
        'id': inId,
        'account_id': template.toAccountId!,
        'linked_transaction_id': outId,
        'type': 'transfer_in',
      };
      final inserted = await _transactions.insertIgnore(inRow);
      if (inserted) {
        generated += 1;
        await _outbox.enqueueTransactionUpsert(inId, jsonEncode(inRow));
      }
    }

    if ((existingOut == null) != (existingIn == null) && generated > 0) {
      reconciled = 1;
    }

    return (generated: generated, reconciled: reconciled);
  }

  static bool _hasExpectedLink(Map<String, dynamic> row, String expectedId) {
    return row['linked_transaction_id'] == expectedId;
  }

  static bool _isSupportedType(String type) {
    return type == 'income' || type == 'expense' || type == 'transfer_out';
  }

  static bool _isIsoDate(String value) {
    if (value.length != 10) return false;
    try {
      DateTime.parse(value);
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _isEnded(String? endDate, String cursorDate) {
    if (endDate == null || endDate.isEmpty) return false;
    return cursorDate.compareTo(endDate) > 0;
  }

  static bool _onOrBefore(String a, String b) => a.compareTo(b) <= 0;

  static String _dateOnly(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _statusForDate({required String date, required String today}) {
    return date.compareTo(today) <= 0 ? 'cleared' : 'pending';
  }

  static TransactionTemplateModel _copyWithNextDate(
    TransactionTemplateModel base,
    String? nextDate,
    DateTime updatedAt,
  ) {
    return TransactionTemplateModel(
      id: base.id,
      name: base.name,
      accountId: base.accountId,
      toAccountId: base.toAccountId,
      categoryId: base.categoryId,
      type: base.type,
      amountCents: base.amountCents,
      currencyCode: base.currencyCode,
      tags: base.tags,
      description: base.description,
      frequency: base.frequency,
      nextDate: nextDate,
      endDate: base.endDate,
      createdAt: base.createdAt,
      updatedAt: updatedAt,
      deletedAt: base.deletedAt,
    );
  }
}

enum _TemplateValidation { valid, dataShapeError, referenceIntegrityError }
