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
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/auth/auth_provider.dart';
import 'package:pocket_pilot/src/ui/screens/login/login_screen.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/accounts/domain/account.dart';
import 'package:pocket_pilot/src/features/categories/data/category_local_store.dart';
import 'package:pocket_pilot/src/features/transactions/domain/transaction.dart';
import 'package:pocket_pilot/src/features/accounts/ui/account_form_screen.dart';
import 'package:pocket_pilot/src/features/accounts/ui/accounts_route_scope.dart';
import 'package:pocket_pilot/src/features/accounts/ui/accounts_screen.dart';
import 'package:pocket_pilot/src/features/budgets/domain/budget.dart';
import 'package:pocket_pilot/src/features/budgets/ui/budget_form_screen.dart';
import 'package:pocket_pilot/src/features/debts/domain/contact_balance.dart';
import 'package:pocket_pilot/src/features/debts/ui/debt_detail_screen.dart';
import 'package:pocket_pilot/src/features/debts/ui/debt_form_screen.dart';
import 'package:pocket_pilot/src/features/goals/domain/goal.dart';
import 'package:pocket_pilot/src/features/goals/ui/goal_form_screen.dart';
import 'package:pocket_pilot/src/features/categories/domain/category.dart';
import 'package:pocket_pilot/src/features/categories/ui/categories_route_scope.dart';
import 'package:pocket_pilot/src/features/categories/ui/categories_screen.dart';
import 'package:pocket_pilot/src/features/categories/ui/category_form_screen.dart';
import 'package:pocket_pilot/src/features/transaction_templates/domain/transaction_template.dart';
import 'package:pocket_pilot/src/features/transaction_templates/ui/transaction_template_form_route_scope.dart';
import 'package:pocket_pilot/src/features/transaction_templates/ui/transaction_template_form_screen.dart';
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
import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_route_scope.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'package:pocket_pilot/src/features/csv_import/ui/csv_import_route_scope.dart';
import 'package:pocket_pilot/src/features/csv_import/ui/csv_import_screen.dart';
import 'package:pocket_pilot/src/features/csv_import/ui/csv_mapping_screen.dart';
import 'screens/notifications/notifications_screen.dart';
import 'screens/settings/sync_status_screen.dart';

GoRouter buildRouter(AuthProvider authProvider) {
  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: authProvider,
    redirect: (context, state) {
      final isLoggedIn = authProvider.isAuthenticated;
      final isOnLogin = state.matchedLocation == '/login';

      if (!isLoggedIn && !isOnLogin) return '/login';
      if (isLoggedIn && isOnLogin) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      // ----------------------------------------------------------
      // ShellRoute: tabs con NavigationBar persistente
      // ----------------------------------------------------------
      ShellRoute(
        builder: (context, state, child) => HomeScreen(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) =>
                const DashboardRouteScope(child: DashboardScreen()),
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
              // --- Plantillas (antes en /templates) ---
              GoRoute(
                path: 'templates/new',
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
                path: 'templates/:templateId/edit',
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
              // --- Rendimientos (antes en /yields) ---
              GoRoute(
                path: 'yields/new',
                builder: (context, state) =>
                    const YieldConfigFormRouteScope(child: YieldConfigFormScreen()),
              ),
              GoRoute(
                path: 'yields/:yieldId/edit',
                builder: (context, state) => YieldConfigFormRouteScope(
                  child: YieldConfigFormScreen(
                    config: state.extra as YieldConfigModel?,
                  ),
                ),
              ),
              // --- Deudas (antes en /accounts/debts) ---
              GoRoute(
                path: 'debts/new',
                builder: (context, state) {
                  ContactBalance? contact;
                  TransactionModel? transferOut;
                  TransactionModel? transferIn;

                  final extra = state.extra;
                  if (extra is ContactBalance) {
                    contact = extra;
                  } else if (extra is Map<String, dynamic>) {
                    contact = extra['contact'] as ContactBalance?;
                    transferOut = extra['out'] as TransactionModel?;
                    transferIn = extra['in'] as TransactionModel?;
                  }

                  return TransactionsRouteScope(
                    child: DebtFormScreen(
                      contact: contact,
                      transferOut: transferOut,
                      transferIn: transferIn,
                    ),
                  );
                },
              ),
              GoRoute(
                path: 'debts/:accountId',
                builder: (context, state) => TransactionsRouteScope(
                  child: DebtDetailScreen(
                    accountId: state.pathParameters['accountId']!,
                    initialContact: state.extra as ContactBalance?,
                  ),
                ),
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
                builder: (context, state) => AccountsRouteScope(
                  child: AccountFormScreen(
                    initialName: state.extra is String
                        ? state.extra as String
                        : null,
                  ),
                ),
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
                  child: GoalFormScreen(goal: state.extra as GoalModel?),
                ),
              ),
              GoRoute(
                path: 'budgets/new',
                builder: (context, state) =>
                    const AccountsRouteScope(child: BudgetFormScreen()),
                routes: [
                  GoRoute(
                    path: 'category',
                    builder: (context, state) {
                      final extra = state.extra as Map<String, dynamic>?;
                      final db = DatabaseHelper();
                      return Provider<CategoryLocalStore>(
                        create: (_) => CategoryLocalStore(db: db),
                        child: CategoryPickerScreen(
                          type: extra?['type'] as String? ?? 'expense',
                        ),
                      );
                    },
                  ),
                ],
              ),
              GoRoute(
                path: 'budgets/:budgetId/edit',
                builder: (context, state) => AccountsRouteScope(
                  child: BudgetFormScreen(
                    budget: state.extra as BudgetModel?,
                    categoryRoute:
                        '/accounts/budgets/${state.pathParameters['budgetId']}/edit/category',
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'category',
                    builder: (context, state) {
                      final extra = state.extra as Map<String, dynamic>?;
                      final db = DatabaseHelper();
                      return Provider<CategoryLocalStore>(
                        create: (_) => CategoryLocalStore(db: db),
                        child: CategoryPickerScreen(
                          type: extra?['type'] as String? ?? 'expense',
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          // CSV Import (Settings) — nested shell para compartir ViewModel
          // sin crear un segundo shell de nivel raíz.
          ShellRoute(
            builder: (context, state, child) =>
                CsvImportRouteScope(child: child),
            routes: [
              GoRoute(
                path: '/settings/csv-import',
                builder: (context, state) => const CsvImportScreen(),
                routes: [
                  GoRoute(
                    path: 'mapping',
                    builder: (context, state) => const CsvMappingScreen(),
                  ),
                ],
              ),
            ],
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
            builder: (context, state) {
              final extra = state.extra;
              CategoryModel? parent;
              String? initialName;
              if (extra is CategoryModel) {
                parent = extra;
              } else if (extra is Map<String, dynamic>) {
                parent = extra['parent'] as CategoryModel?;
                initialName = extra['initialName'] as String?;
              }
              return CategoriesRouteScope(
                child: CategoryFormScreen(
                  parent: parent,
                  initialName: initialName,
                ),
              );
            },
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
      // Templates y Yields movidos bajo /transactions como child routes
      GoRoute(
        path: '/settings/currency',
        builder: (context, state) =>
            const UserPreferencesRouteScope(child: CurrencyPreferencesScreen()),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/settings/sync',
        builder: (context, state) => const SyncStatusScreen(),
      ),
    ],
  );
}
