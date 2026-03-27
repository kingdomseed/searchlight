import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

void main() {
  group('source format behavior', () {
    test(
      'raw HTML is indexed as plain text, including markup tokens',
      () async {
        final db = Searchlight.create(
          schema: Schema({
            'content': const TypedField(SchemaType.string),
          }),
        );
        addTearDown(db.dispose);

        db.insert({
          'content': '<h1 class="hero">Ember Lance</h1><p>Fire spell</p>',
        });

        final visibleText = db.search(
          term: 'ember',
          properties: const ['content'],
        );
        final tagName = db.search(
          term: 'h1',
          properties: const ['content'],
        );
        final attributeToken = db.search(
          term: 'hero',
          properties: const ['content'],
        );

        expect(visibleText.count, 1);
        expect(tagName.count, 1);
        expect(attributeToken.count, 1);
      },
    );

    test(
      'raw Markdown is indexed as plain text, '
      'including link destination tokens',
      () async {
        final db = Searchlight.create(
          schema: Schema({
            'content': const TypedField(SchemaType.string),
          }),
        );
        addTearDown(db.dispose);

        db.insert({
          'content': '# Ember Lance\n\nSee [spell notes](/spells/ember-lance).',
        });

        final visibleText = db.search(
          term: 'notes',
          properties: const ['content'],
        );
        final linkDestination = db.search(
          term: 'spells',
          properties: const ['content'],
        );

        expect(visibleText.count, 1);
        expect(linkDestination.count, 1);
      },
    );
  });
}
