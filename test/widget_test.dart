import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:speedy_pizza/main.dart';

void main() {
  testWidgets('reader prepares text and advances with playback', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SpeedyReaderApp());

    expect(find.text('Speedy Reader'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'uno due tre');
    await tester.tap(find.text('Prepara testo'));
    await tester.pump();

    expect(find.text('1 / 3'), findsNWidgets(2));

    await tester.ensureVisible(find.text('Play'));
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('2 / 3'), findsNWidgets(2));
  });
}
