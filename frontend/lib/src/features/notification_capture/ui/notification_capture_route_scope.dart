// ============================================================
// NotificationCaptureRouteScope — DI para la feature
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/account_card_mapping_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/bank_alias_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/bank_package_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/bank_package_remote_service.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/captured_notification_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/notification_capture_preferences.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/notification_capture_repository.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/notification_permission_service.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/package_observation_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/parser_feedback_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/parser_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/parser_remote_service.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/pending_transaction_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/transaction_rule_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/watched_package_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/ui/banks_picker_view_model.dart';
import 'package:pocket_pilot/src/features/notification_capture/ui/notification_inbox_view_model.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';

class NotificationCaptureRouteScope extends StatelessWidget {
  final Widget child;

  const NotificationCaptureRouteScope({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<DatabaseHelper>();
    final outbox = context.read<SyncOutbox>();
    return MultiProvider(
      providers: [
        Provider<CapturedNotificationLocalStore>(
          create: (_) => CapturedNotificationLocalStore(db: db),
        ),
        Provider<PendingTransactionLocalStore>(
          create: (_) => PendingTransactionLocalStore(db: db),
        ),
        Provider<ParserLocalStore>(
          create: (_) => ParserLocalStore(db: db),
        ),
        Provider<AccountLocalStore>(
          create: (_) => AccountLocalStore(db: db),
        ),
        Provider<CategoryLocalStore>(
          create: (_) => CategoryLocalStore(db: db),
        ),
        Provider<AccountCardMappingLocalStore>(
          create: (_) => AccountCardMappingLocalStore(db: db),
        ),
        Provider<TransactionRuleLocalStore>(
          create: (_) => TransactionRuleLocalStore(db: db),
        ),
        Provider<ParserFeedbackLocalStore>(
          create: (_) => ParserFeedbackLocalStore(db: db),
        ),
        // Fase 8 ─────────────────────────────────────────────────────────
        Provider<PackageObservationLocalStore>(
          create: (_) => PackageObservationLocalStore(db: db),
        ),
        Provider<WatchedPackageLocalStore>(
          create: (_) => WatchedPackageLocalStore(db: db),
        ),
        Provider<BankAliasLocalStore>(
          create: (_) => BankAliasLocalStore(db: db),
        ),
        Provider<BankPackageLocalStore>(
          create: (_) => BankPackageLocalStore(db: db),
        ),
        Provider<BankPackageRemoteService>(
          create: (_) => BankPackageRemoteService(),
        ),
        // ────────────────────────────────────────────────────────────────
        Provider<TransactionRepository>(
          create: (_) => TransactionRepository(
            local: TransactionLocalStore(db: db),
            outbox: outbox,
          ),
        ),
        Provider<ParserRemoteService>(
          create: (_) => ParserRemoteService(),
        ),
        Provider<NotificationCapturePreferences>(
          create: (_) => NotificationCapturePreferences(
            store: UserPreferenceLocalStore(db: db),
          ),
        ),
        Provider<NotificationCaptureRepository>(
          create: (ctx) => NotificationCaptureRepository(
            captured: ctx.read<CapturedNotificationLocalStore>(),
            pending: ctx.read<PendingTransactionLocalStore>(),
            parsers: ctx.read<ParserLocalStore>(),
            accounts: ctx.read<AccountLocalStore>(),
            cardMappings: ctx.read<AccountCardMappingLocalStore>(),
            rules: ctx.read<TransactionRuleLocalStore>(),
            feedback: ctx.read<ParserFeedbackLocalStore>(),
            bankAliases: ctx.read<BankAliasLocalStore>(),
            bankPackages: ctx.read<BankPackageLocalStore>(),
            transactions: ctx.read<TransactionRepository>(),
            outbox: outbox,
            parserRemote: ctx.read<ParserRemoteService>(),
            preferences: ctx.read<NotificationCapturePreferences>(),
          ),
        ),
        Provider<NotificationPermissionService>(
          create: (_) => NotificationPermissionService(),
        ),
        ChangeNotifierProvider<NotificationInboxViewModel>(
          create: (ctx) {
            final parsers = ctx.read<ParserLocalStore>();
            // Seed asset es fire-and-forget; el engine lo recoge en la
            // siguiente refresh.
            parsers.seedFromAssetIfMissing(
              bankId: 'bbva_mx',
              assetPath: 'assets/parsers/bbva_mx.json',
            );
            return NotificationInboxViewModel(
              captured: ctx.read<CapturedNotificationLocalStore>(),
              pending: ctx.read<PendingTransactionLocalStore>(),
              repository: ctx.read<NotificationCaptureRepository>(),
              permission: ctx.read<NotificationPermissionService>(),
            )..loadOnAppear();
          },
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
