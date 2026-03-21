// ============================================================
// CategoriesRouteScope — inyección de dependencias de Categories
// ============================================================
//
// Mismo patrón que AccountsRouteScope.
// Ver accounts_route_scope.dart para la explicación del ciclo de vida.
//
// Árbol de dependencias que monta este scope:
//   context.read<DatabaseHelper>()
//     └─ CategoryLocalStore(db)
//   CategoryRemoteService()
//   CategoryRepository(local, remote)
//   CategoriesViewModel(repository)

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/categories/data/category_remote_service.dart';
import 'package:pocket_pilot/src/features/categories/data/category_repository.dart';
import 'package:pocket_pilot/src/features/categories/ui/categories_view_model.dart';

class CategoriesRouteScope extends StatelessWidget {
  final Widget child;

  const CategoriesRouteScope({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) {
        final db = ctx.read<DatabaseHelper>();
        final localStore = CategoryLocalStore(db: db);
        final remoteService = CategoryRemoteService();
        final repository = CategoryRepository(
          local: localStore,
          remote: remoteService,
        );
        return CategoriesViewModel(repository: repository)..loadOnAppear();
      },
      child: child,
    );
  }
}
