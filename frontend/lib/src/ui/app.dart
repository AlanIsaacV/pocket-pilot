// ============================================================
// PocketPilotApp — Widget raíz de la aplicación
// ============================================================
//
// MaterialApp.router integra go_router con el sistema de navegación
// de Flutter. La diferencia con MaterialApp normal:
//   MaterialApp       → usa Navigator con rutas anónimas
//   MaterialApp.router → usa un Router declarativo (go_router) que
//                        sincroniza con la URL del sistema operativo

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/core/theme/theme_preference_controller.dart';

class PocketPilotApp extends StatelessWidget {
  /// El router se inyecta desde main.dart para facilitar el testing
  /// (en tests podemos pasar un router diferente con rutas mock).
  final GoRouter router;

  const PocketPilotApp({super.key, required this.router});

  @override
  Widget build(BuildContext context) {
    final themePreference = context.watch<ThemePreferenceController>();

    return MaterialApp.router(
      title: 'Pocket Pilot',
      debugShowCheckedModeBanner: false,

      // Tema claro y oscuro — el sistema operativo decide cuál usar
      // según la configuración del usuario.
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),

      // ThemeMode se controla por preferencia sincronizable del usuario.
      themeMode: themePreference.themeMode,

      // routerConfig le dice a MaterialApp que delegue toda la navegación
      // a nuestro GoRouter.
      routerConfig: router,
    );
  }
}
