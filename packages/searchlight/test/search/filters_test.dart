// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

void main() {
  group('Searchlight search() with where filters', () {
    test('filter by boolean field returns only matching docs', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'active': const TypedField(SchemaType.boolean),
        }),
      );

      db
        ..insert({'id': 'doc1', 'title': 'Alpha', 'active': true})
        ..insert({'id': 'doc2', 'title': 'Beta', 'active': false})
        ..insert({'id': 'doc3', 'title': 'Gamma', 'active': true});

      final result = db.search(where: {'active': eq(true)});

      expect(result.count, 2);
      final ids = result.hits.map((h) => h.id).toSet();
      expect(ids, containsAll(['doc1', 'doc3']));
      expect(ids, isNot(contains('doc2')));

      // All scores should be 0 (no search term)
      for (final hit in result.hits) {
        expect(hit.score, 0.0);
      }
    });

    test('filter by number eq returns exact match', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'price': const TypedField(SchemaType.number),
        }),
      );

      db
        ..insert({'id': 'doc1', 'title': 'A', 'price': 30})
        ..insert({'id': 'doc2', 'title': 'B', 'price': 50})
        ..insert({'id': 'doc3', 'title': 'C', 'price': 70});

      final result = db.search(where: {'price': eq(50)});

      expect(result.count, 1);
      expect(result.hits.first.id, 'doc2');
      expect(result.hits.first.score, 0.0);
    });

    test('filter by number gt returns docs with value > threshold', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'price': const TypedField(SchemaType.number),
        }),
      );

      db
        ..insert({'id': 'doc1', 'title': 'A', 'price': 30})
        ..insert({'id': 'doc2', 'title': 'B', 'price': 50})
        ..insert({'id': 'doc3', 'title': 'C', 'price': 70});

      final result = db.search(where: {'price': gt(50)});

      expect(result.count, 1);
      expect(result.hits.first.id, 'doc3');
    });

    test('filter by number between returns docs in range', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'price': const TypedField(SchemaType.number),
        }),
      );

      db
        ..insert({'id': 'doc1', 'title': 'A', 'price': 10})
        ..insert({'id': 'doc2', 'title': 'B', 'price': 30})
        ..insert({'id': 'doc3', 'title': 'C', 'price': 50})
        ..insert({'id': 'doc4', 'title': 'D', 'price': 80})
        ..insert({'id': 'doc5', 'title': 'E', 'price': 100});

      final result = db.search(where: {'price': between(20, 80)});

      expect(result.count, 3);
      final ids = result.hits.map((h) => h.id).toSet();
      expect(ids, containsAll(['doc2', 'doc3', 'doc4']));
    });

    test('filter by enum eq returns matching category', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'category': const TypedField(SchemaType.enumType),
        }),
      );

      db
        ..insert({'id': 'doc1', 'title': 'A', 'category': 'electronics'})
        ..insert({'id': 'doc2', 'title': 'B', 'category': 'books'})
        ..insert({'id': 'doc3', 'title': 'C', 'category': 'electronics'});

      final result = db.search(where: {'category': eq('electronics')});

      expect(result.count, 2);
      final ids = result.hits.map((h) => h.id).toSet();
      expect(ids, containsAll(['doc1', 'doc3']));
    });

    test('filter by enum in returns union of matching categories', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'category': const TypedField(SchemaType.enumType),
        }),
      );

      db
        ..insert({'id': 'doc1', 'title': 'A', 'category': 'electronics'})
        ..insert({'id': 'doc2', 'title': 'B', 'category': 'books'})
        ..insert({'id': 'doc3', 'title': 'C', 'category': 'clothing'})
        ..insert({'id': 'doc4', 'title': 'D', 'category': 'books'});

      final result = db.search(
        where: {
          'category': inFilter(['electronics', 'books'])
        },
      );

      expect(result.count, 3);
      final ids = result.hits.map((h) => h.id).toSet();
      expect(ids, containsAll(['doc1', 'doc2', 'doc4']));
      expect(ids, isNot(contains('doc3')));
    });

    test('multiple filters are ANDed (intersection)', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'price': const TypedField(SchemaType.number),
          'active': const TypedField(SchemaType.boolean),
        }),
      );

      db
        ..insert({'id': 'doc1', 'title': 'A', 'price': 20, 'active': true})
        ..insert({'id': 'doc2', 'title': 'B', 'price': 5, 'active': true})
        ..insert({'id': 'doc3', 'title': 'C', 'price': 30, 'active': false})
        ..insert({'id': 'doc4', 'title': 'D', 'price': 50, 'active': true});

      final result = db.search(
        where: {'price': gt(10), 'active': eq(true)},
      );

      // Only doc1 (price 20, active) and doc4 (price 50, active) match both
      expect(result.count, 2);
      final ids = result.hits.map((h) => h.id).toSet();
      expect(ids, containsAll(['doc1', 'doc4']));
    });

    test('filter with search term scores only filtered docs', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'price': const TypedField(SchemaType.number),
        }),
      );

      db
        ..insert({'id': 'doc1', 'title': 'phone case', 'price': 20})
        ..insert({'id': 'doc2', 'title': 'phone charger', 'price': 600})
        ..insert({'id': 'doc3', 'title': 'phone stand', 'price': 30});

      final result = db.search(
        term: 'phone',
        where: {'price': lt(500)},
      );

      // doc2 (price 600) excluded by filter
      expect(result.count, 2);
      final ids = result.hits.map((h) => h.id).toSet();
      expect(ids, containsAll(['doc1', 'doc3']));
      expect(ids, isNot(contains('doc2')));

      // All hits should have score > 0 (search term matched)
      for (final hit in result.hits) {
        expect(hit.score, greaterThan(0));
      }
    });

    test('filter without search term returns matching docs with score 0', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'active': const TypedField(SchemaType.boolean),
        }),
      );

      db
        ..insert({'id': 'doc1', 'title': 'A', 'active': true})
        ..insert({'id': 'doc2', 'title': 'B', 'active': false})
        ..insert({'id': 'doc3', 'title': 'C', 'active': true})
        ..insert({'id': 'doc4', 'title': 'D', 'active': true});

      final result = db.search(where: {'active': eq(true)});

      expect(result.count, 3);
      final ids = result.hits.map((h) => h.id).toSet();
      expect(ids, containsAll(['doc1', 'doc3', 'doc4']));

      for (final hit in result.hits) {
        expect(hit.score, 0.0);
      }
    });

    test('filter on unknown field throws QueryException', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
      );

      db.insert({'id': 'doc1', 'title': 'A'});

      expect(
        () => db.search(where: {'nonexistent': eq(true)}),
        throwsA(isA<QueryException>()),
      );
    });

    test('geoRadius filter returns nearby docs', () {
      final db = Searchlight.create(
        schema: Schema({
          'name': const TypedField(SchemaType.string),
          'location': const TypedField(SchemaType.geopoint),
        }),
      );

      // NYC area points
      db
        ..insert({
          'id': 'nyc',
          'name': 'New York',
          'location': const GeoPoint(lat: 40.7128, lon: -74.0060),
        })
        ..insert({
          'id': 'nj',
          'name': 'Newark NJ',
          'location': const GeoPoint(lat: 40.7357, lon: -74.1724),
        })
        ..insert({
          'id': 'la',
          'name': 'Los Angeles',
          'location': const GeoPoint(lat: 34.0522, lon: -118.2437),
        });

      // Search within 20km of NYC center
      final result = db.search(
        where: {
          'location': geoRadius(
            lat: 40.7128,
            lon: -74.0060,
            radius: 20000, // 20km in meters
          ),
        },
      );

      // NYC and Newark should be within 20km, LA should not
      expect(result.count, 2);
      final ids = result.hits.map((h) => h.id).toSet();
      expect(ids, containsAll(['nyc', 'nj']));
      expect(ids, isNot(contains('la')));
    });
  });
}
