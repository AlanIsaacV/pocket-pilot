import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/features/statistics/ui/widgets/stat_delta_row.dart';

void main() {
  testWidgets('shows promedio, este mes, and delta %', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatDeltaRow(
            currency: 'MXN',
            avgCents: 400000,
            currentCents: 340000,
            kind: 'expense',
          ),
        ),
      ),
    );

    expect(find.text('Promedio'), findsOneWidget);
    expect(find.text('Este mes'), findsOneWidget);
    expect(find.textContaining('4,000'), findsOneWidget);
    expect(find.textContaining('3,400'), findsOneWidget);
    expect(find.textContaining('-15%'), findsOneWidget);
  });
}
