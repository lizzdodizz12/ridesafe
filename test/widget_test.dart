import 'package:flutter_test/flutter_test.dart';
import 'package:ridesafe/main.dart';

void main() {
  testWidgets('App loads and shows title', (WidgetTester tester) async {
    await tester.pumpWidget(const RideSafeApp());

    expect(find.text('RideSafe PH'), findsOneWidget);
  });
}
