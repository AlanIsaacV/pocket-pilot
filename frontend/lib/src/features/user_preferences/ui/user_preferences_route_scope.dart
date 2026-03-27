import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_repository.dart';
import 'package:pocket_pilot/src/features/user_preferences/ui/user_preferences_view_model.dart';

class UserPreferencesRouteScope extends StatelessWidget {
  final Widget child;

  const UserPreferencesRouteScope({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) {
        final db = ctx.read<DatabaseHelper>();
        final outbox = ctx.read<SyncOutbox>();
        final syncService = ctx.read<SyncService>();

        final localStore = UserPreferenceLocalStore(db: db);
        final repository = UserPreferenceRepository(
          local: localStore,
          outbox: outbox,
        );

        return UserPreferencesViewModel(
          repository: repository,
          syncService: syncService,
        )..loadOnAppear();
      },
      child: child,
    );
  }
}
