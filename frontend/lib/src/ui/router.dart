// ============================================================
// Router — go_router declarativo
// ============================================================
//
// Estructura de rutas:
//   ShellRoute (HomeScreen con NavigationBar) → 4 tabs:
//     /dashboard       → DashboardScreen
//     /transactions    → TransactionsScreen
//       /new           → TransactionFormScreen
//     /accounts        → AccountsScreen
//       /new           → AccountFormScreen
//     /settings        → SettingsScreen
//
//   Rutas sin tab (fuera del shell):
//     /categories      → CategoriesRouteScope + CategoriesScreen
//       /new           → CategoryFormScreen
//
// Para agregar una nueva feature con tab:
//   1. Crear features/<name>/ui/<name>_route_scope.dart
//   2. Agregar GoRoute en el ShellRoute
//   3. Agregar destino en HomeScreen._routes

import 'package:go_router/go_router.dart';

import 'package:pocket_pilot/src/features/accounts/ui/account_form_screen.dart';
import 'package:pocket_pilot/src/features/accounts/ui/accounts_route_scope.dart';
import 'package:pocket_pilot/src/features/accounts/ui/accounts_screen.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/features/categories/ui/categories_route_scope.dart';
import 'package:pocket_pilot/src/features/categories/ui/categories_screen.dart';
import 'package:pocket_pilot/src/features/categories/ui/category_form_screen.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transaction_form_screen.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transactions_route_scope.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transactions_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/settings/settings_screen.dart';

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/dashboard',

    routes: [
      // ----------------------------------------------------------
      // ShellRoute: tabs con NavigationBar persistente
      // ----------------------------------------------------------
      ShellRoute(
        builder: (context, state, child) => HomeScreen(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/transactions',
            builder: (context, state) => const TransactionsRouteScope(
              child: TransactionsScreen(),
            ),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const TransactionFormScreen(),
              ),
            ],
          ),
          GoRoute(
            path: '/accounts',
            builder: (context, state) => const AccountsRouteScope(
              child: AccountsScreen(),
            ),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const AccountFormScreen(),
              ),
            ],
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),

      // ----------------------------------------------------------
      // Rutas fuera del shell (sin NavigationBar)
      // Categorías se accede desde el formulario de transacciones.
      // ----------------------------------------------------------
      GoRoute(
        path: '/categories',
        builder: (context, state) => const CategoriesRouteScope(
          child: CategoriesScreen(),
        ),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => CategoryFormScreen(
              parent: state.extra as CategoryModel?,
            ),
          ),
        ],
      ),
    ],
  );
}
