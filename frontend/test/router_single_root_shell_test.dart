import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pocket_pilot/src/ui/router.dart';

void main() {
  test('router keeps a single root ShellRoute', () {
    final router = buildRouter();
    final rootShellCount = router.configuration.routes
        .whereType<ShellRoute>()
        .length;

    expect(rootShellCount, 1);
  });
}
