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

import 'package:pocket_pilot/src/core/constants/constants.dart';
import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/core/sync/connectivity_monitor.dart';
import 'package:pocket_pilot/src/core/sync/sync_metadata_store.dart';
import 'package:pocket_pilot/src/core/sync/sync_outbox.dart';
import 'package:pocket_pilot/src/core/sync/sync_service.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_local_store.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_remote_service.dart';
import 'package:pocket_pilot/src/features/accounts/data/account_sync_handler.dart';
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

  final syncService = SyncService(
    outbox: syncOutbox,
    metadataStore: syncMetadataStore,
    handlers: [accountSyncHandler],
  );

  // ConnectivityMonitor: lanza sync automático al recuperar conexión.
  final connectivityMonitor = ConnectivityMonitor(
    syncService: syncService,
    userId: kHardcodedUserId,
  );

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
