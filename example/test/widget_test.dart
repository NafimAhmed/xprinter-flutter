import 'package:flutter_test/flutter_test.dart';
import 'package:xprinter_flutter_example/main.dart';

void main() {
  testWidgets('Printer example displays controls', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('xprinter_flutter - XP-365B test'), findsOneWidget);
    expect(find.text('Refresh paired printers'), findsOneWidget);
  });
}
