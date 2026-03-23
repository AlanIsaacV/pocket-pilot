// ============================================================
// CategoriesRouteScope — inyección de dependencias de Categories
// ============================================================
//
// Árbol de dependencias que monta este scope:
//   context.read<DatabaseHelper>()
//     └─ CategoryLocalStore(db)
//   context.read<SyncOutbox>()          ← compartido con SyncService
//   CategoryRepository(local, outbox)   ← local-first + encola en outbox
//   context.read<SyncService>()         ← singleton global de sync
//   CategoriesViewModel(repository, sync)

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
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
        final outbox = ctx.read<SyncOutbox>();
        final syncService = ctx.read<SyncService>();

        final localStore = CategoryLocalStore(db: db);
        final repository = CategoryRepository(
          local: localStore,
          outbox: outbox,
        );

        return CategoriesViewModel(
          repository: repository,
          syncService: syncService,
        )..loadOnAppear();
      },
      child: child,
    );
  }
}
