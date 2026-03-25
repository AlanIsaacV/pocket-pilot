// ============================================================
// TransactionsRouteScope — inyección de dependencias de Transactions
// ============================================================
//
// Árbol de dependencias que monta este scope:
//   context.read<DatabaseHelper>()
//     ├─ TransactionLocalStore(db)
//     └─ CategoryLocalStore(db)    ← instancia propia de este scope
//   context.read<SyncOutbox>()          ← compartido con SyncService
//   TransactionRepository(local, outbox, categoryStore)
//   context.read<SyncService>()         ← singleton global de sync
//   TransactionsViewModel(repository, sync)
//
// ¿Por qué CategoryLocalStore aquí y no compartido?
//   TransactionRepository necesita CategoryLocalStore para enriquecer
//   cada transacción con el tipo de su categoría (income/expense).
//   CategoryLocalStore es un DAO sin estado — solo wrappea queries SQL.
//   Tener dos instancias apuntando al mismo archivo SQLite es seguro.

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transactions_view_model.dart';

class TransactionsRouteScope extends StatelessWidget {
  final Widget child;

  const TransactionsRouteScope({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) {
        final db = ctx.read<DatabaseHelper>();
        final outbox = ctx.read<SyncOutbox>();
        final syncService = ctx.read<SyncService>();

        final transactionLocalStore = TransactionLocalStore(db: db);
        final repository = TransactionRepository(
          local: transactionLocalStore,
          outbox: outbox,
        );

        return TransactionsViewModel(
          repository: repository,
          syncService: syncService,
        )..loadOnAppear();
      },
      child: child,
    );
  }
}
