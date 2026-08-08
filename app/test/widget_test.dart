import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myuzi/main.dart';

void main() {
  testWidgets('MyÜzi app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyUziApp()));
    await tester.pump();
    // MaterialApp.router keeps the title in platform metadata; it is not a
    // Text widget in the widget tree.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
