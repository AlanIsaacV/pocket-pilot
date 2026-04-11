// ============================================================
// TransactionsRouteScope — inyección de dependencias de Transactions
// ============================================================
//
// Provee ViewModels para las 4 tabs: Transacciones, Plantillas, Rendimientos y Deudas.

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transaction_filter_view_model.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transactions_view_model.dart';
import 'package:pocket_pilot/src/features/transaction_templates/data/transaction_template_local_store.dart';
import 'package:pocket_pilot/src/features/transaction_templates/data/transaction_template_repository.dart';
import 'package:pocket_pilot/src/features/transaction_templates/ui/transaction_template_view_model.dart';
import 'package:pocket_pilot/src/features/yield_configs/data/yield_config_local_store.dart';
import 'package:pocket_pilot/src/features/yield_configs/data/yield_config_repository.dart';
import 'package:pocket_pilot/src/features/yield_configs/ui/yield_config_view_model.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_repository.dart';
import 'package:pocket_pilot/src/features/debts/data/debt_local_store.dart';
import 'package:pocket_pilot/src/features/debts/data/debt_repository.dart';
import 'package:pocket_pilot/src/features/debts/ui/debt_view_model.dart';

class TransactionsRouteScope extends StatelessWidget {
  final Widget child;

  const TransactionsRouteScope({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => TransactionFilterViewModel(),
        ),
        ChangeNotifierProvider(
          create: (ctx) {
            final db = ctx.read<DatabaseHelper>();
            final outbox = ctx.read<SyncOutbox>();
            final syncService = ctx.read<SyncService>();
            final filterVM = ctx.read<TransactionFilterViewModel>();

            final transactionLocalStore = TransactionLocalStore(db: db);
            final repository = TransactionRepository(
              local: transactionLocalStore,
              outbox: outbox,
            );

            return TransactionsViewModel(
              repository: repository,
              syncService: syncService,
              filterViewModel: filterVM,
            )..loadOnAppear();
          },
        ),
        ChangeNotifierProvider(
          create: (ctx) {
            final db = ctx.read<DatabaseHelper>();
            final outbox = ctx.read<SyncOutbox>();
            final syncService = ctx.read<SyncService>();

            final localStore = TransactionTemplateLocalStore(db: db);
            final repository = TransactionTemplateRepository(
              local: localStore,
              outbox: outbox,
            );

            return TransactionTemplateViewModel(
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

            final localStore = YieldConfigLocalStore(db: db);
            final repository = YieldConfigRepository(
              local: localStore,
              outbox: outbox,
            );

            return YieldConfigViewModel(
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

            final debtLocal = DebtLocalStore(db: db);
            final accountLocal = AccountLocalStore(db: db);
            final txnLocal = TransactionLocalStore(db: db);

            final accountRepo = AccountRepository(
              local: accountLocal,
              outbox: outbox,
            );
            final txnRepo = TransactionRepository(
              local: txnLocal,
              outbox: outbox,
            );
            final debtRepo = DebtRepository(
              transactionRepo: txnRepo,
              accountRepo: accountRepo,
              debtLocal: debtLocal,
            );

            return DebtViewModel(
              repository: debtRepo,
              syncService: syncService,
            )..loadOnAppear();
          },
        ),
        Provider(
          create: (ctx) {
            final db = ctx.read<DatabaseHelper>();
            final outbox = ctx.read<SyncOutbox>();

            final debtLocal = DebtLocalStore(db: db);
            final accountLocal = AccountLocalStore(db: db);
            final txnLocal = TransactionLocalStore(db: db);

            return DebtRepository(
              transactionRepo: TransactionRepository(
                local: txnLocal,
                outbox: outbox,
              ),
              accountRepo: AccountRepository(
                local: accountLocal,
                outbox: outbox,
              ),
              debtLocal: debtLocal,
            );
          },
        ),
      ],
      child: child,
    );
  }
}
