import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

void main() {
  group('extension tokenizer component', () {
    test('component tokenizer replaces the built-in tokenizer', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        components: SearchlightComponents(
          tokenizer: Tokenizer(stopWords: ['the']),
        ),
      )..insert({
          'id': 'doc-1',
          'title': 'the ember lance',
        });
      addTearDown(db.dispose);

      expect(
        db.search(term: 'the', properties: const ['title']).count,
        0,
      );
      expect(
        db.search(term: 'ember', properties: const ['title']).count,
        1,
      );
    });

    test(
      'direct tokenizer input conflicts with tokenizer component overrides',
      () {
      expect(
        () => Searchlight.create(
          schema: Schema({
            'title': const TypedField(SchemaType.string),
          }),
          tokenizer: Tokenizer(),
          components: SearchlightComponents(
            tokenizer: Tokenizer(stopWords: ['the']),
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
      },
    );

    test('restore rejects tokenizer component overrides', () {
      final original = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
      )..insert({
          'id': 'doc-1',
          'title': 'Ember Lance',
        });
      addTearDown(original.dispose);

      expect(
        () => Searchlight.fromJson(
          original.toJson(),
          components: SearchlightComponents(tokenizer: Tokenizer()),
        ),
        throwsA(isA<SerializationException>()),
      );
    });
  });
}
