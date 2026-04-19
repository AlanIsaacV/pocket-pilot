import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_filter_view_model.dart';
import 'package:pocket_pilot/src/features/statistics/ui/statistics_tab.dart';

Widget _wrap() {
  final filter = DashboardFilterViewModel()..setCurrencyCode('MXN');
  return MaterialApp(
    home: ChangeNotifierProvider.value(
      value: filter,
      child: const Scaffold(body: StatisticsTab()),
    ),
  );
}

void main() {
  testWidgets('hub renders navigation entries', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(find.text('Categorías'), findsOneWidget);
    expect(find.text('Flujo'), findsOneWidget);
  });
}
