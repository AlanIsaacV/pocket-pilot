// ============================================================
// TransactionsRouteScope — inyección de dependencias de Transactions
// ============================================================

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transaction_filter_view_model.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transactions_view_model.dart';

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
      ],
      child: child,
    );
  }
}
