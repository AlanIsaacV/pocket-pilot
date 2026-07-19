import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/ui/widgets/dismissible_background.dart';

void main() {
  testWidgets('uses archive colors and start-to-end alignment', (tester) async {
    const margin = EdgeInsets.only(bottom: 8);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DismissibleBackground(
            label: 'Archivar',
            icon: Icons.archive_outlined,
            colorScheme: DismissibleBackgroundColorScheme.archive,
            direction: DismissDirection.startToEnd,
            margin: margin,
          ),
        ),
      ),
    );

    final container = tester.widget<Container>(find.byType(Container));
    final decoration = container.decoration! as BoxDecoration;
    final theme = Theme.of(tester.element(find.byType(DismissibleBackground)));

    expect(find.text('Archivar'), findsOneWidget);
    expect(find.byIcon(Icons.archive_outlined), findsOneWidget);
    expect(container.alignment, Alignment.centerLeft);
    expect(container.margin, margin);
    expect(
      decoration.color,
      theme.colorScheme.tertiary.withValues(alpha: 0.18),
    );
  });

  testWidgets('uses the primary color for edit actions', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DismissibleBackground(
            label: 'Editar',
            icon: Icons.edit_outlined,
            colorScheme: DismissibleBackgroundColorScheme.edit,
          ),
        ),
      ),
    );

    final container = tester.widget<Container>(find.byType(Container));
    final decoration = container.decoration! as BoxDecoration;
    final theme = Theme.of(tester.element(find.byType(DismissibleBackground)));

    expect(find.text('Editar'), findsOneWidget);
    expect(decoration.color, theme.colorScheme.primary.withValues(alpha: 0.18));
  });
}
