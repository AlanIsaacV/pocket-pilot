// ============================================================
// TransactionFormRouteScope — DI para el formulario de transacción
// ============================================================
//
// Provee los stores y repositorios necesarios para que
// TransactionFormScreen pueda listar cuentas, categorías, tags
// y guardar transacciones.
//
// Árbol de dependencias:
//   context.read<DatabaseHelper>()
//     ├─ AccountLocalStore(db)
//     ├─ CategoryLocalStore(db)
//     ├─ TagLocalStore(db)
//     └─ TransactionLocalStore(db)
//   context.read<SyncOutbox>()
//     ├─ TagRepository(local, outbox)
//     └─ TransactionRepository(local, outbox, categoryStore)
//   context.read<SyncService>()

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_local_store.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_repository.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';

class TransactionFormRouteScope extends StatelessWidget {
  final Widget child;

  const TransactionFormRouteScope({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<DatabaseHelper>();
    final outbox = context.read<SyncOutbox>();
    final syncService = context.read<SyncService>();

    final accountStore = AccountLocalStore(db: db);
    final categoryStore = CategoryLocalStore(db: db);
    final tagStore = TagLocalStore(db: db);
    final tagRepository = TagRepository(local: tagStore, outbox: outbox);
    final transactionLocalStore = TransactionLocalStore(db: db);
    final transactionRepository = TransactionRepository(
      local: transactionLocalStore,
      outbox: outbox,
    );

    return MultiProvider(
      providers: [
        Provider.value(value: accountStore),
        Provider.value(value: categoryStore),
        Provider.value(value: tagStore),
        Provider.value(value: tagRepository),
        Provider.value(value: transactionRepository),
        Provider.value(value: syncService),
      ],
      child: child,
    );
  }
}
