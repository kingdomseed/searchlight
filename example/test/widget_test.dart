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

  testWidgets('does not match URL-only terms in default mode', (tester) async {
    await tester.pumpWidget(const SearchValidationApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'creatures');
    await tester.pumpAndSettle();

    expect(find.text('Iron Boar'), findsNothing);
  });

  testWidgets('local corpus mode shows configuration error on placeholder asset',
      (tester) async {
    await tester.pumpWidget(const SearchValidationApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Public fixture'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Local corpus asset').last);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Local corpus asset is not configured'),
      findsOneWidget,
    );
  });

  testWidgets(
      'local snapshot mode shows configuration error on placeholder asset',
      (tester) async {
    await tester.pumpWidget(const SearchValidationApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Public fixture'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Local snapshot asset').last);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Local snapshot asset is not configured'),
      findsOneWidget,
    );
  });
}
