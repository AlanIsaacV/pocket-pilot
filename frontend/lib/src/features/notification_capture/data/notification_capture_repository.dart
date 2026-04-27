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
import 'dart:developer' as developer;

import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/account_card_mapping_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/bank_alias_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/bank_package_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/captured_notification_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/notification_capture_preferences.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/parser_feedback_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/parser_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/parser_remote_service.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/pending_transaction_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/transaction_rule_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/account_card_mapping.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/parser_feedback.dart';
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
  final ParserFeedbackLocalStore? _feedback;
  final BankAliasLocalStore? _bankAliases;
  final BankPackageLocalStore? _bankPackages;
  final TransactionRepository _transactions;
  final SyncOutbox _outbox;
  final ParserEngine _engine;
  final ParserRemoteService? _parserRemote;
  final NotificationCapturePreferences? _preferences;

  NotificationCaptureRepository({
    required CapturedNotificationLocalStore captured,
    required PendingTransactionLocalStore pending,
    required ParserLocalStore parsers,
    required AccountLocalStore accounts,
    required AccountCardMappingLocalStore cardMappings,
    required TransactionRuleLocalStore rules,
    required TransactionRepository transactions,
    required SyncOutbox outbox,
    ParserFeedbackLocalStore? feedback,
    BankAliasLocalStore? bankAliases,
    BankPackageLocalStore? bankPackages,
    ParserEngine? engine,
    ParserRemoteService? parserRemote,
    NotificationCapturePreferences? preferences,
  })  : _captured = captured,
        _pending = pending,
        _parsers = parsers,
        _accounts = accounts,
        _cardMappings = cardMappings,
        _rules = rules,
        _feedback = feedback,
        _bankAliases = bankAliases,
        _bankPackages = bankPackages,
        _transactions = transactions,
        _outbox = outbox,
        _engine = engine ?? ParserEngine(),
        _parserRemote = parserRemote,
        _preferences = preferences;

  /// Procesa cada notificación pendiente:
  ///   - intenta match con parsers locales
  ///   - si toggle ON, fallback al LLM server-side (Fase 4)
  ///   - resuelve account_id/category_id desde mappings/rules aprendidos
  ///   - persiste extraction_method/parser_version/pattern_id para trazabilidad
  Future<int> processInbox() async {
    final pending = await _captured.listPendingProcessing();
    if (pending.isEmpty) return 0;

    final parsers = await _parsers.listActive();

    // Lee el toggle UNA vez por batch para evitar I/O por noti.
    bool llmEnabled = false;
    bool helpImprove = true;
    final preferences = _preferences;
    if (_parserRemote != null && preferences != null) {
      llmEnabled = await preferences.shareWithLlmForParser();
      helpImprove = await preferences.helpImproveApp();
    }

    int processed = 0;
    bool quotaExhausted = false;

    for (final notification in pending) {
      // 1. Match local primero. Si lo hay, gana sin tocar la red.
      ParserMatch? match;
      for (final parser in parsers) {
        match = _engine.tryMatch(notification, parser);
        if (match != null) break;
      }

      if (match != null) {
        final pendingTx = await _createPendingFromLocalMatch(notification, match);
        await _captured.updateStatus(
          notification.id,
          'matched_local',
          pendingTxId: pendingTx.id,
          matchedParserVersion: match.parser.version,
          matchedPatternId: match.pattern.id,
          extractionMethod: 'local',
        );
        processed++;
        continue;
      }

      // 2. Fallback al LLM si el toggle está ON y no hemos topado cuota
      // en este batch (evitamos N llamadas perdedoras).
      if (llmEnabled && !quotaExhausted) {
        final llmPending = await _tryLlmFallback(notification, helpImprove);
        if (llmPending == _LlmOutcome.matched) {
          processed++;
          continue;
        }
        if (llmPending == _LlmOutcome.quotaExceeded) {
          quotaExhausted = true;
        }
      }

      // 3. Sin match local ni LLM → unparseable.
      await _captured.updateStatus(notification.id, 'unparseable');
    }
    return processed;
  }

  Future<PendingTransactionModel> _createPendingFromLocalMatch(
    dynamic notification,
    ParserMatch match,
  ) async {
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
    return pendingTx;
  }

  Future<_LlmOutcome> _tryLlmFallback(
    dynamic notification,
    bool helpImprove,
  ) async {
    final remote = _parserRemote;
    if (remote == null) return _LlmOutcome.skipped;

    try {
      final outcome = await remote.parseNotification(
        packageName: notification.packageName as String,
        title: (notification.title as String?) ?? '',
        text: (notification.text as String?) ?? '',
        bigText: (notification.bigText as String?) ?? '',
        helpImproveApp: helpImprove,
      );

      if (!outcome.matched) {
        // El LLM tampoco la reconoció: tratar como unparseable.
        return _LlmOutcome.notMatched;
      }

      // El LLM no resuelve account ni category — los buscamos con la misma
      // lógica que para parsers locales (mappings y rules aprendidas).
      final bankId =
          await _bankIdForPackage(notification.packageName as String);
      final accountId = outcome.cardLastDigits.isNotEmpty
          ? await _resolveAccount(
              bankId: bankId,
              cardLastDigits: outcome.cardLastDigits,
            )
          : null;
      final categoryId = outcome.merchantDescription.isNotEmpty
          ? await _resolveCategory(outcome.merchantDescription)
          : null;

      final pendingTx = PendingTransactionModel(
        id: _uuid.v4(),
        capturedNotificationId: notification.id,
        suggestedAccountId: accountId,
        suggestedCategoryId: categoryId,
        amountCents: outcome.amountCents,
        currencyCode: outcome.currencyCode,
        merchantDescription: outcome.merchantDescription.isEmpty
            ? null
            : outcome.merchantDescription,
        cardLastDigits: outcome.cardLastDigits.isEmpty
            ? null
            : outcome.cardLastDigits,
        transactionType: outcome.transactionType,
        occurredAt: notification.postedAt,
        source: 'parser_llm',
        parserId: outcome.proposedPatternId.isEmpty
            ? null
            : 'llm/${outcome.proposedPatternId}',
        parserVersion: null,
        confidence: 0.7,
        status: 'pending',
        createdAt: DateTime.now().toUtc(),
      );

      await _pending.insert(pendingTx);
      await _captured.updateStatus(
        notification.id,
        'llm_used',
        pendingTxId: pendingTx.id,
        matchedPatternId: outcome.proposedPatternId.isEmpty
            ? null
            : outcome.proposedPatternId,
        extractionMethod: 'llm',
      );
      return _LlmOutcome.matched;
    } on ParserQuotaExceededException catch (e) {
      developer.log('LLM quota exceeded: ${e.message}',
          name: 'NotificationCapture');
      return _LlmOutcome.quotaExceeded;
    } catch (e, st) {
      // Red, 5xx, parsing — no bloquea el inbox. La noti queda unparseable
      // y el botón "Reintentar no parseables" volverá a intentar.
      developer.log('LLM fallback failed: $e',
          name: 'NotificationCapture', error: e, stackTrace: st);
      return _LlmOutcome.error;
    }
  }

  /// Resolución package_name → bank_id (Fase 8): consulta primero el alias
  /// per-user (si el usuario lo asignó manualmente al marcar el package
  /// como banco) y, si no, el catálogo global pull-only. Fallback
  /// 'unknown' si el package no está en ninguna tabla — el lookup de
  /// account_card_mappings fallará en silencio (no se preasigna cuenta,
  /// el usuario elige).
  ///
  /// Antes de Fase 8 era un switch hardcoded para BBVA; ahora la lista de
  /// bancos crece sin redeploy gracias al loop comunitario (admin promueve
  /// `package_suggestions` → `bank_packages`).
  Future<String> _bankIdForPackage(String packageName) async {
    final aliases = _bankAliases;
    if (aliases != null) {
      final alias = await aliases.getByPackageName(packageName);
      final aliasBankId = alias?.bankId;
      if (aliasBankId != null && aliasBankId.isNotEmpty) {
        return aliasBankId;
      }
    }
    final packages = _bankPackages;
    if (packages != null) {
      final pkg = await packages.getByPackageName(packageName);
      if (pkg != null) {
        return pkg.bankId;
      }
    }
    return 'unknown';
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
    bool? wasHelpful,
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

    // Señal de calidad ───────────────────────────────────────────────────
    await _persistFeedback(
      pending: pending,
      wasDismissed: false,
      wasHelpful: wasHelpful,
      finalAccountId: accountId,
      finalCategoryId: categoryId,
      finalAmountCents: amount,
      finalDescription: description,
    );
  }

  Future<void> dismiss(
    PendingTransactionModel pending, {
    bool? wasHelpful,
  }) async {
    await _pending.updateStatus(pending.id, 'dismissed');
    if (pending.capturedNotificationId != null) {
      await _captured.updateStatus(
        pending.capturedNotificationId!,
        'ignored',
      );
    }
    await _persistFeedback(
      pending: pending,
      wasDismissed: true,
      wasHelpful: wasHelpful,
    );
  }

  /// Persiste señal de calidad sobre la sugerencia. Push-only vía outbox; el
  /// store local se mantiene para idempotencia y para el conflict resolution
  /// cuando el server gana en LWW.
  ///
  /// Cuando [wasDismissed] es true, todos los `*_changed` se setean a false
  /// porque no hay "final" con qué comparar (el usuario simplemente descartó).
  Future<void> _persistFeedback({
    required PendingTransactionModel pending,
    required bool wasDismissed,
    bool? wasHelpful,
    String? finalAccountId,
    String? finalCategoryId,
    int? finalAmountCents,
    String? finalDescription,
  }) async {
    final feedback = _feedback;
    if (feedback == null) return; // legacy/test sin DI

    final (bankId, patternId) =
        PendingTransactionModel.splitParserId(pending.parserId);
    final extractionMethod = switch (pending.source) {
      'parser_local' => 'local',
      'llm' || 'parser_llm' => 'llm',
      _ => null,
    };

    final accountChanged = wasDismissed
        ? false
        : (finalAccountId != pending.suggestedAccountId);
    final categoryChanged = wasDismissed
        ? false
        : (finalCategoryId != pending.suggestedCategoryId);
    final amountChanged = wasDismissed
        ? false
        : (finalAmountCents != null && finalAmountCents != pending.amountCents);
    final descriptionChanged = wasDismissed
        ? false
        : _descriptionChanged(pending.merchantDescription, finalDescription);

    final now = DateTime.now().toUtc();
    final model = ParserFeedbackModel(
      id: _uuid.v4(),
      pendingTransactionId: pending.id,
      capturedNotificationId: pending.capturedNotificationId,
      bankId: bankId,
      patternId: patternId,
      parserVersion: pending.parserVersion,
      extractionMethod: extractionMethod,
      wasHelpful: wasHelpful,
      accountChanged: accountChanged,
      categoryChanged: categoryChanged,
      amountChanged: amountChanged,
      descriptionChanged: descriptionChanged,
      wasDismissed: wasDismissed,
      createdAt: now,
      updatedAt: now,
    );

    await feedback.upsert(model);
    await _outbox.enqueue(
      entityType: 'parser_feedback',
      entityId: model.id,
      operation: 'upsert',
      payload: jsonEncode(model.toServerMap()),
    );
  }

  /// Comparación de descriptions tolerante a diferencias triviales: trim +
  /// lowercase + colapso de whitespace. BBVA emite descriptions con trailing
  /// spaces y casing inconsistente; el usuario que solo limpie espacios no
  /// debería disparar `description_changed`.
  bool _descriptionChanged(String? suggested, String? finalText) {
    String norm(String? s) =>
        (s ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return norm(suggested) != norm(finalText);
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

enum _LlmOutcome {
  matched,        // PendingTransaction creada — seguir al siguiente
  notMatched,     // LLM dijo "no es transacción" → unparseable
  quotaExceeded,  // cuota agotada — abortar el resto del batch
  error,          // red/5xx/parse → unparseable, log
  skipped,        // dependencias no inyectadas (tests/legacy callers)
}
