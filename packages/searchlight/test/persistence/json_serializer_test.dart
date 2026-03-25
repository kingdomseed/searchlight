// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

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

    test('fromJson with wrong formatVersion throws SerializationException', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
      );
      final json = db.toJson();

      // Tamper with format version
      json['formatVersion'] = 999;

      expect(
        () => Searchlight.fromJson(json),
        throwsA(isA<SerializationException>()),
      );
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
  });
}
