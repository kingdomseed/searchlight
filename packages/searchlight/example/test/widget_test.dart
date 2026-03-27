import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:searchlight_example/main.dart';

void main() {
  testWidgets('shows seeded results for a corpus query', (tester) async {
    await tester.pumpWidget(const SearchValidationApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'ember');
    await tester.pumpAndSettle();

    expect(find.text('Ember Lance'), findsOneWidget);
  });
}
