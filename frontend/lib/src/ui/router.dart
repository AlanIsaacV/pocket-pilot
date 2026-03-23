// ============================================================
// Router — go_router declarativo
// ============================================================
//
// Para agregar una nueva feature:
//   1. Crear features/<name>/ui/<name>_route_scope.dart
//   2. Agregar un GoRoute aquí con su RouteScope como builder.

import 'package:go_router/go_router.dart';

import 'package:pocket_pilot/src/features/accounts/ui/account_form_screen.dart';
import 'package:pocket_pilot/src/features/accounts/ui/accounts_route_scope.dart';
import 'package:pocket_pilot/src/features/accounts/ui/accounts_screen.dart';
import 'package:pocket_pilot/src/features/categories/ui/categories_route_scope.dart';
import 'package:pocket_pilot/src/features/categories/ui/categories_screen.dart';
import 'package:pocket_pilot/src/features/categories/ui/category_form_screen.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transaction_form_screen.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transactions_route_scope.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transactions_screen.dart';
import 'screens/home/home_screen.dart';

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/transactions',

    routes: [
      ShellRoute(
        builder: (context, state, child) => HomeScreen(child: child),
        routes: [
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
            path: '/categories',
            builder: (context, state) => const CategoriesRouteScope(
              child: CategoriesScreen(),
            ),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const CategoryFormScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
