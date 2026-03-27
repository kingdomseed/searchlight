import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

void main() {
  group('Searchlight.create tokenizer config', () {
    Searchlight? db;
    Searchlight activeDb() => db!;

    tearDown(() async {
      await db?.dispose();
      db = null;
    });

    test('with stemming: false does not stem indexed or search terms', () {
      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        stemming: false,
      )..insert({
          'id': 'doc1',
          'title': 'studies',
        });

      final result = activeDb().search(
        term: 'study',
        properties: const ['title'],
      );

      expect(result.count, 0);
      expect(result.hits, isEmpty);
    });

    test('defaults to no stemming like Orama create()', () {
      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
      )..insert({
          'id': 'doc1',
          'title': 'studies',
        });

      final result = activeDb().search(
        term: 'study',
        properties: const ['title'],
      );

      expect(result.count, 0);
      expect(result.hits, isEmpty);
    });

    test('with stopWords removes stop words from indexed and search terms', () {
      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        stopWords: const ['the', 'is'],
      )..insert({
          'id': 'doc1',
          'title': 'the cat is here',
        });

      final stopWordResult = activeDb().search(
        term: 'the',
        properties: const ['title'],
      );
      final contentResult = activeDb().search(
        term: 'cat',
        properties: const ['title'],
      );

      expect(stopWordResult.count, 0);
      expect(stopWordResult.hits, isEmpty);
      expect(contentResult.count, 1);
      expect(contentResult.hits.first.id, 'doc1');
    });

    test('with stemmerSkipProperties skips stemming only on those fields', () {
      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'content': const TypedField(SchemaType.string),
        }),
        stemming: true,
        stemmerSkipProperties: const {'title'},
      )..insert({
          'id': 'doc1',
          'title': 'studying',
          'content': 'studying',
        });

      final titleResult = activeDb().search(
        term: 'study',
        properties: const ['title'],
      );
      final contentResult = activeDb().search(
        term: 'study',
        properties: const ['content'],
      );

      expect(titleResult.count, 0);
      expect(titleResult.hits, isEmpty);
      expect(contentResult.count, 1);
      expect(contentResult.hits.first.id, 'doc1');
    });

    test('with custom tokenizer uses the injected tokenizer', () {
      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        tokenizer: Tokenizer(
          stopWords: ['the'],
        ),
      )..insert({
          'id': 'doc1',
          'title': 'the studies',
        });

      final stopWordResult = activeDb().search(
        term: 'the',
        properties: const ['title'],
      );
      final stemmedResult = activeDb().search(
        term: 'study',
        properties: const ['title'],
      );
      final literalResult = activeDb().search(
        term: 'studies',
        properties: const ['title'],
      );

      expect(stopWordResult.count, 0);
      expect(stemmedResult.count, 0);
      expect(literalResult.count, 1);
      expect(literalResult.hits.first.id, 'doc1');
    });

    test('with custom tokenizer rejects explicit language overrides', () {
      expect(
        () => Searchlight.create(
          schema: Schema({
            'title': const TypedField(SchemaType.string),
          }),
          language: 'english',
          tokenizer: Tokenizer(),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('with custom tokenizer rejects additional tokenizer config', () {
      expect(
        () => Searchlight.create(
          schema: Schema({
            'title': const TypedField(SchemaType.string),
          }),
          tokenizer: Tokenizer(),
          stopWords: const ['the'],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('with tokenizeSkipProperties indexes that field as one token', () {
      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        tokenizeSkipProperties: const {'title'},
      )..insert({
          'id': 'doc1',
          'title': 'SKU Élite 42',
        });

      final result = activeDb().search(
        term: 'elite',
        properties: const ['title'],
      );

      expect(result.count, 0);
      expect(result.hits, isEmpty);
    });

    test('JSON round-trip preserves surfaced tokenizer config', () async {
      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        stemming: false,
        stopWords: const ['the'],
      )..insert({
          'id': 'doc1',
          'title': 'the studies',
        });

      final restored = Searchlight.fromJson(activeDb().toJson());
      addTearDown(restored.dispose);

      final stopWordResult = restored.search(
        term: 'the',
        properties: const ['title'],
      );
      final stemmedResult = restored.search(
        term: 'study',
        properties: const ['title'],
      );
      final literalResult = restored.search(
        term: 'studies',
        properties: const ['title'],
      );

      expect(stopWordResult.count, 0);
      expect(stopWordResult.hits, isEmpty);
      expect(stemmedResult.count, 0);
      expect(stemmedResult.hits, isEmpty);
      expect(literalResult.count, 1);
      expect(literalResult.hits.first.id, 'doc1');
    });

    test('with useDefaultStopWords applies built-in stop words', () {
      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        useDefaultStopWords: true,
      )..insert({
          'id': 'doc1',
          'title': 'the cat is here',
        });

      final stopWordResult = activeDb().search(
        term: 'the',
        properties: const ['title'],
      );
      final contentResult = activeDb().search(
        term: 'cat',
        properties: const ['title'],
      );

      expect(stopWordResult.count, 0);
      expect(stopWordResult.hits, isEmpty);
      expect(contentResult.count, 1);
      expect(contentResult.hits.first.id, 'doc1');
    });

    test(
      'with allowDuplicates preserves repeated-token scoring impact',
      () async {
        final noDuplicatesDb = Searchlight.create(
          schema: Schema({
            'title': const TypedField(SchemaType.string),
          }),
        )..insert({
            'id': 'doc1',
            'title': 'hello hello world',
          });
        addTearDown(noDuplicatesDb.dispose);

        final allowDuplicatesDb = Searchlight.create(
          schema: Schema({
            'title': const TypedField(SchemaType.string),
          }),
          allowDuplicates: true,
        )..insert({
            'id': 'doc1',
            'title': 'hello hello world',
          });
        addTearDown(allowDuplicatesDb.dispose);

        final noDuplicatesResult = noDuplicatesDb.search(
          term: 'hello',
          properties: const ['title'],
        );
        final allowDuplicatesResult = allowDuplicatesDb.search(
          term: 'hello',
          properties: const ['title'],
        );

        expect(noDuplicatesResult.count, 1);
        expect(allowDuplicatesResult.count, 1);
        expect(
          allowDuplicatesResult.hits.first.score,
          greaterThan(noDuplicatesResult.hits.first.score),
        );
      },
    );

    test('with custom stemmer uses the supplied stemming function', () {
      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        stemmer: (token) => token.isEmpty ? token : token[0],
      )..insert({
          'id': 'doc1',
          'title': 'zebra',
        });

      final result = activeDb().search(
        term: 'zoo',
        properties: const ['title'],
      );

      expect(result.count, 1);
      expect(result.hits.first.id, 'doc1');
    });

    test('with plugins accepts configured plugins after resolution step', () {
      expect(
        () => Searchlight.create(
          schema: Schema({
            'title': const TypedField(SchemaType.string),
          }),
          plugins: const [SearchlightPlugin(name: 'test-plugin')],
        ),
        returnsNormally,
      );
    });

    test(
      'with plugins throws a deterministic exception for duplicate names',
      () {
        expect(
          () => Searchlight.create(
            schema: Schema({
              'title': const TypedField(SchemaType.string),
            }),
            plugins: const [
              SearchlightPlugin(name: 'duplicate'),
              SearchlightPlugin(name: 'duplicate'),
            ],
          ),
          throwsA(
            isA<ExtensionResolutionException>().having(
              (error) => error.message,
              'message',
              contains('duplicate'),
            ),
          ),
        );
      },
    );

    test(
      'with components accepts direct overrides after resolution step',
      () {
        expect(
          () => Searchlight.create(
            schema: Schema({
              'title': const TypedField(SchemaType.string),
            }),
            components: const SearchlightComponents(),
          ),
          returnsNormally,
        );
      },
    );

    test('stores resolved extension state on created instances', () {
      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: const [SearchlightPlugin(name: 'kept')],
      );

      expect(db!.resolvedExtensions.plugins, hasLength(1));
      expect(db!.resolvedExtensions.plugins.first.name, 'kept');
    });
  });
}
