// ============================================================
// TransactionTemplateRouteScope — DI para la lista de plantillas
// ============================================================
//
// Árbol de dependencias:
//   context.read<DatabaseHelper>()
//     └─ TransactionTemplateLocalStore(db)
//   context.read<SyncOutbox>()
//   TransactionTemplateRepository(local, outbox)
//   context.read<SyncService>()
//   TransactionTemplateViewModel(repository, syncService)..loadOnAppear()

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/transaction_templates/data/transaction_template_local_store.dart';
import 'package:pocket_pilot/src/features/transaction_templates/data/transaction_template_repository.dart';
import 'package:pocket_pilot/src/features/transaction_templates/ui/transaction_template_view_model.dart';

class TransactionTemplateRouteScope extends StatelessWidget {
  final Widget child;

  const TransactionTemplateRouteScope({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
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
      child: child,
    );
  }
}
