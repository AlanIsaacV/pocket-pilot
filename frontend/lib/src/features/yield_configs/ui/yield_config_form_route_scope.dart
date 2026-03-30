// ============================================================
// YieldConfigFormRouteScope — DI para el formulario de rendimientos
// ============================================================
//
// Árbol de dependencias:
//   context.read<DatabaseHelper>()
//     ├─ AccountLocalStore(db)
//     └─ YieldConfigLocalStore(db)
//   context.read<SyncOutbox>()
//     └─ YieldConfigRepository(local, outbox)
//   context.read<SyncService>()

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/yield_configs/data/yield_config_local_store.dart';
import 'package:pocket_pilot/src/features/yield_configs/data/yield_config_repository.dart';

class YieldConfigFormRouteScope extends StatelessWidget {
  final Widget child;

  const YieldConfigFormRouteScope({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<DatabaseHelper>();
    final outbox = context.read<SyncOutbox>();
    final syncService = context.read<SyncService>();

    final accountStore = AccountLocalStore(db: db);
    final localStore = YieldConfigLocalStore(db: db);
    final repository = YieldConfigRepository(
      local: localStore,
      outbox: outbox,
    );

    return MultiProvider(
      providers: [
        Provider.value(value: accountStore),
        Provider.value(value: repository),
        Provider.value(value: syncService),
      ],
      child: child,
    );
  }
}
