import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/ui/widgets/temporal_page_view.dart';

void main() {
  testWidgets('tapping a quick-range chip calls setQuickSelection',
      (tester) async {
    final state = _FakeTemporalFilterState();

    await _pumpTemporalPageView(tester, state);

    await tester.tap(find.text('1Y'));
    await tester.pumpAndSettle();

    expect(state.quickSelectionCalls, [QuickRange.y1]);
  });

  testWidgets('the granularity sheet shows Spanish labels', (tester) async {
    // Start on the period page (index 1) so it's mounted from the outset.
    final state = _FakeTemporalFilterState(activePageIndex: 1);

    await _pumpTemporalPageView(tester, state);

    await tester.tap(find.text('Mes'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, 'Semana'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Mes'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Año'), findsOneWidget);
    expect(find.text('Week'), findsNothing);
    expect(find.text('Month'), findsNothing);
    expect(find.text('Year'), findsNothing);
  });

  testWidgets('dots reflect activePageIndex', (tester) async {
    final state = _FakeTemporalFilterState(activePageIndex: 1);

    await _pumpTemporalPageView(tester, state);

    final dotDecorations = tester
        .widgetList<Container>(find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).shape == BoxShape.circle,
        ))
        .map((container) => container.decoration! as BoxDecoration)
        .toList();

    expect(dotDecorations, hasLength(3));
    // Index 1 (active) should stand out from the two inactive dots (0, 2),
    // which share the same inactive color.
    expect(dotDecorations[0].color, dotDecorations[2].color);
    expect(dotDecorations[1].color, isNot(dotDecorations[0].color));
  });
}

Future<void> _pumpTemporalPageView(
  WidgetTester tester,
  TemporalFilterState state,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TemporalPageView(state: state),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeTemporalFilterState extends ChangeNotifier
    implements TemporalFilterState {
  _FakeTemporalFilterState({this.activePageIndex = 0});

  @override
  int activePageIndex;
  @override
  QuickRange quickSelection = QuickRange.d30;
  @override
  PeriodGranularity periodGranularity = PeriodGranularity.month;
  @override
  String periodLabel = 'Mes';
  @override
  DateTime customFrom = DateTime(2026, 1, 1);
  @override
  DateTime customTo = DateTime(2026, 1, 31);

  final List<QuickRange> quickSelectionCalls = [];

  @override
  void setActivePageIndex(int index) {
    activePageIndex = index;
    notifyListeners();
  }

  @override
  void setQuickSelection(QuickRange range) {
    quickSelection = range;
    quickSelectionCalls.add(range);
    activePageIndex = 0;
    notifyListeners();
  }

  @override
  void setPeriodGranularity(PeriodGranularity g) {
    periodGranularity = g;
    activePageIndex = 1;
    notifyListeners();
  }

  @override
  void navigatePeriod(int delta) {
    notifyListeners();
  }

  @override
  void setCustomRange(DateTime from, DateTime to) {
    customFrom = from;
    customTo = to;
    activePageIndex = 2;
    notifyListeners();
  }
}
