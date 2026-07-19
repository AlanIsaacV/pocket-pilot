import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/account_card_mapping_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/captured_notification_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/notification_capture_preferences.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/notification_capture_repository.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/parser_feedback_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/parser_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/parser_remote_service.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/pending_transaction_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/transaction_rule_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/background/background_capture_runner.dart';
import 'package:pocket_pilot/src/features/notification_capture/notifications/capture_notification_service.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/account_card_mapping.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/captured_notification.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/notification_parser.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/parser_feedback.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/pending_transaction.dart';
import 'package:pocket_pilot/src/features/notification_capture/domain/transaction_rule.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';

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
    required _FakeCapturedStore captured,
    required _FakePendingStore pending,
    required _FakeCardMappingStore mappings,
    required _FakeRuleStore rules,
    required _FakeTransactionStore transactions,
    required _FakeFeedbackStore feedback,
    required bool autoConfirmEnabled,
    bool shareWithLlm = false,
    ParserRemoteService? parserRemote,
  }) {
    return NotificationCaptureRepository(
      captured: captured,
      pending: pending,
      parsers: _FakeParserStore([bbva]),
      accounts: AccountLocalStore(db: DatabaseHelper()),
      cardMappings: mappings,
      rules: rules,
      feedback: feedback,
      transactions: TransactionRepository(
        local: transactions,
        outbox: _FakeOutbox(),
      ),
      outbox: _FakeOutbox(),
      parserRemote: parserRemote,
      preferences: _FakePreferences(
        autoConfirmEnabledValue: autoConfirmEnabled,
        shareWithLlm: shareWithLlm,
      ),
    );
  }

  CapturedNotificationModel localNotification() {
    final now = DateTime.utc(2026, 7, 18, 12);
    return CapturedNotificationModel(
      id: 'captured-local',
      packageName: 'com.bancomer.mbanking',
      title: 'Compra con TDC',
      text: 'COMPRA TDC EN PAGOMITELMEXCOMSI \$578.00 24 abril 18:24h',
      postedAt: now,
      status: 'received',
      createdAt: now,
    );
  }

  void seedResolvedLocalMatch({
    required _FakeCapturedStore captured,
    required _FakeCardMappingStore mappings,
    required _FakeRuleStore rules,
  }) {
    final now = DateTime.utc(2026, 7, 18);
    captured.seed(localNotification());
    mappings.models.add(
      AccountCardMappingModel(
        id: 'known-pattern-mapping',
        bankId: 'bbva_mx',
        patternId: 'purchase_tdc',
        accountId: 'account-1',
        createdAt: now,
        updatedAt: now,
      ),
    );
    rules.models.add(
      TransactionRuleModel(
        id: 'known-merchant-rule',
        matchText: 'PAGOMITELMEXCOMSI',
        categoryId: 'category-services',
        priority: 0,
        matchCount: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  test('auto-confirms an unambiguous local match without learning', () async {
    final captured = _FakeCapturedStore();
    final pending = _FakePendingStore();
    final mappings = _FakeCardMappingStore();
    final rules = _FakeRuleStore();
    final transactions = _FakeTransactionStore();
    final feedback = _FakeFeedbackStore();
    seedResolvedLocalMatch(
      captured: captured,
      mappings: mappings,
      rules: rules,
    );

    final repository = buildRepository(
      captured: captured,
      pending: pending,
      mappings: mappings,
      rules: rules,
      transactions: transactions,
      feedback: feedback,
      autoConfirmEnabled: true,
    );

    final result = await BackgroundCaptureRunner.withRepository(
      repository,
    ).run();
    expect(result.autoConfirmed, 1);
    expect(result.leftPending, 0);

    expect(transactions.created, hasLength(1));
    expect(transactions.created.single['source'], 'auto_notification');
    final suggestion = pending.byId.values.single;
    expect(suggestion.status, 'approved');
    expect(await pending.listPending(), isEmpty);
    expect(captured.byId['captured-local']!.status, 'consumed');
    expect(feedback.models, hasLength(1));
    final signal = feedback.models.single;
    expect(signal.wasHelpful, isNull);
    expect(signal.accountChanged, isFalse);
    expect(signal.categoryChanged, isFalse);
    expect(signal.amountChanged, isFalse);
    expect(signal.descriptionChanged, isFalse);
    expect(signal.wasDismissed, isFalse);
    expect(mappings.models, hasLength(1));
    expect(rules.models, hasLength(1));
  });

  test('keeps an ambiguous merchant pending for review', () async {
    final captured = _FakeCapturedStore();
    final pending = _FakePendingStore();
    final mappings = _FakeCardMappingStore();
    final rules = _FakeRuleStore();
    final transactions = _FakeTransactionStore()
      ..history.addAll([
        {
          'description': 'PAGOMITELMEXCOMSI SERVICIO',
          'category_id': 'category-services',
        },
        {
          'description': 'PAGOMITELMEXCOMSI TIENDA',
          'category_id': 'category-shopping',
        },
      ]);
    final feedback = _FakeFeedbackStore();
    seedResolvedLocalMatch(
      captured: captured,
      mappings: mappings,
      rules: rules,
    );

    final repository = buildRepository(
      captured: captured,
      pending: pending,
      mappings: mappings,
      rules: rules,
      transactions: transactions,
      feedback: feedback,
      autoConfirmEnabled: true,
    );

    final result = await BackgroundCaptureRunner.withRepository(
      repository,
    ).run();
    expect(result.autoConfirmed, 0);
    expect(result.leftPending, 1);

    expect(transactions.created, isEmpty);
    expect(pending.byId.values.single.status, 'pending');
    expect(captured.byId['captured-local']!.status, 'matched_local');
    expect(feedback.models, isEmpty);
  });

  test('reports auto-confirmed and left-pending matches separately', () async {
    final captured = _FakeCapturedStore();
    final pending = _FakePendingStore();
    final mappings = _FakeCardMappingStore();
    final rules = _FakeRuleStore();
    seedResolvedLocalMatch(
      captured: captured,
      mappings: mappings,
      rules: rules,
    );
    final now = DateTime.utc(2026, 7, 18, 12, 1);
    captured.seed(
      CapturedNotificationModel(
        id: 'captured-account-charge',
        packageName: 'com.bancomer.mbanking',
        title: 'Cargo a tu cuenta',
        text: 'Cargo a tu cuenta *1234 de \$120.00',
        postedAt: now,
        status: 'received',
        createdAt: now,
      ),
    );

    final result = await buildRepository(
      captured: captured,
      pending: pending,
      mappings: mappings,
      rules: rules,
      transactions: _FakeTransactionStore(),
      feedback: _FakeFeedbackStore(),
      autoConfirmEnabled: true,
    ).processInbox();

    expect(result.autoConfirmed, 1);
    expect(result.leftPending, 1);
    expect(result.totalProcessed, 2);
  });

  test('never auto-confirms a fully resolved LLM extraction', () async {
    final now = DateTime.utc(2026, 7, 18);
    final captured = _FakeCapturedStore()
      ..seed(
        CapturedNotificationModel(
          id: 'captured-llm',
          packageName: 'unknown.bank',
          title: 'Movimiento',
          text: 'texto que no coincide con el parser local',
          postedAt: now,
          status: 'received',
          createdAt: now,
        ),
      );
    final pending = _FakePendingStore();
    final mappings = _FakeCardMappingStore()
      ..models.add(
        AccountCardMappingModel(
          id: 'llm-card-mapping',
          bankId: 'unknown',
          lastDigits: '1234',
          accountId: 'account-1',
          createdAt: now,
          updatedAt: now,
        ),
      );
    final rules = _FakeRuleStore()
      ..models.add(
        TransactionRuleModel(
          id: 'llm-rule',
          matchText: 'UBER',
          categoryId: 'category-transport',
          priority: 0,
          matchCount: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );
    final transactions = _FakeTransactionStore();
    final feedback = _FakeFeedbackStore();

    final repository = buildRepository(
      captured: captured,
      pending: pending,
      mappings: mappings,
      rules: rules,
      transactions: transactions,
      feedback: feedback,
      autoConfirmEnabled: true,
      shareWithLlm: true,
      parserRemote: _FakeParserRemoteService(
        const ParseNotificationOutcome(
          matched: true,
          amountCents: 12500,
          currencyCode: 'MXN',
          merchantDescription: 'UBER VIAJE',
          cardLastDigits: '1234',
          transactionType: 'expense',
          proposedPatternId: 'uber_trip',
        ),
      ),
    );

    final result = await repository.processInbox();
    expect(result.autoConfirmed, 0);
    expect(result.leftPending, 1);
    expect(result.leftPendingTransactions, hasLength(1));

    expect(transactions.created, isEmpty);
    final suggestion = pending.byId.values.single;
    expect(suggestion.source, 'parser_llm');
    expect(suggestion.suggestedAccountId, 'account-1');
    expect(suggestion.suggestedCategoryId, 'category-transport');
    expect(suggestion.status, 'pending');
    expect(captured.byId['captured-llm']!.status, 'llm_used');
  });

  test('toggle OFF keeps a resolved local match pending', () async {
    final captured = _FakeCapturedStore();
    final pending = _FakePendingStore();
    final mappings = _FakeCardMappingStore();
    final rules = _FakeRuleStore();
    final transactions = _FakeTransactionStore();
    final feedback = _FakeFeedbackStore();
    seedResolvedLocalMatch(
      captured: captured,
      mappings: mappings,
      rules: rules,
    );

    final repository = buildRepository(
      captured: captured,
      pending: pending,
      mappings: mappings,
      rules: rules,
      transactions: transactions,
      feedback: feedback,
      autoConfirmEnabled: false,
    );

    final result = await repository.processInbox();
    expect(result.autoConfirmed, 0);
    expect(result.leftPending, 1);

    expect(transactions.created, isEmpty);
    expect(pending.byId.values.single.status, 'pending');
    expect(captured.byId['captured-local']!.status, 'matched_local');
    expect(feedback.models, isEmpty);
  });

  test('background runner never uses the LLM fallback', () async {
    final now = DateTime.utc(2026, 7, 18);
    final captured = _FakeCapturedStore()
      ..seed(
        CapturedNotificationModel(
          id: 'captured-unmatched',
          packageName: 'unknown.bank',
          title: 'Movimiento',
          text: 'texto que no coincide con el parser local',
          postedAt: now,
          status: 'received',
          createdAt: now,
        ),
      );
    final pending = _FakePendingStore();
    final repository = buildRepository(
      captured: captured,
      pending: pending,
      mappings: _FakeCardMappingStore(),
      rules: _FakeRuleStore(),
      transactions: _FakeTransactionStore(),
      feedback: _FakeFeedbackStore(),
      autoConfirmEnabled: true,
      shareWithLlm: true,
    );

    final result = await BackgroundCaptureRunner.withRepository(
      repository,
    ).run();
    expect(result.totalProcessed, 0);
    expect(captured.byId['captured-unmatched']!.status, 'unparseable');
    expect(pending.byId, isEmpty);
  });

  test(
    'notification approval creates one transaction and is idempotent',
    () async {
      final pending = _FakePendingStore();
      final transactions = _FakeTransactionStore();
      final now = DateTime.utc(2026, 7, 18);
      pending.byId['pending-action'] = PendingTransactionModel(
        id: 'pending-action',
        suggestedAccountId: 'account-1',
        amountCents: 12000,
        currencyCode: 'MXN',
        merchantDescription: 'COMERCIO',
        transactionType: 'expense',
        occurredAt: now,
        source: 'parser_local',
        parserId: 'bbva_mx/purchase_tdc',
        status: 'pending',
        createdAt: now,
      );
      final repository = buildRepository(
        captured: _FakeCapturedStore(),
        pending: pending,
        mappings: _FakeCardMappingStore(),
        rules: _FakeRuleStore(),
        transactions: transactions,
        feedback: _FakeFeedbackStore(),
        autoConfirmEnabled: false,
      );

      expect(
        await repository.approvePendingFromNotification(
          pendingId: 'pending-action',
          categoryId: 'category-food',
        ),
        isTrue,
      );
      expect(transactions.created, hasLength(1));
      expect(transactions.created.single['category_id'], 'category-food');
      expect(pending.byId['pending-action']!.status, 'approved');
      expect(
        await repository.approvePendingFromNotification(
          pendingId: 'pending-action',
          categoryId: 'category-food',
        ),
        isFalse,
      );
      expect(transactions.created, hasLength(1));
    },
  );

  test(
    'background runner posts summary and resolved review actions only',
    () async {
      final fakeAndroid = _FakeAndroidNotificationPlugin();
      FlutterLocalNotificationsPlatform.instance = fakeAndroid;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final captured = _FakeCapturedStore();
      final pending = _FakePendingStore();
      final mappings = _FakeCardMappingStore();
      final rules = _FakeRuleStore();
      final transactions = _FakeTransactionStore()
        ..topCategoryIds.add('category-food');
      final feedback = _FakeFeedbackStore();
      seedResolvedLocalMatch(
        captured: captured,
        mappings: mappings,
        rules: rules,
      );
      final now = DateTime.utc(2026, 7, 18, 12, 1);
      mappings.models.add(
        AccountCardMappingModel(
          id: 'known-card-digits',
          bankId: 'bbva_mx',
          lastDigits: '1234',
          accountId: 'account-1',
          createdAt: now,
          updatedAt: now,
        ),
      );
      captured
        ..seed(
          CapturedNotificationModel(
            id: 'resolved-review',
            packageName: 'com.bancomer.mbanking',
            title: 'Cargo a tu cuenta',
            text: 'Cargo a tu cuenta *1234 de \$120.00',
            postedAt: now,
            status: 'received',
            createdAt: now,
          ),
        )
        ..seed(
          CapturedNotificationModel(
            id: 'unresolved-review',
            packageName: 'com.bancomer.mbanking',
            title: 'Cargo a tu cuenta',
            text: 'Cargo a tu cuenta *9999 de \$90.00',
            postedAt: now,
            status: 'received',
            createdAt: now,
          ),
        );
      final repository = buildRepository(
        captured: captured,
        pending: pending,
        mappings: mappings,
        rules: rules,
        transactions: transactions,
        feedback: feedback,
        autoConfirmEnabled: true,
      );
      final runner = BackgroundCaptureRunner.withRepository(
        repository,
        notifications: CaptureNotificationService(
          plugin: FlutterLocalNotificationsPlugin(),
          isAndroid: () => true,
        ),
        categoryNameForId: (id) async =>
            id == 'category-food' ? 'Comida' : null,
      );

      try {
        final result = await runner.run();

        expect(result.autoConfirmed, 1);
        expect(result.leftPending, 2);
        expect(fakeAndroid.notifications, hasLength(2));
        expect(
          fakeAndroid.notifications.first.title,
          '1 transacción registrada automáticamente',
        );
        final actionNotification = fakeAndroid.notifications.last;
        expect(actionNotification.payload, isNotEmpty);
        expect(
          actionNotification.details!.actions!.map((action) => action.id),
          ['approve:category-food', 'open_review'],
        );
        expect(actionNotification.details!.actions!.first.title, 'Comida');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}

class _FakeParserStore extends ParserLocalStore {
  _FakeParserStore(this.parsers) : super(db: DatabaseHelper());
  final List<NotificationParserDefinition> parsers;

  @override
  Future<List<NotificationParserDefinition>> listActive() async => parsers;
}

class _FakeCapturedStore extends CapturedNotificationLocalStore {
  _FakeCapturedStore() : super(db: DatabaseHelper());
  final Map<String, CapturedNotificationModel> byId = {};

  void seed(CapturedNotificationModel model) => byId[model.id] = model;

  @override
  Future<List<CapturedNotificationModel>> listPendingProcessing({
    int limit = 200,
  }) async => byId.values.where((model) => model.status == 'received').toList();

  @override
  Future<void> updateStatus(
    String id,
    String status, {
    String? pendingTxId,
    int? matchedParserVersion,
    String? matchedPatternId,
    String? extractionMethod,
  }) async {
    final current = byId[id];
    if (current == null) return;
    byId[id] = CapturedNotificationModel(
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

class _FakePendingStore extends PendingTransactionLocalStore {
  _FakePendingStore() : super(db: DatabaseHelper());
  final Map<String, PendingTransactionModel> byId = {};

  @override
  Future<void> insert(PendingTransactionModel model) async {
    byId[model.id] = model;
  }

  @override
  Future<List<PendingTransactionModel>> listPending({int limit = 100}) async =>
      byId.values.where((model) => model.status == 'pending').toList();

  @override
  Future<PendingTransactionModel?> getById(String id) async => byId[id];

  @override
  Future<void> updateStatus(String id, String status) async {
    final current = byId[id];
    if (current != null) byId[id] = current.copyWith(status: status);
  }
}

class _FakeCardMappingStore extends AccountCardMappingLocalStore {
  _FakeCardMappingStore() : super(db: DatabaseHelper());
  final List<AccountCardMappingModel> models = [];

  @override
  Future<AccountCardMappingModel?> findActiveLatest({
    required String bankId,
    required String lastDigits,
  }) async => _latest(
    (model) =>
        model.bankId == bankId &&
        model.lastDigits == lastDigits &&
        model.isActive,
  );

  @override
  Future<AccountCardMappingModel?> findByBankAndPattern({
    required String bankId,
    required String patternId,
  }) async => _latest(
    (model) =>
        model.bankId == bankId &&
        model.patternId == patternId &&
        model.isActive,
  );

  AccountCardMappingModel? _latest(
    bool Function(AccountCardMappingModel) matches,
  ) {
    final candidates = models.where(matches).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return candidates.isEmpty ? null : candidates.first;
  }

  @override
  Future<void> upsert(AccountCardMappingModel model) async {
    models.add(model);
  }
}

class _FakeRuleStore extends TransactionRuleLocalStore {
  _FakeRuleStore() : super(db: DatabaseHelper());
  final List<TransactionRuleModel> models = [];

  @override
  Future<TransactionRuleModel?> findRuleForDescription(
    String description,
  ) async {
    final lowerDescription = description.toLowerCase();
    final matches =
        models
            .where(
              (model) =>
                  model.isActive &&
                  lowerDescription.contains(model.matchText.toLowerCase()),
            )
            .toList()
          ..sort((a, b) => b.matchText.length.compareTo(a.matchText.length));
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<TransactionRuleModel?> findByExactMatchText(String matchText) async {
    final lowerMatch = matchText.toLowerCase();
    return models.cast<TransactionRuleModel?>().firstWhere(
      (model) =>
          model != null &&
          model.isActive &&
          model.matchText.toLowerCase() == lowerMatch,
      orElse: () => null,
    );
  }

  @override
  Future<void> upsert(TransactionRuleModel model) async {
    models.add(model);
  }
}

class _FakeTransactionStore extends TransactionLocalStore {
  _FakeTransactionStore() : super(db: DatabaseHelper());
  final List<Map<String, dynamic>> created = [];
  final List<Map<String, dynamic>> history = [];
  final List<String> topCategoryIds = [];

  @override
  Future<void> upsertRow(Map<String, dynamic> row) async {
    created.add(row);
  }

  @override
  Future<bool> hasAmbiguousCategoryHistoryForDescriptionPrefix(
    String prefix,
  ) async {
    final categories = history
        .where(
          (row) =>
              (row['description'] as String?)?.toLowerCase().startsWith(
                prefix.toLowerCase(),
              ) ??
              false,
        )
        .map((row) => row['category_id'] as String?)
        .whereType<String>()
        .toSet();
    return categories.length >= 2;
  }

  @override
  Future<List<String>> queryTopCategoryIds({
    String? accountId,
    int limit = 5,
  }) async => topCategoryIds.take(limit).toList();
}

class _PostedAndroidNotification {
  const _PostedAndroidNotification({
    required this.title,
    required this.payload,
    required this.details,
  });

  final String? title;
  final String? payload;
  final AndroidNotificationDetails? details;
}

class _FakeAndroidNotificationPlugin
    extends AndroidFlutterLocalNotificationsPlugin {
  final notifications = <_PostedAndroidNotification>[];

  @override
  Future<bool> initialize({
    required AndroidInitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async => true;

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    AndroidNotificationDetails? notificationDetails,
    String? payload,
  }) async {
    notifications.add(
      _PostedAndroidNotification(
        title: title,
        payload: payload,
        details: notificationDetails,
      ),
    );
  }
}

class _FakeFeedbackStore extends ParserFeedbackLocalStore {
  _FakeFeedbackStore() : super(db: DatabaseHelper());
  final List<ParserFeedbackModel> models = [];

  @override
  Future<void> upsert(ParserFeedbackModel model) async {
    models.add(model);
  }
}

class _FakePreferences extends NotificationCapturePreferences {
  _FakePreferences({
    required this.autoConfirmEnabledValue,
    required this.shareWithLlm,
  }) : super(store: UserPreferenceLocalStore(db: DatabaseHelper()));

  final bool autoConfirmEnabledValue;
  final bool shareWithLlm;

  @override
  Future<bool> autoConfirmEnabled() async => autoConfirmEnabledValue;

  @override
  Future<bool> shareWithLlmForParser() async => shareWithLlm;

  @override
  Future<bool> helpImproveApp() async => true;
}

class _FakeParserRemoteService extends ParserRemoteService {
  _FakeParserRemoteService(this.outcome);
  final ParseNotificationOutcome outcome;

  @override
  Future<ParseNotificationOutcome> parseNotification({
    required String packageName,
    required String title,
    required String text,
    required String bigText,
    required bool helpImproveApp,
  }) async => outcome;
}

class _FakeOutbox extends SyncOutbox {
  _FakeOutbox() : super(db: DatabaseHelper());

  @override
  Future<void> enqueue({
    required String entityType,
    required String entityId,
    required String operation,
    required String payload,
  }) async {}
}
