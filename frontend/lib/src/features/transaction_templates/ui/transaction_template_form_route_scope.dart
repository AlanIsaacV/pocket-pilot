// ============================================================
// TransactionTemplateFormRouteScope — DI para el formulario de plantillas
// ============================================================
//
// Árbol de dependencias:
//   context.read<DatabaseHelper>()
//     ├─ AccountLocalStore(db)
//     ├─ CategoryLocalStore(db)
//     ├─ TagLocalStore(db)
//     └─ TransactionTemplateLocalStore(db)
//   context.read<SyncOutbox>()
//     ├─ TagRepository(local, outbox)
//     └─ TransactionTemplateRepository(local, outbox)
//   context.read<SyncService>()

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_local_store.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_repository.dart';
import 'package:pocket_pilot/src/features/transaction_templates/data/transaction_template_local_store.dart';
import 'package:pocket_pilot/src/features/transaction_templates/data/transaction_template_repository.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/currency_preferences_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';

class TransactionTemplateFormRouteScope extends StatelessWidget {
  final Widget child;

  const TransactionTemplateFormRouteScope({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<DatabaseHelper>();
    final outbox = context.read<SyncOutbox>();
    final syncService = context.read<SyncService>();

    final accountStore = AccountLocalStore(db: db);
    final categoryStore = CategoryLocalStore(db: db);
    final tagStore = TagLocalStore(db: db);
    final userPreferenceStore = UserPreferenceLocalStore(db: db);
    final currencyPreferencesStore = CurrencyPreferencesLocalStore(
      preferences: userPreferenceStore,
    );
    final tagRepository = TagRepository(local: tagStore, outbox: outbox);
    final templateLocalStore = TransactionTemplateLocalStore(db: db);
    final templateRepository = TransactionTemplateRepository(
      local: templateLocalStore,
      outbox: outbox,
    );

    return MultiProvider(
      providers: [
        Provider.value(value: accountStore),
        Provider.value(value: categoryStore),
        Provider.value(value: tagStore),
        Provider.value(value: tagRepository),
        Provider.value(value: currencyPreferencesStore),
        Provider.value(value: templateRepository),
        Provider.value(value: syncService),
      ],
      child: child,
    );
  }
}
