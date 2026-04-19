import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/features/dashboard/ui/dashboard_filter_view_model.dart';
import 'package:pocket_pilot/src/features/statistics/ui/statistics_filter_view_model.dart';
import 'package:pocket_pilot/src/features/statistics/ui/statistics_tab.dart';

Widget _wrap() {
  final filter = DashboardFilterViewModel()..setCurrencyCode('MXN');
  final statsFilter = StatisticsFilterViewModel();
  return MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: filter),
        ChangeNotifierProvider.value(value: statsFilter),
      ],
      child: const Scaffold(body: StatisticsTab()),
    ),
  );
}

void main() {
  testWidgets('hub renders navigation entries + time window chips',
      (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    // Chips
    expect(find.text('3m'), findsOneWidget);
    expect(find.text('6m'), findsOneWidget);
    expect(find.text('12m'), findsOneWidget);

    // Entries
    expect(find.text('Categorías'), findsOneWidget);
    expect(find.text('Flujo'), findsOneWidget);
  });

  testWidgets('changing chip updates StatisticsFilterViewModel',
      (tester) async {
    final filter = DashboardFilterViewModel()..setCurrencyCode('MXN');
    final statsFilter = StatisticsFilterViewModel();

    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: filter),
            ChangeNotifierProvider.value(value: statsFilter),
          ],
          child: const Scaffold(body: StatisticsTab()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(statsFilter.window, 6);
    await tester.tap(find.text('12m'));
    await tester.pumpAndSettle();
    expect(statsFilter.window, 12);
  });
}
