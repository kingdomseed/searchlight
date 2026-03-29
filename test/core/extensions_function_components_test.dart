import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

void main() {
  group('extension function components', () {
    test('getDocumentIndexId can resolve IDs from extra document fields', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        components: SearchlightComponents(
          getDocumentIndexId: (doc) => 'slug:${doc['slug']}',
        ),
      );
      addTearDown(db.dispose);

      final id = db.insert({
        'slug': 'ember-lance',
        'title': 'Ember Lance',
      });

      expect(id, 'slug:ember-lance');
      expect(db.getById('slug:ember-lance')?.toMap()['title'], 'Ember Lance');
    });

    test('validateSchema participates in insert validation', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        components: SearchlightComponents(
          validateSchema: (doc, schema) {
            final _ = schema;
            if (doc['title'] == 'Forbidden') {
              return 'title';
            }
            return null;
          },
        ),
      );
      addTearDown(db.dispose);

      expect(
        () => db.insert({
          'id': 'doc-1',
          'title': 'Forbidden',
        }),
        throwsA(
          isA<DocumentValidationException>().having(
            (error) => error.field,
            'field',
            'title',
          ),
        ),
      );
    });

    test(
      'getDocumentProperties can drive indexing from alternate payloads',
      () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        components: SearchlightComponents(
          getDocumentProperties: (doc, paths) {
            final payload = doc['payload'] as Map<String, Object?>? ?? const {};
            return {
              for (final path in paths)
                path: path == 'title' ? payload['headline'] : doc[path],
            };
          },
        ),
      );
      addTearDown(db.dispose);

      db.insert({
        'id': 'doc-1',
        'payload': {
          'headline': 'Ember Lance',
        },
      });

      final results = db.search(
        term: 'ember',
        properties: const ['title'],
      );

      expect(results.count, 1);
      expect(results.hits.single.id, 'doc-1');
      },
    );
  });
}
