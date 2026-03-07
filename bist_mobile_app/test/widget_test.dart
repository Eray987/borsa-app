import 'package:flutter_test/flutter_test.dart';

import 'package:bist_mobile_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const BistMobileApp());
    expect(find.text('BIST Mobile App'), findsOneWidget);
  });
}
