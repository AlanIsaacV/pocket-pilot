import 'package:flutter/foundation.dart';

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
import 'package:pocket_pilot/src/features/notification_capture/data/pending_transaction_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/data/transaction_rule_local_store.dart';
import 'package:pocket_pilot/src/features/notification_capture/engine/parser_engine.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';

/// Minimal, UI-free composition root for capture work run by WorkManager.
///
/// It intentionally omits [ParserRemoteService], so unmatched notifications
/// never invoke the LLM from a background isolate.
class BackgroundCaptureRunner {
  final NotificationCaptureRepository _repository;

  BackgroundCaptureRunner({DatabaseHelper? dbHelper})
    : _repository = _buildRepository(dbHelper ?? DatabaseHelper());

  @visibleForTesting
  BackgroundCaptureRunner.withRepository(this._repository);

  Future<int> run() => _repository.processInbox();

  static NotificationCaptureRepository _buildRepository(DatabaseHelper db) {
    final outbox = SyncOutbox(db: db);
    return NotificationCaptureRepository(
      captured: CapturedNotificationLocalStore(db: db),
      pending: PendingTransactionLocalStore(db: db),
      parsers: ParserLocalStore(db: db),
      accounts: AccountLocalStore(db: db),
      cardMappings: AccountCardMappingLocalStore(db: db),
      rules: TransactionRuleLocalStore(db: db),
      feedback: ParserFeedbackLocalStore(db: db),
      bankAliases: BankAliasLocalStore(db: db),
      bankPackages: BankPackageLocalStore(db: db),
      transactions: TransactionRepository(
        local: TransactionLocalStore(db: db),
        outbox: outbox,
      ),
      outbox: outbox,
      engine: ParserEngine(),
      preferences: NotificationCapturePreferences(
        store: UserPreferenceLocalStore(db: db),
      ),
    );
  }
}

Future<int> runBackgroundCaptureInbox() => BackgroundCaptureRunner().run();
