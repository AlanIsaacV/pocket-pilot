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

import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/transactions/domain/transaction.dart';
import 'package:pocket_pilot/src/features/accounts/ui/account_form_screen.dart';
import 'package:pocket_pilot/src/features/accounts/ui/accounts_route_scope.dart';
import 'package:pocket_pilot/src/features/accounts/ui/accounts_screen.dart';
import 'package:pocket_pilot/src/features/goals/domain/goal.dart';
import 'package:pocket_pilot/src/features/goals/ui/goal_form_screen.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/features/categories/ui/categories_route_scope.dart';
import 'package:pocket_pilot/src/features/categories/ui/categories_screen.dart';
import 'package:pocket_pilot/src/features/categories/ui/category_form_screen.dart';
import 'package:pocket_pilot/src/features/transaction_templates/domain/transaction_template.dart';
import 'package:pocket_pilot/src/features/transaction_templates/ui/transaction_template_form_route_scope.dart';
import 'package:pocket_pilot/src/features/transaction_templates/ui/transaction_template_form_screen.dart';
import 'package:pocket_pilot/src/features/transaction_templates/ui/transaction_template_route_scope.dart';
import 'package:pocket_pilot/src/features/transaction_templates/ui/transaction_templates_screen.dart';
import 'package:pocket_pilot/src/features/transactions/ui/category_picker_screen.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transaction_form_route_scope.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transaction_form_screen.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transactions_route_scope.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transactions_screen.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transfer_form_route_scope.dart';
import 'package:pocket_pilot/src/features/transactions/ui/transfer_form_screen.dart';
import 'package:pocket_pilot/src/features/user_preferences/ui/currency_preferences_screen.dart';
import 'package:pocket_pilot/src/features/user_preferences/ui/user_preferences_route_scope.dart';
import 'package:pocket_pilot/src/features/yield_configs/domain/yield_config.dart';
import 'package:pocket_pilot/src/features/yield_configs/ui/yield_config_form_route_scope.dart';
import 'package:pocket_pilot/src/features/yield_configs/ui/yield_config_form_screen.dart';
import 'package:pocket_pilot/src/features/yield_configs/ui/yield_config_route_scope.dart';
import 'package:pocket_pilot/src/features/yield_configs/ui/yield_configs_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/settings/sync_status_screen.dart';

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
            builder: (context, state) =>
                const TransactionsRouteScope(child: TransactionsScreen()),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const TransactionFormRouteScope(
                  child: TransactionFormScreen(),
                ),
                routes: [
                  GoRoute(
                    path: 'category',
                    builder: (context, state) {
                      final extra = state.extra as Map<String, dynamic>?;
                      return TransactionFormRouteScope(
                        child: CategoryPickerScreen(
                          type: extra?['type'] as String? ?? 'expense',
                        ),
                      );
                    },
                  ),
                ],
              ),
              GoRoute(
                path: 'transfer',
                builder: (context, state) {
                  final extra = state.extra as Map<String, TransactionModel>?;
                  return TransferFormRouteScope(
                    child: TransferFormScreen(
                      transferOut: extra?['out'],
                      transferIn: extra?['in'],
                    ),
                  );
                },
              ),
              GoRoute(
                path: ':transactionId/edit',
                builder: (context, state) => TransactionFormRouteScope(
                  child: TransactionFormScreen(
                    transaction: state.extra as TransactionModel?,
                  ),
                ),
              ),
              GoRoute(
                path: ':transactionId/edit-transfer',
                builder: (context, state) {
                  final extra = state.extra as Map<String, TransactionModel>;
                  return TransferFormRouteScope(
                    child: TransferFormScreen(
                      transferOut: extra['out'],
                      transferIn: extra['in'],
                    ),
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: '/accounts',
            builder: (context, state) =>
                const AccountsRouteScope(child: AccountsScreen()),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) =>
                    const AccountsRouteScope(child: AccountFormScreen()),
              ),
              GoRoute(
                path: ':accountId/edit',
                builder: (context, state) => AccountsRouteScope(
                  child: AccountFormScreen(
                    account: state.extra as AccountModel?,
                  ),
                ),
              ),
              GoRoute(
                path: 'goals/new',
                builder: (context, state) =>
                    const AccountsRouteScope(child: GoalFormScreen()),
              ),
              GoRoute(
                path: 'goals/:goalId/edit',
                builder: (context, state) => AccountsRouteScope(
                  child: GoalFormScreen(
                    goal: state.extra as GoalModel?,
                  ),
                ),
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
        builder: (context, state) =>
            const CategoriesRouteScope(child: CategoriesScreen()),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => CategoriesRouteScope(
              child: CategoryFormScreen(parent: state.extra as CategoryModel?),
            ),
          ),
          GoRoute(
            path: ':categoryId/edit',
            builder: (context, state) => CategoriesRouteScope(
              child: CategoryFormScreen(
                category: state.extra as CategoryModel?,
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/templates',
        builder: (context, state) => const TransactionTemplateRouteScope(
          child: TransactionTemplatesScreen(),
        ),
      ),
      GoRoute(
        path: '/templates/new',
        builder: (context, state) {
          final prefill = state.extra as Map<String, dynamic>?;
          return TransactionTemplateFormRouteScope(
            child: TransactionTemplateFormScreen(prefill: prefill),
          );
        },
        routes: [
          GoRoute(
            path: 'category',
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;
              return TransactionTemplateFormRouteScope(
                child: CategoryPickerScreen(
                  type: extra?['type'] as String? ?? 'expense',
                ),
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: '/templates/:templateId/edit',
        builder: (context, state) => TransactionTemplateFormRouteScope(
          child: TransactionTemplateFormScreen(
            template: state.extra as TransactionTemplateModel?,
          ),
        ),
        routes: [
          GoRoute(
            path: 'category',
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;
              return TransactionTemplateFormRouteScope(
                child: CategoryPickerScreen(
                  type: extra?['type'] as String? ?? 'expense',
                ),
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: '/yields',
        builder: (context, state) => const YieldConfigRouteScope(
          child: YieldConfigsScreen(),
        ),
      ),
      GoRoute(
        path: '/yields/new',
        builder: (context, state) => const YieldConfigFormRouteScope(
          child: YieldConfigFormScreen(),
        ),
      ),
      GoRoute(
        path: '/yields/:yieldId/edit',
        builder: (context, state) => YieldConfigFormRouteScope(
          child: YieldConfigFormScreen(
            config: state.extra as YieldConfigModel?,
          ),
        ),
      ),
      GoRoute(
        path: '/settings/currency',
        builder: (context, state) =>
            const UserPreferencesRouteScope(child: CurrencyPreferencesScreen()),
      ),
      GoRoute(
        path: '/settings/sync',
        builder: (context, state) => const SyncStatusScreen(),
      ),
    ],
  );
}
