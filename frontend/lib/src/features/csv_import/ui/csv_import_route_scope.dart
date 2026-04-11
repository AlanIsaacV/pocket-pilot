import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/csv_import/data/csv_import_local_store.dart';
import 'package:pocket_pilot/src/features/csv_import/data/csv_import_repository.dart';
import 'package:pocket_pilot/src/features/csv_import/data/csv_import_service.dart';
import 'package:pocket_pilot/src/features/csv_import/ui/csv_import_view_model.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_repository.dart';
import 'package:pocket_pilot/src/features/categories/data/category_repository.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_repository.dart';

class CsvImportRouteScope extends StatelessWidget {
  final Widget child;
  const CsvImportRouteScope({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) {
        final db = ctx.read<DatabaseHelper>();
        final outbox = ctx.read<SyncOutbox>();
        final accountStore = AccountLocalStore(db: db);
        final categoryStore = CategoryLocalStore(db: db);
        final tagStore = TagLocalStore(db: db);
        final service = CsvImportService(uuid: const Uuid());
        final localStore = CsvImportLocalStore(db: db);
        final repository = CsvImportRepository(local: localStore);
        final tagRepository = TagRepository(local: tagStore, outbox: outbox);
        final accountRepository = AccountRepository(local: accountStore, outbox: outbox);
        final categoryRepository = CategoryRepository(local: categoryStore, outbox: outbox);

        return CsvImportViewModel(
          service: service,
          repository: repository,
          accountStore: accountStore,
          categoryStore: categoryStore,
          tagStore: tagStore,
          tagRepository: tagRepository,
          accountRepository: accountRepository,
          categoryRepository: categoryRepository,
        );
      },
      child: child,
    );
  }
}
