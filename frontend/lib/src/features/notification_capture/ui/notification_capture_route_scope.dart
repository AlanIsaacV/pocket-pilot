// ============================================================
// NotificationCaptureRouteScope — DI específico del banks picker
// ============================================================
//
// Los stores compartidos del feature (CapturedNotificationLocalStore,
// PendingTransactionLocalStore, ParserLocalStore, AccountLocalStore,
// CategoryLocalStore, AccountCardMappingLocalStore, TransactionRuleLocalStore,
// ParserFeedbackLocalStore, BankAliasLocalStore, BankPackageLocalStore,
// NotificationCapturePreferences, NotificationPermissionService,
// NotificationCaptureRepository) y el PendingSuggestionsViewModel viven a
// nivel app (ver `main.dart`). Este scope solo agrega los providers que
// pertenecen al sub-árbol de `BanksPickerScreen`.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/bank_alias_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/bank_package_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/bank_package_remote_service.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/notification_capture_preferences.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/package_observation_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/watched_package_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/ui/banks_picker_view_model.dart';

class NotificationCaptureRouteScope extends StatelessWidget {
  final Widget child;

  const NotificationCaptureRouteScope({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<DatabaseHelper>();
    final outbox = context.read<SyncOutbox>();
    return MultiProvider(
      providers: [
        Provider<PackageObservationLocalStore>(
          create: (_) => PackageObservationLocalStore(db: db),
        ),
        Provider<WatchedPackageLocalStore>(
          create: (_) => WatchedPackageLocalStore(db: db),
        ),
        Provider<BankPackageRemoteService>(
          create: (_) => BankPackageRemoteService(),
        ),
        ChangeNotifierProvider<BanksPickerViewModel>(
          create: (ctx) => BanksPickerViewModel(
            observations: ctx.read<PackageObservationLocalStore>(),
            watched: ctx.read<WatchedPackageLocalStore>(),
            aliases: ctx.read<BankAliasLocalStore>(),
            bankPackages: ctx.read<BankPackageLocalStore>(),
            remote: ctx.read<BankPackageRemoteService>(),
            preferences: ctx.read<NotificationCapturePreferences>(),
            outbox: outbox,
          ),
        ),
      ],
      child: child,
    );
  }
}
