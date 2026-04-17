import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/features/statistics/domain/category_series_dto.dart';
import 'package:pocket_pilot/src/features/statistics/domain/trend.dart';
import 'package:pocket_pilot/src/features/statistics/ui/widgets/category_list_row.dart';

void main() {
  testWidgets(
    'renders name, current month amount, avg, and up arrow for Trend.up',
    (tester) async {
      const item = CategorySeriesDTO(
        categoryId: 'c1',
        name: 'Comida',
        color: '#A6E3A1',
        icon: 'restaurant',
        kind: 'expense',
        currencyCode: 'MXN',
        totalCents: 600000,
        avgMonthlyCents: 100000,
        currentMonthCents: 120000,
        trend: Trend.up,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CategoryListRow(item: item, windowMonths: 6, onTap: () {}),
          ),
        ),
      );

      expect(find.text('Comida'), findsOneWidget);
      expect(find.textContaining('1,200'), findsOneWidget); // current month
      expect(find.textContaining('prom'), findsOneWidget);
      expect(find.byIcon(Icons.trending_up), findsOneWidget);
    },
  );
}
