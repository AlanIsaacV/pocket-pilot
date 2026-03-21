// ============================================================
// Router — go_router declarativo
// ============================================================
//
// Responsabilidad de este archivo: registrar rutas y conectar cada
// ruta con su RouteScope (que monta las dependencias de la feature).
//
// Para agregar una nueva feature:
//   1. Crear features/<name>/ui/<name>_route_scope.dart
//   2. Agregar un GoRoute aquí con su RouteScope como builder.
//
// Los RouteScope leen DatabaseHelper del contexto ancestro (provisto
// en main.dart) y construyen toda la cadena de dependencias de su
// feature en el `create` del ChangeNotifierProvider.

import 'package:go_router/go_router.dart';

import 'package:pocket_pilot/src/features/accounts/ui/accounts_route_scope.dart';
import 'package:pocket_pilot/src/features/accounts/ui/accounts_screen.dart';
import 'package:pocket_pilot/src/features/categories/ui/categories_route_scope.dart';
import 'package:pocket_pilot/src/features/categories/ui/categories_screen.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transactions_route_scope.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transactions_screen.dart';
import 'screens/home/home_screen.dart';

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/transactions',

    routes: [
      // ShellRoute: envuelve las sub-rutas en HomeScreen (NavigationBar persistente).
      ShellRoute(
        builder: (context, state, child) => HomeScreen(child: child),
        routes: [
          GoRoute(
            path: '/transactions',
            builder: (context, state) => const TransactionsRouteScope(
              child: TransactionsScreen(),
            ),
          ),
          GoRoute(
            path: '/accounts',
            builder: (context, state) => const AccountsRouteScope(
              child: AccountsScreen(),
            ),
          ),
          GoRoute(
            path: '/categories',
            builder: (context, state) => const CategoriesRouteScope(
              child: CategoriesScreen(),
            ),
          ),
        ],
      ),
    ],
  );
}
