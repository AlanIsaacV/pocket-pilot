// ============================================================
// YieldConfigRouteScope — DI para la lista de rendimientos
// ============================================================
//
// Árbol de dependencias:
//   context.read<DatabaseHelper>()
//     └─ YieldConfigLocalStore(db)
//   context.read<SyncOutbox>()
//   YieldConfigRepository(local, outbox)
//   context.read<SyncService>()
//   YieldConfigViewModel(repository, syncService)..loadOnAppear()

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/yield_configs/data/yield_config_local_store.dart';
import 'package:pocket_pilot/src/features/yield_configs/data/yield_config_repository.dart';
import 'package:pocket_pilot/src/features/yield_configs/ui/yield_config_view_model.dart';

class YieldConfigRouteScope extends StatelessWidget {
  final Widget child;

  const YieldConfigRouteScope({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
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
      child: child,
    );
  }
}
