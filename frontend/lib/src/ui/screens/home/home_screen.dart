// ============================================================
// HomeScreen — Shell con NavigationBar de Material 3
// ============================================================
//
// ShellRoute de go_router envuelve las sub-rutas en este widget.
// La idea: la NavigationBar persiste mientras navegas entre tabs,
// pero cada tab tiene su propia pila de navegación.
//
// `child` es el widget de la ruta activa (TransactionsScreen,
// AccountsScreen o CategoriesScreen) que go_router inyecta.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends StatelessWidget {
  /// Widget de la ruta activa, inyectado por go_router ShellRoute.
  final Widget child;

  const HomeScreen({super.key, required this.child});

  // Mapeamos cada ruta a su índice en la NavigationBar.
  static const _routes = [
    '/transactions',
    '/accounts',
    '/categories',
  ];

  /// Determina el índice activo comparando la ruta actual con [_routes].
  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final idx = _routes.indexWhere((r) => location.startsWith(r));
    // Si no coincide ninguna (raro), muestra el primero.
    return idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // `child` ocupa todo el cuerpo — cada pantalla define su propio AppBar.
      body: child,

      // NavigationBar es el componente de Material 3 (reemplaza a BottomNavigationBar).
      // Se diferencia visualmente por tener indicadores de selección pill-shaped.
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex(context),
        onDestinationSelected: (index) {
          // go() navega a la ruta y reemplaza la pantalla actual.
          // Usamos go() en vez de push() para no apilar las tabs.
          context.go(_routes[index]);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Transacciones',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Cuentas',
          ),
          NavigationDestination(
            icon: Icon(Icons.category_outlined),
            selectedIcon: Icon(Icons.category),
            label: 'Categorías',
          ),
        ],
      ),
    );
  }
}
