import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/account_card_mapping_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/bank_alias_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/bank_package_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/captured_notification_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/notification_capture_preferences.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/notification_capture_repository.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/parser_feedback_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/parser_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/parser_remote_service.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/pending_transaction_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/transaction_rule_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/engine/parser_engine.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';

/// Builds the UI-independent dependency graph for notification capture.
///
/// The optional [parserRemote] keeps foreground LLM fallback opt-in while
/// allowing background callers to deliberately omit it. Parser assets are
/// seeded before returning so a fresh background isolate can process its
/// first inbox without waiting for a foreground launch or sync.
Future<NotificationCaptureRepository> buildCaptureRepository({
  required DatabaseHelper db,
  ParserRemoteService? parserRemote,
  SyncOutbox? outbox,
}) async {
  final parsers = ParserLocalStore(db: db);
  await parsers.seedFromAssetIfMissing(
    bankId: 'bbva_mx',
    assetPath: 'assets/parsers/bbva_mx.json',
  );

  final captureOutbox = outbox ?? SyncOutbox(db: db);
  return NotificationCaptureRepository(
    captured: CapturedNotificationLocalStore(db: db),
    pending: PendingTransactionLocalStore(db: db),
    parsers: parsers,
    accounts: AccountLocalStore(db: db),
    cardMappings: AccountCardMappingLocalStore(db: db),
    rules: TransactionRuleLocalStore(db: db),
    feedback: ParserFeedbackLocalStore(db: db),
    bankAliases: BankAliasLocalStore(db: db),
    bankPackages: BankPackageLocalStore(db: db),
    transactions: TransactionRepository(
      local: TransactionLocalStore(db: db),
      outbox: captureOutbox,
    ),
    outbox: captureOutbox,
    engine: ParserEngine(),
    parserRemote: parserRemote,
    preferences: NotificationCapturePreferences(
      store: UserPreferenceLocalStore(db: db),
    ),
  );
}
