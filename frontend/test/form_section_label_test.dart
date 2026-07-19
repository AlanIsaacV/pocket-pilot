import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_pilot/src/ui/widgets/form_section_label.dart';

void main() {
  testWidgets('uses the requested dense font size', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FormSectionLabel('Detalles', fontSize: 12)),
      ),
    );

    final text = tester.widget<Text>(find.text('Detalles'));

    expect(text.style!.fontSize, 12);
    expect(text.style!.fontWeight, FontWeight.w600);
  });
}
