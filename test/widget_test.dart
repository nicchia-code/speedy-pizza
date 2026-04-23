import 'package:flutter_test/flutter_test.dart';

import 'package:speedy_pizza/main.dart';

void main() {
  testWidgets('home shows the Speedy Pizza shell', (WidgetTester tester) async {
    await tester.pumpWidget(const SpeedyReaderApp());

    expect(find.text('Speedy Pizza'), findsOneWidget);
    expect(find.text('Ultima sessione'), findsOneWidget);
    expect(find.text('Aggiungi contenuto'), findsOneWidget);
  });
}
