// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

SearchlightIndexComponent _testIndexComponent(String id) {
  return SearchlightIndexComponent(
    id: id,
    create: ({
      required schema,
      required algorithm,
    }) => SearchIndex.create(schema: schema, algorithm: algorithm),
  );
}

SearchlightSorterComponent _testSorterComponent(String id) {
  return SearchlightSorterComponent(
    id: id,
    create: ({required language}) => SortIndex(language: language),
  );
}

void main() {
  group('JSON serialization', () {
    test('toJson includes formatVersion field', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
      );

      final json = db.toJson();

      expect(json['formatVersion'], equals(1));
    });

    test('toJson includes serialized index and sorting state', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'price': const TypedField(SchemaType.number),
        }),
      )..insert({'id': 'doc1', 'title': 'Hello', 'price': 5});

      final json = db.toJson();

      expect(json['index'], isA<Map<String, Object?>>());
      expect(json['sorting'], isA<Map<String, Object?>>());
    });

    test('toJson records active plugin names and component identities', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: const [
          SearchlightPlugin(name: 'alpha'),
          SearchlightPlugin(name: 'beta'),
        ],
        components: SearchlightComponents(
          index: _testIndexComponent('test.index.json'),
          sorter: _testSorterComponent('test.sorter.json'),
        ),
      );

      final json = db.toJson();
      final compatibility =
          json['extensionCompatibility']! as Map<String, Object?>;

      expect(
        compatibility['plugins'],
        <String>['alpha', 'beta'],
      );
      expect(
        compatibility['components'],
        <String, String>{
          'index': 'test.index.json',
          'sorter': 'test.sorter.json',
          'documentsStore': 'searchlight.documents.default',
        },
      );
    });

    test('round-trip empty database preserves schema, algorithm, language', () {
      final schema = Schema({
        'title': const TypedField(SchemaType.string),
        'rating': const TypedField(SchemaType.number),
        'meta': const NestedField({
          'active': TypedField(SchemaType.boolean),
        }),
      });
      final db = Searchlight.create(
        schema: schema,
      );

      final json = db.toJson();
      final restored = Searchlight.fromJson(json);

      expect(restored.algorithm, equals(SearchAlgorithm.bm25));
      expect(restored.language, equals('en'));
      expect(restored.count, equals(0));
      // Verify schema field paths match
      expect(
        restored.schema.fieldPaths,
        unorderedEquals(schema.fieldPaths),
      );
      // Verify schema field types match
      for (final path in schema.fieldPaths) {
        expect(restored.schema.typeAt(path), equals(schema.typeAt(path)));
      }
    });

    test('round-trip with documents preserves count and getById', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'rating': const TypedField(SchemaType.number),
        }),
      )
        ..insert({'id': 'doc1', 'title': 'Hello World', 'rating': 5})
        ..insert({'id': 'doc2', 'title': 'Goodbye Moon', 'rating': 3});

      final json = db.toJson();
      final restored = Searchlight.fromJson(json);

      expect(restored.count, equals(2));
      final doc1 = restored.getById('doc1');
      expect(doc1, isNotNull);
      expect(doc1!.getString('title'), equals('Hello World'));
      expect(doc1.getNumber('rating'), equals(5));

      final doc2 = restored.getById('doc2');
      expect(doc2, isNotNull);
      expect(doc2!.getString('title'), equals('Goodbye Moon'));
      expect(doc2.getNumber('rating'), equals(3));
    });

    test('fromJson restores without dispatching load hooks', () {
      final calls = <String>[];
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: [
          SearchlightPlugin(
            name: 'hooks',
            hooks: SearchlightHooks(
              beforeLoad: (_, __) => calls.add('beforeLoad'),
              afterLoad: (_, __) => calls.add('afterLoad'),
            ),
          ),
        ],
      )..insert({'id': 'doc-1', 'title': 'Hello'});
      final json = db.toJson();

      final restored = Searchlight.fromJson(
        json,
        plugins: [
          SearchlightPlugin(
            name: 'hooks',
            hooks: SearchlightHooks(
              beforeLoad: (_, __) => calls.add('beforeLoad'),
              afterLoad: (_, __) => calls.add('afterLoad'),
            ),
          ),
        ],
      );

      expect(calls, isEmpty);
      expect(restored.count, 1);
      expect(restored.getById('doc-1'), isNotNull);
    });

    test('fromJson restores with a compatible plugin and component graph', () {
      final index = _testIndexComponent('test.index.compat');
      final sorter = _testSorterComponent('test.sorter.compat');
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: const [
          SearchlightPlugin(name: 'alpha'),
          SearchlightPlugin(name: 'beta'),
        ],
        components: SearchlightComponents(index: index, sorter: sorter),
      )..insert({'id': 'doc-1', 'title': 'Hello'});
      final json = db.toJson();

      final restored = Searchlight.fromJson(
        json,
        plugins: const [
          SearchlightPlugin(name: 'alpha'),
          SearchlightPlugin(name: 'beta'),
        ],
        components: SearchlightComponents(index: index, sorter: sorter),
      );

      expect(restored.count, 1);
      expect(restored.getById('doc-1'), isNotNull);
    });

    test('fromJson rejects mismatched plugin order clearly', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: const [
          SearchlightPlugin(name: 'alpha'),
          SearchlightPlugin(name: 'beta'),
        ],
      )..insert({'id': 'doc-1', 'title': 'Hello'});
      final json = db.toJson();

      expect(
        () => Searchlight.fromJson(
          json,
          plugins: const [
            SearchlightPlugin(name: 'beta'),
            SearchlightPlugin(name: 'alpha'),
          ],
        ),
        throwsA(
          isA<SerializationException>().having(
            (error) => error.message,
            'message',
            contains('plugin'),
          ),
        ),
      );
    });

    test('fromJson rejects mismatched component identities clearly', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        components: SearchlightComponents(
          index: _testIndexComponent('test.index.expected'),
          sorter: _testSorterComponent('test.sorter.expected'),
        ),
      )..insert({'id': 'doc-1', 'title': 'Hello'});
      final json = db.toJson();

      expect(
        () => Searchlight.fromJson(
          json,
          components: SearchlightComponents(
            index: _testIndexComponent('test.index.actual'),
            sorter: _testSorterComponent('test.sorter.actual'),
          ),
        ),
        throwsA(
          isA<SerializationException>().having(
            (error) => error.message,
            'message',
            contains('component'),
          ),
        ),
      );
    });

    test('fromJson ignores async load hooks because load hooks are not wired',
        () {
      var sideEffectRan = false;
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: [
          SearchlightPlugin(
            name: 'hooks',
            hooks: SearchlightHooks(
              beforeLoad: (_, __) async {
                sideEffectRan = true;
              },
            ),
          ),
        ],
      )..insert({'id': 'doc-1', 'title': 'Hello'});
      final json = db.toJson();

      final restored = Searchlight.fromJson(
        json,
        plugins: [
          SearchlightPlugin(
            name: 'hooks',
            hooks: SearchlightHooks(
              beforeLoad: (_, __) async {
                sideEffectRan = true;
              },
            ),
          ),
        ],
      );
      expect(sideEffectRan, isFalse);
      expect(restored.count, 1);
    });

    test('round-trip search works on restored database (BM25)', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'body': const TypedField(SchemaType.string),
        }),
      )
        ..insert({'id': 'doc1', 'title': 'Dart language', 'body': 'Fast'})
        ..insert({'id': 'doc2', 'title': 'Flutter framework', 'body': 'Dart'})
        ..insert({'id': 'doc3', 'title': 'Python scripting', 'body': 'Slow'});

      final json = db.toJson();
      final restored = Searchlight.fromJson(json);

      // Search should find documents containing "dart"
      final results = restored.search(term: 'dart');
      expect(results.count, greaterThanOrEqualTo(2));
      final ids = results.hits.map((h) => h.id).toList();
      expect(ids, contains('doc1'));
      expect(ids, contains('doc2'));
      // "Python scripting" / "Slow" should not match "dart"
      expect(ids, isNot(contains('doc3')));
    });

    test(
      'fromJson restores serialized components without revalidating documents',
      () {
        final db = Searchlight.create(
          schema: Schema({
            'title': const TypedField(SchemaType.string),
            'rating': const TypedField(SchemaType.number),
          }),
        )..insert({
            'id': 'doc1',
            'title': 'Dart Programming',
            'rating': 5,
          });

        final json = db.toJson();
        final documents = json['documents']! as Map<String, Object?>;
        final doc = documents.values.first! as Map<String, Object?>;
        doc['rating'] = 'not-a-number';

        final restored = Searchlight.fromJson(json);

        final results = restored.search(term: 'dart');
        expect(results.count, 1);
        expect(results.hits.first.id, 'doc1');
      },
    );

    test(
      'fromJson restores serialized sort state without revalidating documents',
      () {
        final db = Searchlight.create(
          schema: Schema({
            'title': const TypedField(SchemaType.string),
            'rating': const TypedField(SchemaType.number),
          }),
        )
          ..insert({
            'id': 'doc1',
            'title': 'Dart Patterns',
            'rating': 10,
          })
          ..insert({
            'id': 'doc2',
            'title': 'Dart Cookbook',
            'rating': 1,
          });

        final json = db.toJson();
        final documents = json['documents']! as Map<String, Object?>;
        for (final rawDoc in documents.values) {
          final doc = rawDoc! as Map<String, Object?>;
          doc['rating'] = 'not-a-number';
        }

        final restored = Searchlight.fromJson(json);
        final results = restored.search(
          term: 'dart',
          sortBy: const SortBy(field: 'rating', order: SortOrder.asc),
        );

        expect(results.count, 2);
        expect(results.hits.map((hit) => hit.id).toList(), ['doc2', 'doc1']);
      },
    );

    test('round-trip filters work on restored database', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'rating': const TypedField(SchemaType.number),
          'active': const TypedField(SchemaType.boolean),
        }),
      )
        ..insert({'id': 'a', 'title': 'Alpha', 'rating': 5, 'active': true})
        ..insert({'id': 'b', 'title': 'Beta', 'rating': 2, 'active': false})
        ..insert({'id': 'c', 'title': 'Gamma', 'rating': 8, 'active': true});

      final json = db.toJson();
      final restored = Searchlight.fromJson(json);

      // Number filter: rating > 3
      final numResults = restored.search(
        where: {'rating': const GtFilter(3)},
      );
      final numIds = numResults.hits.map((h) => h.id).toSet();
      expect(numIds, containsAll(['a', 'c']));
      expect(numIds, isNot(contains('b')));

      // Boolean filter: active == true
      final boolResults = restored.search(
        where: {'active': const EqFilter(true)},
      );
      final boolIds = boolResults.hits.map((h) => h.id).toSet();
      expect(boolIds, containsAll(['a', 'c']));
      expect(boolIds, isNot(contains('b')));
    });

    test('round-trip QPS algorithm preserved', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        algorithm: SearchAlgorithm.qps,
      )
        ..insert({'id': 'q1', 'title': 'Quantum computing is exciting.'})
        ..insert({'id': 'q2', 'title': 'Classical computing is boring.'});

      final json = db.toJson();
      final restored = Searchlight.fromJson(json);

      expect(restored.algorithm, equals(SearchAlgorithm.qps));

      // Search should work with QPS scoring
      final results = restored.search(term: 'quantum');
      expect(results.count, greaterThanOrEqualTo(1));
      expect(results.hits.first.id, equals('q1'));
    });

    test('round-trip PT15 algorithm preserved', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        algorithm: SearchAlgorithm.pt15,
      )
        ..insert({'id': 'p1', 'title': 'Positional text indexing'})
        ..insert({'id': 'p2', 'title': 'Random unrelated topic'});

      final json = db.toJson();
      final restored = Searchlight.fromJson(json);

      expect(restored.algorithm, equals(SearchAlgorithm.pt15));

      // Search should work with PT15 scoring
      final results = restored.search(term: 'positional');
      expect(results.count, greaterThanOrEqualTo(1));
      expect(results.hits.first.id, equals('p1'));
    });

    test('fromJson rejects future formatVersion (E2)', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
      );
      final json = db.toJson();

      // Future version should be rejected
      json['formatVersion'] = 999;

      expect(
        () => Searchlight.fromJson(json),
        throwsA(isA<SerializationException>()),
      );
    });

    test('fromJson accepts current and past formatVersions (E2)', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
      )..insert({'id': 'doc1', 'title': 'Hello'});

      // Current version should work
      final json = db.toJson();
      final restored = Searchlight.fromJson(json);
      expect(restored.count, equals(1));

      // A past version (0) should also be accepted since the check
      // now only rejects future versions
      final json2 = db.toJson();
      json2['formatVersion'] = 0;
      final restored2 = Searchlight.fromJson(json2);
      expect(restored2.count, equals(1));
    });

    test('fromJson with corrupt/missing data throws SerializationException',
        () {
      // Missing formatVersion
      expect(
        () => Searchlight.fromJson(<String, Object?>{}),
        throwsA(isA<SerializationException>()),
      );

      // Missing algorithm
      expect(
        () => Searchlight.fromJson(<String, Object?>{
          'formatVersion': 1,
        }),
        throwsA(isA<SerializationException>()),
      );

      // Missing language
      expect(
        () => Searchlight.fromJson(<String, Object?>{
          'formatVersion': 1,
          'algorithm': 'bm25',
        }),
        throwsA(isA<SerializationException>()),
      );

      // Missing schema
      expect(
        () => Searchlight.fromJson(<String, Object?>{
          'formatVersion': 1,
          'algorithm': 'bm25',
          'language': 'en',
        }),
        throwsA(isA<SerializationException>()),
      );

      // Invalid algorithm name
      expect(
        () => Searchlight.fromJson(<String, Object?>{
          'formatVersion': 1,
          'algorithm': 'nonexistent',
          'language': 'en',
          'schema': <String, Object?>{
            'title': {'type': 'string'},
          },
        }),
        throwsA(isA<SerializationException>()),
      );

      // Invalid language
      expect(
        () => Searchlight.fromJson(<String, Object?>{
          'formatVersion': 1,
          'algorithm': 'bm25',
          'language': 'klingon',
          'schema': <String, Object?>{
            'title': {'type': 'string'},
          },
          'documents': <String, Object?>{},
        }),
        throwsA(isA<SerializationException>()),
      );
    });

    test(
        'toJson produces valid JSON (round-trip through jsonEncode/jsonDecode)',
        () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'rating': const TypedField(SchemaType.number),
          'active': const TypedField(SchemaType.boolean),
          'meta': const NestedField({
            'tags': TypedField(SchemaType.stringArray),
          }),
        }),
      )
        ..insert({
          'id': 'doc1',
          'title': 'Test document',
          'rating': 4.5,
          'active': true,
          'meta': {
            'tags': ['dart', 'flutter'],
          },
        })
        ..insert({
          'id': 'doc2',
          'title': 'Another document',
          'rating': 2,
          'active': false,
          'meta': {
            'tags': ['python'],
          },
        });

      final map = db.toJson();

      // Should not throw — the map must be JSON-encodable
      final jsonString = jsonEncode(map);
      expect(jsonString, isA<String>());
      expect(jsonString.isNotEmpty, isTrue);

      // Decode back and restore
      final decoded = jsonDecode(jsonString) as Map<String, Object?>;
      final restored = Searchlight.fromJson(decoded);

      expect(restored.count, equals(2));
      expect(restored.getById('doc1'), isNotNull);
      expect(restored.getById('doc2'), isNotNull);

      // Verify search still works after full JSON string round-trip
      final results = restored.search(term: 'test');
      expect(results.count, greaterThanOrEqualTo(1));
      expect(results.hits.first.id, equals('doc1'));
    });

    test('toJson rejects databases created with a custom tokenizer', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        tokenizer: Tokenizer(
          stopWords: ['the'],
        ),
      );

      expect(
        db.toJson,
        throwsA(isA<SerializationException>()),
      );
    });

    test('toJson rejects databases created with a custom stemmer', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        stemmer: (token) => token.isEmpty ? token : token[0],
      );

      expect(
        db.toJson,
        throwsA(isA<SerializationException>()),
      );
    });

    test('round-trip preserves useDefaultStopWords config flag', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        useDefaultStopWords: true,
      )..insert({
          'id': 'doc1',
          'title': 'the cat is here',
        });

      final restored = Searchlight.fromJson(db.toJson());
      final tokenizerConfig =
          restored.toJson()['tokenizerConfig']! as Map<String, Object?>;

      expect(tokenizerConfig['useDefaultStopWords'], isTrue);
    });

    test('fromJson rejects invalid tokenizerConfig field types', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
      );
      final json = db.toJson();
      json['tokenizerConfig'] = <String, Object?>{
        'stemming': false,
        'stopWords': 'not-a-list',
      };

      expect(
        () => Searchlight.fromJson(json),
        throwsA(isA<SerializationException>()),
      );
    });

    test('fromJson corrects nextInternalId if saved value is too low (C3)', () {
      // Manually craft JSON where nextId (2) is less than doc count + 1 (3).
      // The defensive check should correct it.
      final json = <String, Object?>{
        'formatVersion': 1,
        'algorithm': 'bm25',
        'language': 'en',
        'schema': <String, Object?>{
          'title': {'type': 'string'},
        },
        'internalDocumentIDStore': <String, Object?>{
          'idToInternalId': <String, int>{'doc1': 1, 'doc2': 2},
          'internalIdToId': <String, String>{'1': 'doc1', '2': 'doc2'},
          'nextId': 2, // Too low! Should be >= 3
          'nextGeneratedId': 0,
        },
        'documents': <String, Object?>{
          '1': <String, Object?>{'title': 'Alpha'},
          '2': <String, Object?>{'title': 'Beta'},
        },
      };

      final restored = Searchlight.fromJson(json);
      expect(restored.count, equals(2));

      // Should be able to insert without ID collision
      final newId = restored.insert({'id': 'doc3', 'title': 'Gamma'});
      expect(newId, equals('doc3'));
      expect(restored.count, equals(3));
    });

    test('fromJson throws when documents key is missing (I3c)', () {
      expect(
        () => Searchlight.fromJson(<String, Object?>{
          'formatVersion': 1,
          'algorithm': 'bm25',
          'language': 'en',
          'schema': <String, Object?>{
            'title': {'type': 'string'},
          },
          // No 'documents' key
          'internalDocumentIDStore': <String, Object?>{
            'internalIdToId': <String, Object?>{},
            'nextId': 1,
            'nextGeneratedId': 0,
          },
        }),
        throwsA(isA<SerializationException>()),
      );
    });

    test('round-trip with enum fields preserves enum data', () {
      final db = Searchlight.create(
        schema: Schema({
          'name': const TypedField(SchemaType.string),
          'color': const TypedField(SchemaType.enumType),
        }),
      )
        ..insert({'id': 'a', 'name': 'Apple', 'color': 'red'})
        ..insert({'id': 'b', 'name': 'Banana', 'color': 'yellow'});

      final jsonString = jsonEncode(db.toJson());
      final decoded = jsonDecode(jsonString) as Map<String, Object?>;
      final restored = Searchlight.fromJson(decoded);

      expect(restored.count, equals(2));
      final apple = restored.getById('a');
      expect(apple, isNotNull);
      expect(apple!.getString('color'), equals('red'));

      // Enum filter should work on restored database
      final results = restored.search(
        where: {'color': const EqFilter('red')},
      );
      expect(results.count, equals(1));
      expect(results.hits.first.id, equals('a'));
    });

    test('round-trip with array fields preserves array data', () {
      final db = Searchlight.create(
        schema: Schema({
          'name': const TypedField(SchemaType.string),
          'tags': const TypedField(SchemaType.stringArray),
          'scores': const TypedField(SchemaType.numberArray),
        }),
      )
        ..insert({
          'id': 'doc1',
          'name': 'Widget',
          'tags': ['dart', 'flutter'],
          'scores': [95, 87, 91],
        })
        ..insert({
          'id': 'doc2',
          'name': 'Plugin',
          'tags': ['python'],
          'scores': [72],
        });

      final jsonString = jsonEncode(db.toJson());
      final decoded = jsonDecode(jsonString) as Map<String, Object?>;
      final restored = Searchlight.fromJson(decoded);

      expect(restored.count, equals(2));
      final doc1 = restored.getById('doc1');
      expect(doc1, isNotNull);
      expect(doc1!.getStringList('tags'), equals(['dart', 'flutter']));
      expect(doc1.getNumberList('scores'), equals([95, 87, 91]));
    });

    test('round-trip with nested fields preserves nested data', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'meta': const NestedField({
            'author': TypedField(SchemaType.string),
            'rating': TypedField(SchemaType.number),
          }),
        }),
      )
        ..insert({
          'id': 'doc1',
          'title': 'Dart Guide',
          'meta': {'author': 'Alice', 'rating': 5},
        })
        ..insert({
          'id': 'doc2',
          'title': 'Flutter Book',
          'meta': {'author': 'Bob', 'rating': 3},
        });

      final jsonString = jsonEncode(db.toJson());
      final decoded = jsonDecode(jsonString) as Map<String, Object?>;
      final restored = Searchlight.fromJson(decoded);

      expect(restored.count, equals(2));
      final doc1 = restored.getById('doc1');
      expect(doc1, isNotNull);
      expect(doc1!.getNested('meta').getString('author'), equals('Alice'));
      expect(doc1.getNested('meta').getNumber('rating'), equals(5));

      // Search on nested field should work
      final results = restored.search(term: 'Alice');
      expect(results.count, greaterThanOrEqualTo(1));
    });

    test('delete-then-persist preserves correct IDs (sparse IDs)', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
      )
        ..insert({'id': 'a', 'title': 'Alpha'})
        ..insert({'id': 'b', 'title': 'Beta'})
        ..insert({'id': 'c', 'title': 'Gamma'})
        ..insert({'id': 'd', 'title': 'Delta'});

      // Delete middle documents to create sparse internal IDs
      expect(db.remove('b'), isTrue);
      expect(db.remove('c'), isTrue);
      expect(db.count, equals(2));

      final jsonString = jsonEncode(db.toJson());
      final decoded = jsonDecode(jsonString) as Map<String, Object?>;
      final restored = Searchlight.fromJson(decoded);

      expect(restored.count, equals(2));
      expect(restored.getById('a'), isNotNull);
      expect(restored.getById('d'), isNotNull);
      expect(restored.getById('b'), isNull);
      expect(restored.getById('c'), isNull);

      // Should be able to insert new docs without collisions
      restored.insert({'id': 'e', 'title': 'Epsilon'});
      expect(restored.count, equals(3));
    });

    test('fromJson corrects sparse nextInternalId floor from max doc ID', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
      )
        ..insert({'id': 'a', 'title': 'Alpha'})
        ..insert({'id': 'b', 'title': 'Beta'})
        ..insert({'id': 'c', 'title': 'Gamma'})
        ..insert({'id': 'd', 'title': 'Delta'});

      expect(db.remove('b'), isTrue);
      expect(db.remove('c'), isTrue);

      final json = db.toJson();
      final idStore = json['internalDocumentIDStore']! as Map<String, Object?>;
      idStore['nextId'] = 3;

      final restored = Searchlight.fromJson(json)
        ..insert({'id': 'e', 'title': 'Epsilon'})
        ..insert({'id': 'f', 'title': 'Phi'});

      expect(restored.count, 4);
      expect(restored.getById('a')!.getString('title'), 'Alpha');
      expect(restored.getById('d')!.getString('title'), 'Delta');
      expect(restored.getById('e')!.getString('title'), 'Epsilon');
      expect(restored.getById('f')!.getString('title'), 'Phi');
    });

    test('round-trip with geopoint fields through jsonEncode/jsonDecode', () {
      final db = Searchlight.create(
        schema: Schema({
          'name': const TypedField(SchemaType.string),
          'location': const TypedField(SchemaType.geopoint),
        }),
      )
        ..insert({
          'id': 'nyc',
          'name': 'New York',
          'location': const GeoPoint(lat: 40.7128, lon: -74.0060),
        })
        ..insert({
          'id': 'london',
          'name': 'London',
          'location': const GeoPoint(lat: 51.5074, lon: -0.1278),
        });

      // Must survive full JSON string round-trip (the real test of I4)
      final jsonMap = db.toJson();
      final jsonString = jsonEncode(jsonMap);
      final decoded = jsonDecode(jsonString) as Map<String, Object?>;
      final restored = Searchlight.fromJson(decoded);

      expect(restored.count, equals(2));

      final nyc = restored.getById('nyc');
      expect(nyc, isNotNull);
      expect(nyc!.getGeoPoint('location').lat, equals(40.7128));
      expect(nyc.getGeoPoint('location').lon, equals(-74.0060));

      final london = restored.getById('london');
      expect(london, isNotNull);
      expect(london!.getGeoPoint('location').lat, equals(51.5074));
      expect(london.getGeoPoint('location').lon, equals(-0.1278));
    });
  });
}
