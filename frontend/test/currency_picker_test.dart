import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/db/database_helper.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/currency_preferences_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/data/user_preference_local_store.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences.dart';
import 'package:pocket_pilot/src/ui/widgets/currency_picker.dart';
import 'package:pocket_pilot/src/ui/widgets/form_widgets.dart';

void main() {
  testWidgets('shows sorted retained codes and returns the selected code', (
    tester,
  ) async {
    String? result;

    await tester.pumpWidget(
      Provider<CurrencyPreferencesLocalStore>.value(
        value: _FakeCurrencyPreferencesStore(
          const CurrencyPreferencesSnapshot(
            allowedCodes: ['USD'],
            defaultCode: 'USD',
          ),
        ),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showCurrencyPicker(
                    context,
                    selectedCode: 'EUR',
                    mustIncludeCode: 'MXN',
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Moneda'), findsOneWidget);
    expect(find.text('Configurar monedas'), findsOneWidget);
    expect(find.text('MXN — Peso Mexicano'), findsOneWidget);
    expect(find.text('USD — US Dollar'), findsOneWidget);
    expect(find.text('EUR — Euro'), findsOneWidget);
    expect(
      find
          .byType(SheetItem)
          .evaluate()
          .map((element) => (element.widget as SheetItem).label),
      [
        'Configurar monedas',
        'MXN — Peso Mexicano',
        'USD — US Dollar',
        'EUR — Euro',
      ],
    );

    await tester.tap(find.text('EUR — Euro'));
    await tester.pumpAndSettle();

    expect(result, 'EUR');
  });

  testWidgets('falls back when preferences remove the selected currency', (
    tester,
  ) async {
    final store = _FakeCurrencyPreferencesStore(
      const CurrencyPreferencesSnapshot(
        allowedCodes: ['EUR', 'USD'],
        defaultCode: 'USD',
      ),
    );
    String? result;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showCurrencyPicker(
                    context,
                    selectedCode: 'EUR',
                    mustIncludeCode: 'MXN',
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/settings/currency',
          builder: (context, _) => Scaffold(
            body: ElevatedButton(
              onPressed: () {
                store.snapshot = const CurrencyPreferencesSnapshot(
                  allowedCodes: ['USD'],
                  defaultCode: 'USD',
                );
                context.pop(true);
              },
              child: const Text('Volver'),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      Provider<CurrencyPreferencesLocalStore>.value(
        value: store,
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configurar monedas'));
    await tester.pumpAndSettle();
    expect(find.text('Volver'), findsOneWidget);

    await tester.tap(find.text('Volver'));
    await tester.pumpAndSettle();

    expect(result, 'MXN');
    expect(find.text('Moneda'), findsNothing);
  });
}

class _FakeCurrencyPreferencesStore extends CurrencyPreferencesLocalStore {
  CurrencyPreferencesSnapshot snapshot;

  _FakeCurrencyPreferencesStore(this.snapshot)
    : super(preferences: UserPreferenceLocalStore(db: DatabaseHelper()));

  @override
  Future<CurrencyPreferencesSnapshot> getSnapshot() async => snapshot;
}
