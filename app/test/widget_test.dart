import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myuzi/main.dart';

void main() {
  testWidgets('MyÜzi app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyUziApp()));
    await tester.pump();
    expect(find.text('MyÜzi'), findsWidgets);
  });
}
