import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:searchlight_example/main.dart';

void main() {
  testWidgets('renders validator-style controls', (tester) async {
    await tester.pumpWidget(SearchValidationApp(bundle: _TestAssetBundle()));
    await _pumpLoaded(tester);

    expect(find.text('Choose Folder'), findsOneWidget);
    expect(find.text('Public fixture'), findsWidgets);
    expect(find.textContaining('Indexed'), findsOneWidget);
  });

  testWidgets('shows seeded results for a corpus query', (tester) async {
    await tester.pumpWidget(SearchValidationApp(bundle: _TestAssetBundle()));
    await _pumpLoaded(tester);

    await tester.enterText(find.byType(TextField), 'ember');
    await tester.pump();
    expect(find.text('Ember Lance'), findsWidgets);
    expect(find.textContaining('/spells/ember-lance'), findsWidgets);
  });

  testWidgets('does not match URL-only terms in default mode', (tester) async {
    await tester.pumpWidget(SearchValidationApp(bundle: _TestAssetBundle()));
    await _pumpLoaded(tester);

    await tester.enterText(find.byType(TextField), 'creatures');
    await tester.pump();

    expect(find.text('Iron Boar'), findsNothing);
  });

  testWidgets(
    'local corpus mode shows configuration error on placeholder asset',
    (tester) async {
      await tester.pumpWidget(SearchValidationApp(bundle: _TestAssetBundle()));
      await _pumpLoaded(tester);

      await tester.tap(find.byType(DropdownButton<ValidationSourceMode>));
      await tester.pump();
      await tester.tap(find.text('Local corpus asset').last);
      await _pumpLoaded(tester);

      expect(
        find.textContaining('Local corpus asset is not configured'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'local snapshot mode shows configuration error on placeholder asset',
    (tester) async {
      await tester.pumpWidget(SearchValidationApp(bundle: _TestAssetBundle()));
      await _pumpLoaded(tester);

      await tester.tap(find.byType(DropdownButton<ValidationSourceMode>));
      await tester.pump();
      await tester.tap(find.text('Local snapshot asset').last);
      await _pumpLoaded(tester);

      expect(
        find.textContaining('Local snapshot asset is not configured'),
        findsOneWidget,
      );
    },
  );
}

Future<void> _pumpLoaded(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      return;
    }
  }

  fail('Example app did not finish loading within the test timeout.');
}

final class _TestAssetBundle extends CachingAssetBundle {
  static const Map<String, String> _assets = {
    'assets/search_corpus.json': '''
[
  {
    "url": "/guide/spells/ember-lance",
    "title": "Ember Lance",
    "content": "A precise fire spell that launches a concentrated spear of heat.",
    "type": "spell",
    "group": "fire"
  },
  {
    "url": "/guide/spells/mist-veil",
    "title": "Mist Veil",
    "content": "A utility spell that blankets a corridor in cold fog and blocks sight lines.",
    "type": "spell",
    "group": "water"
  },
  {
    "url": "/guide/creatures/iron-boar",
    "title": "Iron Boar",
    "content": "A heavily armored beast known for charging through shields.",
    "type": "monster",
    "group": "beasts"
  }
]
''',
    'assets/local/generated_search_corpus.json': '[]',
    'assets/local/generated_search_snapshot.json': '{}',
  };

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final value = _assets[key];
    if (value == null) {
      throw FlutterError('Unknown test asset: $key');
    }
    return value;
  }

  @override
  Future<ByteData> load(String key) async {
    final value = await loadString(key);
    final bytes = Uint8List.fromList(utf8.encode(value));
    return ByteData.sublistView(bytes);
  }
}
