// ============================================================
// main.dart — Bootstrap de Pocket Pilot
// ============================================================
//
// Este archivo solo hace tres cosas:
//   1. Inicializa el binding de Flutter.
//   2. Provee DatabaseHelper como singleton global en el árbol de widgets.
//   3. Arranca la app con el router.
//
// El grafo de dependencias de cada feature (LocalStore, RemoteService,
// Repository, ViewModel) vive en su propio RouteScope bajo
// features/<feature>/ui/<feature>_route_scope.dart.
// Cada RouteScope lee DatabaseHelper del contexto y construye
// lo que necesita en el `create` de su ChangeNotifierProvider.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/ui/app.dart';
import 'package:pocket_pilot/src/ui/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    // Provider<DatabaseHelper> en la raíz: singleton compartido por todos
    // los RouteScopes. GrpcClient.channel también es un singleton estático;
    // los *RemoteService lo usan directamente sin necesitar un Provider.
    Provider<DatabaseHelper>.value(
      value: DatabaseHelper(),
      child: PocketPilotApp(router: buildRouter()),
    ),
  );
}
