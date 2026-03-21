// ============================================================
// AccountsRouteScope — inyección de dependencias de Accounts
// ============================================================
//
// Responsabilidad única: armar el grafo de dependencias de la feature
// Accounts y proveer el ViewModel al subárbol de widgets.
//
// Al entrar a la ruta /accounts, go_router construye este widget.
// El ChangeNotifierProvider llama a `create` una sola vez (lazy).
// Al salir de la ruta, Provider llama a dispose() en el ViewModel
// automáticamente — sin memory leaks.
//
// Árbol de dependencias que monta este scope:
//   context.read<DatabaseHelper>()
//     └─ AccountLocalStore(db)         ← DAO, solo SQL
//   AccountRemoteService()             ← usa GrpcClient.channel internamente
//   AccountRepository(local, remote)   ← orquestación offline-first
//   AccountsViewModel(repository)      ← estado de la UI

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_remote_service.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_repository.dart';
import 'package:pocket_pilot/src/features/accounts/ui/accounts_view_model.dart';

class AccountsRouteScope extends StatelessWidget {
  final Widget child;

  const AccountsRouteScope({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) {
        final db = ctx.read<DatabaseHelper>();
        final localStore = AccountLocalStore(db: db);
        final remoteService = AccountRemoteService();
        final repository = AccountRepository(
          local: localStore,
          remote: remoteService,
        );
        return AccountsViewModel(repository: repository)..loadOnAppear();
      },
      child: child,
    );
  }
}
