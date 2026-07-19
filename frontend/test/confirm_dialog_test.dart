import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/ui/widgets/confirm_dialog.dart';

void main() {
  testWidgets('returns false when the confirmation is cancelled', (
    tester,
  ) async {
    var confirmed = true;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                confirmed = await showConfirmDialog(
                  context,
                  title: 'Eliminar cuenta',
                  message: 'Esta acción no se puede deshacer.',
                  confirmLabel: 'Eliminar',
                  destructive: true,
                );
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Eliminar cuenta'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(confirmed, isFalse);
  });
}
