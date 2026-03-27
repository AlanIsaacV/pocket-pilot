// ============================================================
// TransferFormRouteScope — DI para el formulario de transferencia
// ============================================================
//
// Similar a TransactionFormRouteScope pero sin CategoryLocalStore,
// ya que las transferencias no tienen categoría.

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_local_store.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_repository.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/currency_preferences_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';

class TransferFormRouteScope extends StatelessWidget {
  final Widget child;

  const TransferFormRouteScope({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<DatabaseHelper>();
    final outbox = context.read<SyncOutbox>();
    final syncService = context.read<SyncService>();

    final accountStore = AccountLocalStore(db: db);
    final tagStore = TagLocalStore(db: db);
    final userPreferenceStore = UserPreferenceLocalStore(db: db);
    final currencyPreferencesStore = CurrencyPreferencesLocalStore(
      preferences: userPreferenceStore,
    );
    final tagRepository = TagRepository(local: tagStore, outbox: outbox);
    final transactionLocalStore = TransactionLocalStore(db: db);
    final transactionRepository = TransactionRepository(
      local: transactionLocalStore,
      outbox: outbox,
    );

    return MultiProvider(
      providers: [
        Provider.value(value: accountStore),
        Provider.value(value: tagStore),
        Provider.value(value: tagRepository),
        Provider.value(value: currencyPreferencesStore),
        Provider.value(value: transactionRepository),
        Provider.value(value: syncService),
      ],
      child: child,
    );
  }
}
