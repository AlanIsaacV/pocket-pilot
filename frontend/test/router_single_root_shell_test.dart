import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pocket_pilot/src/core/auth/auth_provider.dart';
import 'package:pocket_pilot/src/core/auth/auth_service.dart';
import 'package:pocket_pilot/src/core/auth/token_store.dart';
import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/ui/router.dart';

void main() {
  test('router keeps a single root ShellRoute', () {
    final tokenStore = TokenStore();
    final authProvider = AuthProvider(
      authService: AuthService(tokenStore: tokenStore),
      tokenStore: tokenStore,
      dbHelper: DatabaseHelper(),
    );
    final router = buildRouter(authProvider);
    final rootShellCount = router.configuration.routes
        .whereType<ShellRoute>()
        .length;

    expect(rootShellCount, 1);
  });
}
