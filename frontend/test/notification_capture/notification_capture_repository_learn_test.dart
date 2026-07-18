// Tests de aprendizaje implícito de NotificationCaptureRepository:
//
//   1. Resolución de cuenta por (bank_id, pattern_id) para notificaciones sin
//      dígitos de tarjeta (ej. BBVA "COMPRA TDC"): sin mapeo previo la
//      sugerencia llega sin account_id; tras una aprobación, la siguiente
//      notificación del mismo patrón llega pre-asignada.
//   2. Longest-prefix rule learning: "DIDI" y "DIDI FOOD" coexisten como
//      reglas separadas en lugar de sobrescribirse.
//
// Todos los stores se fake-ean en memoria (mismo patrón que
// transaction_repository_confirm_test.dart) para no depender de sqflite.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/account_card_mapping_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/captured_notification_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/notification_capture_repository.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/parser_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/pending_transaction_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/transaction_rule_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/account_card_mapping.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/captured_notification.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/notification_parser.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/pending_transaction.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/transaction_rule.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NotificationParserDefinition bbva;

  setUpAll(() async {
    final raw = await rootBundle.loadString('assets/parsers/bbva_mx.json');
    bbva = NotificationParserDefinition.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  });

  NotificationCaptureRepository buildRepository({
    required FakeCapturedNotificationLocalStore captured,
    required FakePendingTransactionLocalStore pending,
    required FakeAccountCardMappingLocalStore cardMappings,
    required FakeTransactionRuleLocalStore rules,
  }) {
    return NotificationCaptureRepository(
      captured: captured,
      pending: pending,
      parsers: FakeParserLocalStore([bbva]),
      accounts: AccountLocalStore(db: DatabaseHelper()),
      cardMappings: cardMappings,
      rules: rules,
      transactions: TransactionRepository(
        local: FakeTransactionLocalStore(),
        outbox: FakeSyncOutbox(),
      ),
      outbox: FakeSyncOutbox(),
    );
  }

  CapturedNotificationModel tdcNotification({
    required String id,
    required String text,
    required DateTime postedAt,
  }) {
    return CapturedNotificationModel(
      id: id,
      packageName: 'com.bancomer.mbanking',
      title: 'Compra con TDC',
      text: text,
      postedAt: postedAt,
      status: 'received',
      createdAt: postedAt,
    );
  }

  group('digit-less TDC resolution + learn-on-approval', () {
    test(
      'first "COMPRA TDC" (no digits) yields no account; after approval the '
      'next one resolves to the approved account',
      () async {
        final captured = FakeCapturedNotificationLocalStore();
        final pending = FakePendingTransactionLocalStore();
        final cardMappings = FakeAccountCardMappingLocalStore();
        final repo = buildRepository(
          captured: captured,
          pending: pending,
          cardMappings: cardMappings,
          rules: FakeTransactionRuleLocalStore(),
        );

        captured.seed(
          tdcNotification(
            id: 'n1',
            text: 'COMPRA TDC EN PAGOMITELMEXCOMSI \$578.00 24 abril 18:24h',
            postedAt: DateTime.utc(2026, 4, 25, 0, 24, 48),
          ),
        );

        expect(await repo.processInbox(), 1);
        final firstPendingTx = pending.byId.values.single;
        expect(firstPendingTx.cardLastDigits, isNull);
        expect(firstPendingTx.parserId, 'bbva_mx/purchase_tdc');
        expect(
          firstPendingTx.suggestedAccountId,
          isNull,
          reason: 'no pattern mapping learned yet',
        );

        await repo.approve(
          pending: firstPendingTx,
          accountId: 'acc-credit',
          bankId: 'bbva_mx',
        );

        final learned = cardMappings.mappings.single;
        expect(learned.bankId, 'bbva_mx');
        expect(learned.patternId, 'purchase_tdc');
        expect(learned.lastDigits, isNull);
        expect(learned.accountId, 'acc-credit');

        // Segunda notificación TDC sin dígitos, mismo patrón.
        captured.seed(
          tdcNotification(
            id: 'n2',
            text: 'COMPRA TDC EN MACCHINA SUC PUER \$85.00 24 abril 12:07h',
            postedAt: DateTime.utc(2026, 4, 24, 18, 8, 20),
          ),
        );

        expect(await repo.processInbox(), 1);
        final secondPendingTx = pending.byId.values.firstWhere(
          (tx) => tx.id != firstPendingTx.id,
        );
        expect(secondPendingTx.suggestedAccountId, 'acc-credit');
      },
    );
  });

  group('longest-prefix rule learning', () {
    test(
      'DIDI and DIDI FOOD coexist as separate rules after approvals',
      () async {
        final rules = FakeTransactionRuleLocalStore();
        final repo = buildRepository(
          captured: FakeCapturedNotificationLocalStore(),
          pending: FakePendingTransactionLocalStore(),
          cardMappings: FakeAccountCardMappingLocalStore(),
          rules: rules,
        );

        PendingTransactionModel makePending(String description) {
          final now = DateTime.now().toUtc();
          return PendingTransactionModel(
            id: 'tx-$description',
            amountCents: 10000,
            currencyCode: 'MXN',
            merchantDescription: description,
            transactionType: 'expense',
            occurredAt: now,
            source: 'parser_local',
            status: 'pending',
            createdAt: now,
          );
        }

        // 1. "DIDI VIAJE" → Transporte: aprende la regla "DIDI".
        await repo.approve(
          pending: makePending('DIDI VIAJE'),
          accountId: 'acc-1',
          bankId: null,
          categoryId: 'transporte',
        );
        expect((await rules.findByExactMatchText('DIDI'))?.categoryId,
            'transporte');

        // 2. "DIDI FOOD MX" → Comida: "DIDI" ya apunta a otra categoría, así
        //    que aprende el prefijo de dos palabras en vez de sobrescribir.
        await repo.approve(
          pending: makePending('DIDI FOOD MX'),
          accountId: 'acc-1',
          bankId: null,
          categoryId: 'comida',
        );
        expect(
          (await rules.findByExactMatchText('DIDI'))?.categoryId,
          'transporte',
          reason: 'la regla original de DIDI no debe sobrescribirse',
        );
        expect(
          (await rules.findByExactMatchText('DIDI FOOD'))?.categoryId,
          'comida',
        );

        // 3. Resolución: coincidencia más larga gana.
        expect(
          (await rules.findRuleForDescription('DIDI FOOD MONTERREY'))
              ?.categoryId,
          'comida',
        );
        expect(
          (await rules.findRuleForDescription('DIDI VIAJE'))?.categoryId,
          'transporte',
        );
      },
    );
  });
}

// ── Fakes ────────────────────────────────────────────────────────────────

class FakeParserLocalStore extends ParserLocalStore {
  FakeParserLocalStore(this._parsers) : super(db: DatabaseHelper());
  final List<NotificationParserDefinition> _parsers;

  @override
  Future<List<NotificationParserDefinition>> listActive() async => _parsers;
}

class FakeCapturedNotificationLocalStore extends CapturedNotificationLocalStore {
  FakeCapturedNotificationLocalStore() : super(db: DatabaseHelper());
  final Map<String, CapturedNotificationModel> _byId = {};

  void seed(CapturedNotificationModel model) => _byId[model.id] = model;

  @override
  Future<List<CapturedNotificationModel>> listPendingProcessing({
    int limit = 200,
  }) async {
    return _byId.values.where((n) => n.status == 'received').toList();
  }

  @override
  Future<void> updateStatus(
    String id,
    String status, {
    String? pendingTxId,
    int? matchedParserVersion,
    String? matchedPatternId,
    String? extractionMethod,
  }) async {
    final current = _byId[id];
    if (current == null) return;
    _byId[id] = CapturedNotificationModel(
      id: current.id,
      packageName: current.packageName,
      title: current.title,
      text: current.text,
      bigText: current.bigText,
      postedAt: current.postedAt,
      status: status,
      pendingTxId: pendingTxId ?? current.pendingTxId,
      createdAt: current.createdAt,
    );
  }
}

class FakePendingTransactionLocalStore extends PendingTransactionLocalStore {
  FakePendingTransactionLocalStore() : super(db: DatabaseHelper());
  final Map<String, PendingTransactionModel> byId = {};

  @override
  Future<void> insert(PendingTransactionModel model) async {
    byId[model.id] = model;
  }

  @override
  Future<void> updateStatus(String id, String status) async {
    final current = byId[id];
    if (current != null) {
      byId[id] = current.copyWith(status: status);
    }
  }
}

class FakeAccountCardMappingLocalStore extends AccountCardMappingLocalStore {
  FakeAccountCardMappingLocalStore() : super(db: DatabaseHelper());
  final List<AccountCardMappingModel> mappings = [];

  @override
  Future<AccountCardMappingModel?> findActiveLatest({
    required String bankId,
    required String lastDigits,
  }) async {
    final candidates = mappings
        .where((m) =>
            m.bankId == bankId && m.lastDigits == lastDigits && m.isActive)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return candidates.isEmpty ? null : candidates.first;
  }

  @override
  Future<AccountCardMappingModel?> findByBankAndPattern({
    required String bankId,
    required String patternId,
  }) async {
    final candidates = mappings
        .where((m) =>
            m.bankId == bankId && m.patternId == patternId && m.isActive)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return candidates.isEmpty ? null : candidates.first;
  }

  @override
  Future<void> upsert(AccountCardMappingModel model) async {
    mappings.add(model);
  }
}

class FakeTransactionRuleLocalStore extends TransactionRuleLocalStore {
  FakeTransactionRuleLocalStore() : super(db: DatabaseHelper());
  final List<TransactionRuleModel> rules = [];

  @override
  Future<TransactionRuleModel?> findRuleForDescription(
    String description,
  ) async {
    if (description.trim().isEmpty) return null;
    final lowerDesc = description.toLowerCase();
    final candidates = rules
        .where((r) =>
            r.deletedAt == null && lowerDesc.contains(r.matchText.toLowerCase()))
        .toList()
      ..sort((a, b) {
        final byLength = b.matchText.length.compareTo(a.matchText.length);
        if (byLength != 0) return byLength;
        final byPriority = b.priority.compareTo(a.priority);
        if (byPriority != 0) return byPriority;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    return candidates.isEmpty ? null : candidates.first;
  }

  @override
  Future<TransactionRuleModel?> findByExactMatchText(String matchText) async {
    final matches = rules
        .where((r) =>
            r.deletedAt == null &&
            r.matchText.toLowerCase() == matchText.toLowerCase())
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<void> upsert(TransactionRuleModel model) async {
    rules.removeWhere((r) => r.id == model.id);
    rules.add(model);
  }
}

class FakeTransactionLocalStore extends TransactionLocalStore {
  FakeTransactionLocalStore() : super(db: DatabaseHelper());

  @override
  Future<void> upsertRow(Map<String, dynamic> row) async {
    // No-op: approve() solo necesita que esto no toque sqflite.
  }
}

class FakeSyncOutbox extends SyncOutbox {
  FakeSyncOutbox() : super(db: DatabaseHelper());
  final List<String> payloads = [];

  @override
  Future<void> enqueue({
    required String entityType,
    required String entityId,
    required String operation,
    required String payload,
  }) async {
    payloads.add(payload);
  }
}
