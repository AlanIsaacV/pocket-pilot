// ============================================================
// main.dart — Bootstrap de Pocket Pilot
// ============================================================
//
// Responsabilidades:
//   1. Inicializa el binding de Flutter.
//   2. Construye el grafo de dependencias globales (DB, sync).
//   3. Provee los singletons compartidos en el árbol de widgets.
//   4. Inicia el monitoreo de conectividad para sync automático.
//
// Dependencias globales (disponibles en todo el árbol via context.read):
//   DatabaseHelper  → singleton de SQLite, compartido por todos los DAO.
//   SyncOutbox      → cola de operaciones pendientes, compartida por repos y SyncService.
//   SyncService     → orquestador de sync; ViewModels lo llaman para sincronizar.
//
// Las dependencias de cada feature (LocalStore, Repository, ViewModel) viven
// en su propio RouteScope bajo features/<feature>/ui/<feature>_route_scope.dart.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/connectivity_monitor.dart';
import 'package:pocket_pilot/src/core/sync/sync_metadata_store.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_remote_service.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_sync_handler.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/categories/data/category_remote_service.dart';
import 'package:pocket_pilot/src/features/categories/data/category_seeder.dart';
import 'package:pocket_pilot/src/features/categories/data/category_sync_handler.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_local_store.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_remote_service.dart';
import 'package:pocket_pilot/src/features/tags/data/tag_sync_handler.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_remote_service.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_sync_handler.dart';
import 'package:pocket_pilot/src/ui/app.dart';
import 'package:pocket_pilot/src/ui/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Construir grafo de dependencias de sync.
  // DatabaseHelper es un singleton interno; las instancias adicionales comparten la misma DB.
  final dbHelper = DatabaseHelper();
  final syncOutbox = SyncOutbox(db: dbHelper);
  final syncMetadataStore = SyncMetadataStore(db: dbHelper);

  // Un SyncHandler por tipo de entidad.
  // Cada handler tiene su propio LocalStore + RemoteService (independientes de los RouteScopes).
  final accountSyncHandler = AccountSyncHandler(
    local: AccountLocalStore(db: dbHelper),
    remote: AccountRemoteService(),
  );

  final categorySyncHandler = CategorySyncHandler(
    local: CategoryLocalStore(db: dbHelper),
    remote: CategoryRemoteService(),
  );

  final tagSyncHandler = TagSyncHandler(
    local: TagLocalStore(db: dbHelper),
    remote: TagRemoteService(),
  );

  final transactionSyncHandler = TransactionSyncHandler(
    local: TransactionLocalStore(db: dbHelper),
    remote: TransactionRemoteService(),
  );

  final syncService = SyncService(
    outbox: syncOutbox,
    metadataStore: syncMetadataStore,
    handlers: [
      accountSyncHandler,
      categorySyncHandler,
      tagSyncHandler,
      transactionSyncHandler,
    ],
  );

  // Insertar categorías por defecto si es la primera ejecución.
  final categorySeeder = CategorySeeder(
    local: CategoryLocalStore(db: dbHelper),
    db: dbHelper,
    outbox: syncOutbox,
  );
  await categorySeeder.seedIfNeeded();

  // ConnectivityMonitor: lanza sync automático al recuperar conexión.
  final connectivityMonitor = ConnectivityMonitor(syncService: syncService);

  runApp(
    MultiProvider(
      providers: [
        Provider<DatabaseHelper>.value(value: dbHelper),
        Provider<SyncOutbox>.value(value: syncOutbox),
        Provider<SyncService>.value(value: syncService),
      ],
      child: PocketPilotApp(router: buildRouter()),
    ),
  );

  // Iniciar monitoreo de conectividad y lanzar sync inicial si hay conexión.
  connectivityMonitor.startMonitoring();
  await connectivityMonitor.checkAndSync();
}
