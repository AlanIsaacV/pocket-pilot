// ============================================================
// main.dart — Bootstrap de Pocket Pilot
// ============================================================
//
// Responsabilidades:
//   1. Inicializa el binding de Flutter.
//   2. Construye el grafo de dependencias globales (DB, sync).
//   3. Provee los singletons compartidos en el árbol de widgets.
//   4. Inicia el monitoreo de conectividad para sync automático.
//
// Dependencias globales (disponibles en todo el árbol via context.read):
//   DatabaseHelper  → singleton de SQLite, compartido por todos los DAO.
//   SyncOutbox      → cola de operaciones pendientes, compartida por repos y SyncService.
//   SyncService     → orquestador de sync; ViewModels lo llaman para sincronizar.
//
// Las dependencias de cada feature (LocalStore, Repository, ViewModel) viven
// en su propio RouteScope bajo features/<feature>/ui/<feature>_route_scope.dart.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/composite_scheduled_generator_runner.dart';
import 'package:pocket_pilot/src/core/sync/connectivity_monitor.dart';
import 'package:pocket_pilot/src/core/sync/sync_metadata_store.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/core/sync/scheduled_generation_orchestrator.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/core/sync/sync_status_remote_service.dart';
import 'package:pocket_pilot/src/core/theme/theme_preference_controller.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_remote_service.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_sync_handler.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/ai_context_builder.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/ai_remote_service.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/ai_tool_dispatcher.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/tools/financial_summary_tool.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/tools/goal_tool.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/tools/template_tool.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/tools/edit_transaction_tool.dart';
import 'package:pocket_pilot/src/features/ai_assistant/data/tools/transaction_tool.dart';
import 'package:pocket_pilot/src/features/ai_assistant/ui/ai_session_controller.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/categories/data/category_remote_service.dart';
import 'package:pocket_pilot/src/features/categories/data/category_seeder.dart';
import 'package:pocket_pilot/src/features/categories/data/category_sync_handler.dart';
import 'package:pocket_pilot/src/features/budgets/data/budget_local_store.dart';
import 'package:pocket_pilot/src/features/budgets/data/budget_remote_service.dart';
import 'package:pocket_pilot/src/features/budgets/data/budget_sync_handler.dart';
import 'package:pocket_pilot/src/features/dashboard/data/dashboard_local_store.dart';
import 'package:pocket_pilot/src/features/dashboard/data/dashboard_repository.dart';
import 'package:pocket_pilot/src/features/goals/data/goal_local_store.dart';
import 'package:pocket_pilot/src/features/goals/data/goal_remote_service.dart';
import 'package:pocket_pilot/src/features/goals/data/goal_sync_handler.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_holding_local_store.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_holding_remote_service.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_holding_sync_handler.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_lot_local_store.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_lot_remote_service.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_lot_sync_handler.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_split_local_store.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_split_remote_service.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_split_sync_handler.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_transaction_generator.dart';
import 'package:pocket_pilot/src/features/investments/data/market_price_local_store.dart';
import 'package:pocket_pilot/src/features/investments/data/market_price_remote_service.dart';
import 'package:pocket_pilot/src/features/investments/data/market_price_sync_handler.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/account_card_mapping_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/account_card_mapping_remote_service.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/account_card_mapping_sync_handler.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/transaction_rule_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/transaction_rule_remote_service.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/transaction_rule_sync_handler.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_local_store.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_remote_service.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_sync_handler.dart';
import 'package:pocket_pilot/src/features/transaction_templates/data/transaction_template_local_store.dart';
import 'package:pocket_pilot/src/features/transaction_templates/data/transaction_template_repository.dart';
import 'package:pocket_pilot/src/features/transaction_templates/data/transaction_template_remote_service.dart';
import 'package:pocket_pilot/src/features/transaction_templates/data/scheduled_transaction_generator.dart';
import 'package:pocket_pilot/src/features/transaction_templates/data/transaction_template_sync_handler.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_remote_service.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_sync_handler.dart';
import 'package:pocket_pilot/src/features/yield_configs/data/yield_config_local_store.dart';
import 'package:pocket_pilot/src/features/yield_configs/data/yield_config_remote_service.dart';
import 'package:pocket_pilot/src/features/yield_configs/data/yield_config_repository.dart';
import 'package:pocket_pilot/src/features/yield_configs/data/yield_config_sync_handler.dart';
import 'package:pocket_pilot/src/features/yield_configs/data/yield_transaction_generator.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/theme_preferences_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_remote_service.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_repository.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_sync_handler.dart';
import 'package:pocket_pilot/src/core/constants/constants.dart';
import 'package:pocket_pilot/src/core/auth/auth_provider.dart';
import 'package:pocket_pilot/src/core/auth/auth_service.dart';
import 'package:pocket_pilot/src/core/auth/token_store.dart';
import 'package:pocket_pilot/src/core/grpc/auth_interceptor.dart';
import 'package:pocket_pilot/src/core/grpc/grpc_client.dart';
import 'package:pocket_pilot/src/core/notifications/notification_center_repository.dart';
import 'package:pocket_pilot/src/core/notifications/notification_center_view_model.dart';
import 'package:pocket_pilot/src/core/notifications/notification_local_store.dart';
import 'package:pocket_pilot/src/core/notifications/notification_repository.dart';
import 'package:pocket_pilot/src/core/notifications/notification_scheduler_service.dart';
import 'package:pocket_pilot/src/ui/app.dart';
import 'package:pocket_pilot/src/ui/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // DatabaseHelper es un singleton interno; las instancias adicionales comparten la misma DB.
  final dbHelper = DatabaseHelper();

  // Auth setup — must happen before any gRPC client is created.
  final tokenStore = TokenStore();
  final authService = AuthService(
    tokenStore: tokenStore,
    googleServerClientId: kGoogleServerClientId.isNotEmpty
        ? kGoogleServerClientId
        : null,
  );
  final authProvider = AuthProvider(
    authService: authService,
    tokenStore: tokenStore,
    dbHelper: dbHelper,
  );
  await authProvider.init();

  final authInterceptor = AuthInterceptor(
    tokenStore: tokenStore,
    authService: authService,
    authProvider: authProvider,
  );
  GrpcClient.init(interceptors: [authInterceptor]);

  // Construir grafo de dependencias de sync.
  final syncOutbox = SyncOutbox(db: dbHelper);
  final syncMetadataStore = SyncMetadataStore(db: dbHelper);
  final userPreferenceLocalStore = UserPreferenceLocalStore(db: dbHelper);

  final userPreferenceRepository = UserPreferenceRepository(
    local: userPreferenceLocalStore,
    outbox: syncOutbox,
  );
  final themePreferenceController = ThemePreferenceController(
    localStore: ThemePreferencesLocalStore(
      preferences: userPreferenceLocalStore,
    ),
    repository: userPreferenceRepository,
  );
  await themePreferenceController.loadFromLocal();

  // Un SyncHandler por tipo de entidad.
  // Cada handler tiene su propio LocalStore + RemoteService (independientes de los RouteScopes).
  final accountSyncHandler = AccountSyncHandler(
    local: AccountLocalStore(db: dbHelper),
    remote: AccountRemoteService(),
  );

  final categorySyncHandler = CategorySyncHandler(
    local: CategoryLocalStore(db: dbHelper),
    remote: CategoryRemoteService(),
  );

  final tagSyncHandler = TagSyncHandler(
    local: TagLocalStore(db: dbHelper),
    remote: TagRemoteService(),
  );

  final transactionTemplateSyncHandler = TransactionTemplateSyncHandler(
    local: TransactionTemplateLocalStore(db: dbHelper),
    remote: TransactionTemplateRemoteService(),
  );

  final transactionSyncHandler = TransactionSyncHandler(
    local: TransactionLocalStore(db: dbHelper),
    remote: TransactionRemoteService(),
  );

  final yieldConfigSyncHandler = YieldConfigSyncHandler(
    local: YieldConfigLocalStore(db: dbHelper),
    remote: YieldConfigRemoteService(),
  );

  final userPreferenceSyncHandler = UserPreferenceSyncHandler(
    local: userPreferenceLocalStore,
    remote: UserPreferenceRemoteService(),
  );

  final goalSyncHandler = GoalSyncHandler(
    local: GoalLocalStore(db: dbHelper),
    remote: GoalRemoteService(),
  );

  final budgetSyncHandler = BudgetSyncHandler(
    local: BudgetLocalStore(db: dbHelper),
    remote: BudgetRemoteService(),
  );

  final investmentHoldingSyncHandler = InvestmentHoldingSyncHandler(
    local: InvestmentHoldingLocalStore(db: dbHelper),
    remote: InvestmentHoldingRemoteService(),
  );

  final investmentLotSyncHandler = InvestmentLotSyncHandler(
    local: InvestmentLotLocalStore(db: dbHelper),
    remote: InvestmentLotRemoteService(),
  );

  final investmentSplitSyncHandler = InvestmentSplitSyncHandler(
    local: InvestmentSplitLocalStore(db: dbHelper),
    remote: InvestmentSplitRemoteService(),
  );

  final marketPriceSyncHandler = MarketPriceSyncHandler(
    local: MarketPriceLocalStore(db: dbHelper),
    remote: MarketPriceRemoteService(),
  );

  final accountCardMappingSyncHandler = AccountCardMappingSyncHandler(
    local: AccountCardMappingLocalStore(db: dbHelper),
    remote: AccountCardMappingRemoteService(),
  );

  final transactionRuleSyncHandler = TransactionRuleSyncHandler(
    local: TransactionRuleLocalStore(db: dbHelper),
    remote: TransactionRuleRemoteService(),
  );

  final syncStatusRemoteService = SyncStatusRemoteService();

  final syncService = SyncService(
    outbox: syncOutbox,
    metadataStore: syncMetadataStore,
    statusService: syncStatusRemoteService,
    handlers: [
      accountSyncHandler,
      categorySyncHandler,
      tagSyncHandler,
      transactionTemplateSyncHandler,
      yieldConfigSyncHandler,
      accountCardMappingSyncHandler,
      transactionRuleSyncHandler,
      investmentHoldingSyncHandler,
      investmentLotSyncHandler,
      investmentSplitSyncHandler,
      marketPriceSyncHandler,
      transactionSyncHandler,
      userPreferenceSyncHandler,
      goalSyncHandler,
      budgetSyncHandler,
    ],
  );

  final scheduledGenerator = ScheduledTransactionGenerator(
    templates: TemplateScheduleStoreAdapter(
      repository: TransactionTemplateRepository(
        local: TransactionTemplateLocalStore(db: dbHelper),
        outbox: syncOutbox,
      ),
    ),
    transactions: TransactionOccurrenceStoreAdapter(
      local: TransactionLocalStore(db: dbHelper),
    ),
    outbox: OutboxWriterAdapter(outbox: syncOutbox),
    accounts: AccountLookupAdapter(local: AccountLocalStore(db: dbHelper)),
    categories: CategoryLookupAdapter(local: CategoryLocalStore(db: dbHelper)),
  );

  final yieldGenerator = YieldTransactionGenerator(
    configs: YieldScheduleStoreAdapter(
      repository: YieldConfigRepository(
        local: YieldConfigLocalStore(db: dbHelper),
        outbox: syncOutbox,
      ),
    ),
    transactions: YieldTransactionStoreAdapter(
      local: TransactionLocalStore(db: dbHelper),
    ),
    outbox: YieldOutboxWriterAdapter(outbox: syncOutbox),
    accounts: YieldAccountLookupAdapter(local: AccountLocalStore(db: dbHelper)),
  );

  final investmentGenerator = InvestmentTransactionGenerator(
    lots: InvestmentLotStoreAdapter(
      local: InvestmentLotLocalStore(db: dbHelper),
    ),
    holdings: InvestmentHoldingLookupAdapter(
      local: InvestmentHoldingLocalStore(db: dbHelper),
    ),
    accounts: InvestmentAccountLookupAdapter(
      local: AccountLocalStore(db: dbHelper),
    ),
    transactions: InvestmentTransactionStoreAdapter(
      local: TransactionLocalStore(db: dbHelper),
    ),
    outbox: InvestmentOutboxWriterAdapter(outbox: syncOutbox),
  );

  final compositeGenerator = CompositeScheduledGeneratorRunner(
    runners: [scheduledGenerator, yieldGenerator, investmentGenerator],
  );

  final scheduledOrchestrator = ScheduledGenerationOrchestrator(
    sync: syncService,
    generator: compositeGenerator,
  );

  // AI Assistant
  final aiRemoteService = AIRemoteService();
  final aiDashboardLocalStore = DashboardLocalStore(db: dbHelper);
  final aiDashboardRepository = DashboardRepository(
    local: aiDashboardLocalStore,
  );
  final aiTransactionRepository = TransactionRepository(
    local: TransactionLocalStore(db: dbHelper),
    outbox: syncOutbox,
  );

  final aiToolDispatcher = AIToolDispatcher(
    transactionTool: TransactionTool(repo: aiTransactionRepository),
    editTransactionTool: EditTransactionTool(repo: aiTransactionRepository),
    templateTool: TemplateTool(
      db: dbHelper,
      transactionRepo: aiTransactionRepository,
    ),
    financialSummaryTool: FinancialSummaryTool(
      dashboardRepo: aiDashboardRepository,
      dashboardLocal: aiDashboardLocalStore,
    ),
    goalTool: GoalTool(db: dbHelper, dashboardRepo: aiDashboardRepository),
    remote: aiRemoteService,
  );

  final aiContextBuilder = AIContextBuilder(
    accounts: AccountLocalStore(db: dbHelper),
    categories: CategoryLocalStore(db: dbHelper),
    templates: TransactionTemplateLocalStore(db: dbHelper),
    goals: GoalLocalStore(db: dbHelper),
    prefs: UserPreferenceLocalStore(db: dbHelper),
  );

  final aiSessionController = AISessionController(
    remote: aiRemoteService,
    dispatcher: aiToolDispatcher,
    contextBuilder: aiContextBuilder,
  );

  // Notification scheduling (offline-first, no backend).
  final notificationRepo = NotificationRepository(db: dbHelper);
  final notificationLocalStore = NotificationLocalStore(db: dbHelper);
  final notificationCenterRepo = NotificationCenterRepository(
    projection: notificationRepo,
    local: notificationLocalStore,
  );
  final notificationCenterVM = NotificationCenterViewModel(
    repository: notificationCenterRepo,
  );
  final router = buildRouter(authProvider);
  final notificationScheduler = NotificationSchedulerService(
    repository: notificationRepo,
    onNotificationTap: () => router.push('/notifications'),
  );
  await notificationScheduler.init();

  const aiChannel = MethodChannel('com.pocketpilot/ai_assistant');
  aiChannel.setMethodCallHandler((call) async {
    if (call.method == 'onLaunchAssistant') {
      await aiSessionController.openSession();
    }
  });

  // Insertar categorías por defecto si es la primera ejecución.
  final userId = await tokenStore.getUserId();

  if (userId != null) {
    final categorySeeder = CategorySeeder(
      local: CategoryLocalStore(db: dbHelper),
      db: dbHelper,
      outbox: syncOutbox,
      userId: userId,
    );

    // Pre-seed pull: intentar traer categorías del servidor antes de sembrar defaults.
    // Si tiene éxito, seedIfNeeded() detectará rows existentes y no sembrará.
    // Fallo silencioso: sin red, error de auth o timeout → seedIfNeeded() siembra localmente.
    try {
      final pullResult = await categorySyncHandler
          .pull(null)
          .timeout(const Duration(seconds: 5));
      for (final item in pullResult.items) {
        try {
          await categorySyncHandler.saveLocally(item.data);
        } catch (_) {}
      }
    } catch (_) {}

    await categorySeeder.seedIfNeeded();
  }

  // ConnectivityMonitor: lanza sync automático al recuperar conexión.
  final connectivityMonitor = ConnectivityMonitor(syncService: syncService);

  runApp(
    MultiProvider(
      providers: [
        Provider<DatabaseHelper>.value(value: dbHelper),
        Provider<SyncOutbox>.value(value: syncOutbox),
        Provider<SyncService>.value(value: syncService),
        Provider<ScheduledGenerationOrchestrator>.value(
          value: scheduledOrchestrator,
        ),
        ChangeNotifierProvider<ThemePreferenceController>.value(
          value: themePreferenceController,
        ),
        ChangeNotifierProvider<AISessionController>.value(
          value: aiSessionController,
        ),
        Provider<TokenStore>.value(value: tokenStore),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        Provider<NotificationRepository>.value(value: notificationRepo),
        ChangeNotifierProvider<NotificationCenterViewModel>.value(
          value: notificationCenterVM,
        ),
      ],
      child: PocketPilotApp(router: router),
    ),
  );

  // Iniciar monitoreo de conectividad y lanzar sync inicial si hay conexión.
  connectivityMonitor.startMonitoring();
  await scheduledOrchestrator.runCycle();
  await themePreferenceController.loadFromLocal();

  // Schedule OS notifications and populate notification center — fire-and-forget.
  notificationScheduler.rescheduleAllNotifications();
  notificationCenterVM.load();
}
