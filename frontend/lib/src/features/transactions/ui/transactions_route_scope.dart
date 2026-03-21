// ============================================================
// TransactionsRouteScope — inyección de dependencias de Transactions
// ============================================================
//
// Mismo patrón que AccountsRouteScope.
// Ver accounts_route_scope.dart para la explicación del ciclo de vida.
//
// Árbol de dependencias que monta este scope:
//   context.read<DatabaseHelper>()
//     ├─ TransactionLocalStore(db)
//     └─ CategoryLocalStore(db)    ← instancia propia de este scope
//   TransactionRemoteService()
//   TransactionRepository(local, remote, categoryStore)
//   TransactionsViewModel(repository)
//
// ¿Por qué CategoryLocalStore aquí y no compartido?
//   TransactionRepository necesita CategoryLocalStore para enriquecer
//   cada transacción con el tipo de su categoría (income/expense).
//   CategoryLocalStore es un DAO sin estado — solo wrappea queries SQL.
//   Tener dos instancias apuntando al mismo archivo SQLite es seguro:
//   SQLite maneja concurrencia de lecturas sin problema.
//   La alternativa (Provider<CategoryLocalStore> global) añadiría
//   acoplamiento entre features sin beneficio real para el MVP.

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_remote_service.dart';
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
        final transactionLocalStore = TransactionLocalStore(db: db);
        // CategoryLocalStore propio de este scope: DAO sin estado,
        // seguro tener múltiples instancias sobre el mismo SQLite.
        final categoryLocalStore = CategoryLocalStore(db: db);
        final remoteService = TransactionRemoteService();
        final repository = TransactionRepository(
          local: transactionLocalStore,
          remote: remoteService,
          categoryStore: categoryLocalStore,
        );
        return TransactionsViewModel(repository: repository)..loadOnAppear();
      },
      child: child,
    );
  }
}
