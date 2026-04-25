// ============================================================
// AccountsRouteScope — inyección de dependencias de Accounts
// ============================================================
//
// Responsabilidad única: armar el grafo de dependencias de la feature
// Accounts y proveer el ViewModel al subárbol de widgets.

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/scheduled_generation_orchestrator.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_adjustment_service.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_repository.dart';
import 'package:pocket_pilot/src/features/accounts/ui/accounts_view_model.dart';
import 'package:pocket_pilot/src/features/budgets/data/budget_local_store.dart';
import 'package:pocket_pilot/src/features/budgets/data/budget_repository.dart';
import 'package:pocket_pilot/src/features/budgets/ui/budget_view_model.dart';
import 'package:pocket_pilot/src/features/goals/data/goal_local_store.dart';
import 'package:pocket_pilot/src/features/goals/data/goal_repository.dart';
import 'package:pocket_pilot/src/features/goals/ui/goal_view_model.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_holding_local_store.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_holding_repository.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_lot_local_store.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_lot_repository.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_split_local_store.dart';
import 'package:pocket_pilot/src/features/investments/data/investment_split_repository.dart';
import 'package:pocket_pilot/src/features/investments/data/market_price_local_store.dart';
import 'package:pocket_pilot/src/features/investments/ui/investment_view_model.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';

class AccountsRouteScope extends StatelessWidget {
  final Widget child;

  const AccountsRouteScope({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<TransactionLocalStore>(
          create: (ctx) => TransactionLocalStore(
            db: ctx.read<DatabaseHelper>(),
          ),
        ),
        Provider<TransactionRepository>(
          create: (ctx) => TransactionRepository(
            local: ctx.read<TransactionLocalStore>(),
            outbox: ctx.read<SyncOutbox>(),
          ),
        ),
        Provider<AccountAdjustmentService>(
          create: (ctx) => AccountAdjustmentService(
            local: ctx.read<TransactionLocalStore>(),
            repository: ctx.read<TransactionRepository>(),
          ),
        ),
        Provider<AccountLocalStore>(
          create: (ctx) => AccountLocalStore(db: ctx.read<DatabaseHelper>()),
        ),
        Provider<InvestmentHoldingLocalStore>(
          create: (ctx) =>
              InvestmentHoldingLocalStore(db: ctx.read<DatabaseHelper>()),
        ),
        Provider<InvestmentLotLocalStore>(
          create: (ctx) =>
              InvestmentLotLocalStore(db: ctx.read<DatabaseHelper>()),
        ),
        Provider<InvestmentSplitLocalStore>(
          create: (ctx) =>
              InvestmentSplitLocalStore(db: ctx.read<DatabaseHelper>()),
        ),
        Provider<MarketPriceLocalStore>(
          create: (ctx) => MarketPriceLocalStore(db: ctx.read<DatabaseHelper>()),
        ),
        Provider<InvestmentHoldingRepository>(
          create: (ctx) => InvestmentHoldingRepository(
            local: ctx.read<InvestmentHoldingLocalStore>(),
            outbox: ctx.read<SyncOutbox>(),
            lotLocal: ctx.read<InvestmentLotLocalStore>(),
          ),
        ),
        Provider<InvestmentLotRepository>(
          create: (ctx) => InvestmentLotRepository(
            local: ctx.read<InvestmentLotLocalStore>(),
            outbox: ctx.read<SyncOutbox>(),
          ),
        ),
        Provider<InvestmentSplitRepository>(
          create: (ctx) => InvestmentSplitRepository(
            local: ctx.read<InvestmentSplitLocalStore>(),
            outbox: ctx.read<SyncOutbox>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (ctx) {
            final repository = AccountRepository(
              local: ctx.read<AccountLocalStore>(),
              outbox: ctx.read<SyncOutbox>(),
              investmentLotLocal: ctx.read<InvestmentLotLocalStore>(),
            );

            return AccountsViewModel(
              repository: repository,
              transactionRepository: ctx.read<TransactionRepository>(),
              syncService: ctx.read<SyncService>(),
            )..loadOnAppear();
          },
        ),
        ChangeNotifierProvider(
          create: (ctx) {
            final db = ctx.read<DatabaseHelper>();
            final outbox = ctx.read<SyncOutbox>();
            final syncService = ctx.read<SyncService>();

            final localStore = GoalLocalStore(db: db);
            final repository = GoalRepository(
              local: localStore,
              outbox: outbox,
            );

            return GoalViewModel(
              repository: repository,
              syncService: syncService,
            )..loadOnAppear();
          },
        ),
        ChangeNotifierProvider(
          create: (ctx) {
            final db = ctx.read<DatabaseHelper>();
            final outbox = ctx.read<SyncOutbox>();
            final syncService = ctx.read<SyncService>();

            final localStore = BudgetLocalStore(db: db);
            final repository = BudgetRepository(
              local: localStore,
              outbox: outbox,
            );

            return BudgetViewModel(
              repository: repository,
              syncService: syncService,
            )..loadOnAppear();
          },
        ),
        ChangeNotifierProvider<InvestmentViewModel>(
          create: (ctx) => InvestmentViewModel(
            holdingRepo: ctx.read<InvestmentHoldingRepository>(),
            lotRepo: ctx.read<InvestmentLotRepository>(),
            splitRepo: ctx.read<InvestmentSplitRepository>(),
            marketPriceStore: ctx.read<MarketPriceLocalStore>(),
            transactionStore: ctx.read<TransactionLocalStore>(),
            syncService: ctx.read<SyncService>(),
            orchestrator: ctx.read<ScheduledGenerationOrchestrator>(),
          )..loadOnAppear(),
        ),
      ],
      child: child,
    );
  }
}
