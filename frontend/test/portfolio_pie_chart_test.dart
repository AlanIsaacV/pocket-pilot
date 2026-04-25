import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/src/features/investments/domain/portfolio_distribution.dart';
import 'package:pocket_pilot/src/features/investments/ui/widgets/portfolio_pie_chart.dart';

PortfolioSlice makeSlice({
  String holdingId = 'h1',
  String symbol = 'AAPL',
  String displayName = 'Apple Inc.',
  String currencyCode = 'USD',
  double marketValue = 1000,
  double percentage = 1.0,
}) {
  return (
    holdingId: holdingId,
    symbol: symbol,
    displayName: displayName,
    currencyCode: currencyCode,
    marketValue: marketValue,
    percentage: percentage,
  );
}

Widget wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 400,
        height: 700,
        child: child,
      ),
    ),
  );
}

void main() {
  group('PortfolioPieChart', () {
    testWidgets('shows placeholder when distribution is empty',
        (tester) async {
      await tester.pumpWidget(wrap(const PortfolioPieChart(distribution: {})));
      expect(find.text('Sin datos para graficar'), findsOneWidget);
      expect(find.byType(PieChart), findsNothing);
    });

    testWidgets('renders one pie and header for a single currency',
        (tester) async {
      final distribution = {
        'USD': [
          makeSlice(symbol: 'AAPL', marketValue: 3000, percentage: 0.75),
          makeSlice(
            holdingId: 'h2',
            symbol: 'MSFT',
            marketValue: 1000,
            percentage: 0.25,
          ),
        ],
      };
      await tester.pumpWidget(
        wrap(PortfolioPieChart(distribution: distribution)),
      );

      expect(find.byType(PieChart), findsOneWidget);
      expect(find.text('Portafolio USD'), findsOneWidget);
      expect(find.textContaining('AAPL'), findsOneWidget);
      expect(find.textContaining('MSFT'), findsOneWidget);
      expect(find.textContaining('75.0%'), findsOneWidget);
      expect(find.textContaining('25.0%'), findsOneWidget);
    });

    testWidgets('renders a pie per currency in alphabetical order',
        (tester) async {
      final distribution = {
        'USD': [makeSlice(symbol: 'AAPL', percentage: 1.0)],
        'MXN': [
          makeSlice(
            holdingId: 'h3',
            symbol: 'AMXL',
            currencyCode: 'MXN',
            marketValue: 2000,
            percentage: 1.0,
          ),
        ],
      };
      await tester.pumpWidget(
        wrap(PortfolioPieChart(distribution: distribution)),
      );

      expect(find.byType(PieChart), findsNWidgets(2));
      expect(find.text('Portafolio MXN'), findsOneWidget);
      expect(find.text('Portafolio USD'), findsOneWidget);

      // MXN header should come first (alphabetical sort).
      final mxnPosition =
          tester.getTopLeft(find.text('Portafolio MXN')).dy;
      final usdPosition =
          tester.getTopLeft(find.text('Portafolio USD')).dy;
      expect(mxnPosition, lessThan(usdPosition));
    });

    testWidgets('formats group total next to header', (tester) async {
      final distribution = {
        'USD': [
          makeSlice(symbol: 'AAPL', marketValue: 1234.56, percentage: 1.0),
        ],
      };
      await tester.pumpWidget(
        wrap(PortfolioPieChart(distribution: distribution)),
      );

      // "1 · $1,234.56" — 1 holding, formatted total with thousands separator.
      expect(find.textContaining(r'$1,234.56'), findsOneWidget);
    });
  });
}
