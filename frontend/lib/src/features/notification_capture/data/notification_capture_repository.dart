// ============================================================
// NotificationCaptureRepository — orquesta el flujo end-to-end
// ============================================================
//
// Drena las `captured_notifications` en estado `received`, intenta hacer match
// contra los parsers locales y, por cada match, crea una `PendingTransaction`
// con los campos sugeridos:
//   - account_id ← account_card_mappings (si existe mapeo aprendido)
//   - category_id ← transaction_rules (si existe regla aprendida)
//
// Al aprobar (`approve`), persiste la decisión final del usuario:
//   - Si la notificación traía card_last_digits y la cuenta elegida es
//     distinta a la mapeada (o no había), inserta nueva fila en
//     account_card_mappings → próxima notificación con esos dígitos llega
//     pre-asignada.
//   - Si el usuario asignó categoría y no había regla activa para ese
//     comercio, inserta nueva fila en transaction_rules con match_text =
//     primera palabra del merchant → próximas transacciones similares pre-
//     categorizadas.
//
// Toda la persistencia pasa por el outbox para sincronizar entre dispositivos.

import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/account_card_mapping_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/captured_notification_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/parser_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/pending_transaction_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/transaction_rule_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/account_card_mapping.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/pending_transaction.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/transaction_rule.dart';
import 'package:pocket_pilot/src/features/notification_capture/engine/parser_engine.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';

class NotificationCaptureRepository {
  static const _uuid = Uuid();

  final CapturedNotificationLocalStore _captured;
  final PendingTransactionLocalStore _pending;
  final ParserLocalStore _parsers;
  final AccountLocalStore _accounts;
  final AccountCardMappingLocalStore _cardMappings;
  final TransactionRuleLocalStore _rules;
  final TransactionRepository _transactions;
  final SyncOutbox _outbox;
  final ParserEngine _engine;

  NotificationCaptureRepository({
    required CapturedNotificationLocalStore captured,
    required PendingTransactionLocalStore pending,
    required ParserLocalStore parsers,
    required AccountLocalStore accounts,
    required AccountCardMappingLocalStore cardMappings,
    required TransactionRuleLocalStore rules,
    required TransactionRepository transactions,
    required SyncOutbox outbox,
    ParserEngine? engine,
  })  : _captured = captured,
        _pending = pending,
        _parsers = parsers,
        _accounts = accounts,
        _cardMappings = cardMappings,
        _rules = rules,
        _transactions = transactions,
        _outbox = outbox,
        _engine = engine ?? ParserEngine();

  /// Procesa cada notificación pendiente:
  ///   - intenta match con parsers locales
  ///   - resuelve account_id/category_id desde mappings/rules aprendidos
  ///   - si match → crea PendingTransaction y marca status='matched_local'
  ///   - si no match → status='unparseable' (Fase 4 lo eleva al servidor)
  Future<int> processInbox() async {
    final pending = await _captured.listPendingProcessing();
    if (pending.isEmpty) return 0;

    final parsers = await _parsers.listActive();
    if (parsers.isEmpty) return 0;

    int processed = 0;
    for (final notification in pending) {
      ParserMatch? match;
      for (final parser in parsers) {
        match = _engine.tryMatch(notification, parser);
        if (match != null) break;
      }

      if (match == null) {
        await _captured.updateStatus(notification.id, 'unparseable');
        continue;
      }

      final accountId = await _resolveAccount(
        bankId: match.parser.bankId,
        cardLastDigits: match.cardLastDigits,
      );
      final categoryId = match.merchantDescription != null
          ? await _resolveCategory(match.merchantDescription!)
          : null;

      final pendingTx = PendingTransactionModel(
        id: _uuid.v4(),
        capturedNotificationId: notification.id,
        suggestedAccountId: accountId,
        suggestedCategoryId: categoryId,
        amountCents: match.amountCents,
        currencyCode: match.currencyCode,
        merchantDescription: match.merchantDescription,
        cardLastDigits: match.cardLastDigits,
        transactionType: match.transactionType,
        occurredAt: notification.postedAt,
        source: 'parser_local',
        parserId: '${match.parser.bankId}/${match.pattern.id}',
        parserVersion: match.parser.version,
        confidence: 1.0,
        status: 'pending',
        createdAt: DateTime.now().toUtc(),
      );

      await _pending.insert(pendingTx);
      await _captured.updateStatus(
        notification.id,
        'matched_local',
        pendingTxId: pendingTx.id,
      );
      processed++;
    }
    return processed;
  }

  /// Aprueba una sugerencia → crea Transaction real (que sincroniza vía outbox)
  /// y aprende del feedback: persiste mappings y rules implícitamente.
  Future<void> approve({
    required PendingTransactionModel pending,
    required String accountId,
    required String? bankId,
    String? categoryId,
    int? amountCentsOverride,
    String? currencyCodeOverride,
    String? descriptionOverride,
    DateTime? dateOverride,
  }) async {
    final amount = amountCentsOverride ?? pending.amountCents;
    final currency = currencyCodeOverride ?? pending.currencyCode;
    final description = (descriptionOverride ??
            pending.merchantDescription ??
            'Sin descripción')
        .trim();
    final date = (dateOverride ?? pending.occurredAt).toLocal();

    await _transactions.createTransaction(
      id: _uuid.v4(),
      accountId: accountId,
      categoryId: categoryId,
      amountMinor: amount,
      currencyCode: currency,
      description: description,
      date: _formatDate(date),
      type: pending.transactionType,
      status: 'cleared',
      tags: const [],
    );

    await _pending.updateStatus(pending.id, 'approved');
    if (pending.capturedNotificationId != null) {
      await _captured.updateStatus(
        pending.capturedNotificationId!,
        'consumed',
      );
    }

    // Aprendizaje implícito ──────────────────────────────────────────────
    await _learnCardMapping(
      bankId: bankId,
      cardLastDigits: pending.cardLastDigits,
      accountId: accountId,
    );
    await _learnRule(
      merchantDescription: pending.merchantDescription,
      categoryId: categoryId,
    );
  }

  Future<void> dismiss(PendingTransactionModel pending) async {
    await _pending.updateStatus(pending.id, 'dismissed');
    if (pending.capturedNotificationId != null) {
      await _captured.updateStatus(
        pending.capturedNotificationId!,
        'ignored',
      );
    }
  }

  /// Reintenta el match local sobre todas las notificaciones que previamente
  /// quedaron en `unparseable`. Pensado para cuando el parser cambia de
  /// versión (bump server-side) y queremos que el motor actualizado tenga
  /// otra oportunidad. Devuelve cuántas se reabrieron y, de esas, cuántas
  /// produjeron un PendingTransaction nuevo.
  Future<({int reopened, int matched})> reprocessUnparseable() async {
    final reopened = await _captured.resetUnparseableToReceived();
    if (reopened == 0) return (reopened: 0, matched: 0);
    final matched = await processInbox();
    return (reopened: reopened, matched: matched);
  }

  /// Lee la fila activa más reciente de account_card_mappings.
  /// Si hay match único → asigna; si no → null y la UI obliga a elegir.
  Future<String?> _resolveAccount({
    required String bankId,
    String? cardLastDigits,
  }) async {
    if (cardLastDigits == null || cardLastDigits.length != 4) return null;
    final mapping = await _cardMappings.findActiveLatest(
      bankId: bankId,
      lastDigits: cardLastDigits,
    );
    return mapping?.accountId;
  }

  Future<String?> _resolveCategory(String description) async {
    final rule = await _rules.findRuleForDescription(description);
    return rule?.categoryId;
  }

  Future<void> _learnCardMapping({
    required String? bankId,
    required String? cardLastDigits,
    required String accountId,
  }) async {
    if (bankId == null || cardLastDigits == null || cardLastDigits.length != 4) {
      return;
    }
    final existing = await _cardMappings.findActiveLatest(
      bankId: bankId,
      lastDigits: cardLastDigits,
    );
    if (existing != null && existing.accountId == accountId) {
      // Ya conocíamos este mapeo: nada que persistir.
      return;
    }
    final now = DateTime.now().toUtc();
    final mapping = AccountCardMappingModel(
      id: _uuid.v4(),
      bankId: bankId,
      lastDigits: cardLastDigits,
      accountId: accountId,
      createdAt: now,
      updatedAt: now,
    );
    await _cardMappings.upsert(mapping);
    await _outbox.enqueue(
      entityType: 'account_card_mapping',
      entityId: mapping.id,
      operation: 'upsert',
      payload: jsonEncode(mapping.toServerMap()),
    );
  }

  Future<void> _learnRule({
    required String? merchantDescription,
    required String? categoryId,
  }) async {
    if (merchantDescription == null ||
        categoryId == null ||
        merchantDescription.trim().isEmpty) {
      return;
    }

    // Heurística: primera palabra del merchant. Suficientemente específica
    // para "STARBUCKS REFORMA 222" → rule "STARBUCKS" que también matchea
    // "STARBUCKS POLANCO". Si el usuario quiere reglas más finas, las
    // editaremos en una pantalla dedicada en el futuro.
    final firstWord = _firstWord(merchantDescription);
    if (firstWord == null) return;

    final existing = await _rules.findByExactMatchText(firstWord);
    if (existing != null && existing.categoryId == categoryId) {
      return; // ya conocíamos esta regla
    }

    final now = DateTime.now().toUtc();
    final rule = existing == null
        ? TransactionRuleModel(
            id: _uuid.v4(),
            matchText: firstWord,
            categoryId: categoryId,
            priority: 0,
            matchCount: 0,
            createdAt: now,
            updatedAt: now,
          )
        : existing.copyWith(
            categoryId: categoryId,
            updatedAt: now,
          );

    await _rules.upsert(rule);
    await _outbox.enqueue(
      entityType: 'transaction_rule',
      entityId: rule.id,
      operation: 'upsert',
      payload: jsonEncode(rule.toServerMap()),
    );
  }

  /// Lista de cuentas activas para que la UI permita elegir manualmente.
  Future<List<AccountModel>> listAssignableAccounts() async {
    final all = await _accounts.getAccounts();
    return all
        .where((a) => a.type != 'contact' && a.type != 'investment')
        .toList(growable: false);
  }

  String? _firstWord(String text) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return null;
    // Splittea por espacios, comas, puntos: la primera palabra alfanumérica.
    final tokens = cleaned.split(RegExp(r'[\s,.\-]+'));
    for (final t in tokens) {
      final candidate = t.trim();
      if (candidate.length >= 2) return candidate;
    }
    return null;
  }

  String _formatDate(DateTime date) {
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '${date.year}-$m-$d';
  }
}
