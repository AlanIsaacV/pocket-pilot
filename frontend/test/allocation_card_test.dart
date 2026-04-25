import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/features/dashboard/domain/dashboard_metrics.dart';
import 'package:pocket_pilot/src/features/dashboard/ui/widgets/allocation_card.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 400, height: 400, child: child),
    ),
  );
}

DashboardMetrics _metrics({
  String currency = 'USD',
  int liquid = 0,
  int marketValue = 0,
  int yields = 0,
  int debt = 0,
  int revolving = 0,
}) {
  return DashboardMetrics(
    currencyCode: currency,
    netWorthCents: liquid + marketValue,
    liquidAssetsCents: liquid,
    safeToSpendCents: 0,
    buyingPowerCents: liquid + revolving,
    marketValueOfHoldingsCents: marketValue,
    yieldsValueCents: yields,
    debtCents: debt,
    revolvingCreditCents: revolving,
  );
}

void main() {
  group('AllocationCard', () {
    testWidgets('renders 3 segments when all buckets > 0', (tester) async {
      // 30k liquid total, 10k yields → free liquid 20k.
      // 50k stocks. 10k yields. Total = 80k.
      final metrics = _metrics(
        liquid: 3000000,
        marketValue: 5000000,
        yields: 1000000,
      );
      await tester.pumpWidget(_wrap(AllocationCard(metrics: metrics)));

      expect(find.text('Composición'), findsOneWidget);
      // Tres legends visibles
      expect(find.textContaining('Líquido'), findsOneWidget);
      expect(find.textContaining('Stocks'), findsOneWidget);
      expect(find.textContaining('Rend'), findsOneWidget);

      // 3 Expanded segments dentro del bar
      final expandedFinder = find.descendant(
        of: find.byType(ClipRRect),
        matching: find.byType(Expanded),
      );
      expect(expandedFinder, findsNWidgets(3));

      final flexes = tester
          .widgetList<Expanded>(expandedFinder)
          .map((e) => e.flex)
          .toList();
      // Líquido $20k / total $80k = 25%, Stocks 62.5%, Rend 12.5% — flex×1000.
      expect(flexes[0], 250);
      expect(flexes[1], 625);
      expect(flexes[2], 125);
    });

    testWidgets('renders 1 segment at 100% when only liquid > 0',
        (tester) async {
      final metrics = _metrics(liquid: 100000);
      await tester.pumpWidget(_wrap(AllocationCard(metrics: metrics)));

      final expandedFinder = find.descendant(
        of: find.byType(ClipRRect),
        matching: find.byType(Expanded),
      );
      expect(expandedFinder, findsNWidgets(1));
      expect(find.textContaining('100%'), findsOneWidget);
      expect(find.textContaining('Líquido'), findsOneWidget);
      expect(find.textContaining('Stocks'), findsNothing);
    });

    testWidgets('renders nothing when all buckets are 0', (tester) async {
      final metrics = _metrics();
      await tester.pumpWidget(_wrap(AllocationCard(metrics: metrics)));

      expect(find.text('Composición'), findsNothing);
      expect(find.byType(ClipRRect), findsNothing);
    });

    testWidgets('shows debt and revolving chips only when > 0', (tester) async {
      final metrics = _metrics(
        liquid: 50000,
        debt: 30000,
        revolving: 70000,
      );
      await tester.pumpWidget(_wrap(AllocationCard(metrics: metrics)));

      expect(find.textContaining('Deuda actual'), findsOneWidget);
      expect(find.textContaining('Crédito disp'), findsOneWidget);
    });

    testWidgets('hides debt chip when debt is 0', (tester) async {
      final metrics = _metrics(liquid: 50000, revolving: 70000);
      await tester.pumpWidget(_wrap(AllocationCard(metrics: metrics)));

      expect(find.textContaining('Deuda actual'), findsNothing);
      expect(find.textContaining('Crédito disp'), findsOneWidget);
    });

    testWidgets('subtracts yields from liquid bucket to avoid double counting',
        (tester) async {
      // liquid total 100k, yields 60k → free liquid 40k, yields 60k.
      // Sin stocks. Total = 100k. Líquido bar = 40%, Rend = 60%.
      final metrics = _metrics(liquid: 10000000, yields: 6000000);
      await tester.pumpWidget(_wrap(AllocationCard(metrics: metrics)));

      final expandedFinder = find.descendant(
        of: find.byType(ClipRRect),
        matching: find.byType(Expanded),
      );
      expect(expandedFinder, findsNWidgets(2));

      final flexes = tester
          .widgetList<Expanded>(expandedFinder)
          .map((e) => e.flex)
          .toList();
      expect(flexes[0], 400); // free liquid
      expect(flexes[1], 600); // yields
    });
  });
}
