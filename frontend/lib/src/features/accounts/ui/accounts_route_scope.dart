// ============================================================
// AccountsRouteScope — inyección de dependencias de Accounts
// ============================================================
//
// Responsabilidad única: armar el grafo de dependencias de la feature
// Accounts y proveer el ViewModel al subárbol de widgets.
//
// Árbol de dependencias que monta este scope:
//   context.read<DatabaseHelper>()
//     ├─ AccountLocalStore(db)              ← DAO, solo SQL
//     └─ TransactionLocalStore(db)          ← DAO, solo SQL
//   context.read<SyncOutbox>()          ← compartido con SyncService
//   AccountRepository(local, outbox)    ← local-first + encola en outbox
//   TransactionRepository(local, outbox) ← local-first + encola en outbox
//   context.read<SyncService>()         ← singleton global de sync
//   AccountsViewModel(accountsRepo, txRepo, sync) ← estado de la UI
//
// Nota: AccountRepository ya no habla directamente con el servidor.
// SyncService (provisto desde main.dart) gestiona todas las operaciones remotas.

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
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
        ChangeNotifierProvider(
          create: (ctx) {
            final db = ctx.read<DatabaseHelper>();
            final outbox = ctx.read<SyncOutbox>();
            final syncService = ctx.read<SyncService>();

            final localStore = AccountLocalStore(db: db);
            final repository = AccountRepository(
              local: localStore,
              outbox: outbox,
            );

            return AccountsViewModel(
              repository: repository,
              transactionRepository: ctx.read<TransactionRepository>(),
              syncService: syncService,
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
      ],
      child: child,
    );
  }
}
