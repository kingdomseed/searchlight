// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/searchlight.dart';
import 'package:searchlight/src/indexing/index_manager.dart' show TokenScore;
import 'package:searchlight/src/search/grouping.dart';
import 'package:test/test.dart';

void main() {
  group('getGroups', () {
    test('groups results by field value', () {
      final schema = Schema({
        'title': const TypedField(SchemaType.string),
        'category': const TypedField(SchemaType.string),
      });

      final db = Searchlight.create(schema: schema)
        ..insert({'id': 'doc1', 'title': 'A', 'category': 'electronics'})
        ..insert({'id': 'doc2', 'title': 'B', 'category': 'electronics'})
        ..insert({'id': 'doc3', 'title': 'C', 'category': 'books'})
        ..insert({'id': 'doc4', 'title': 'D', 'category': 'books'})
        ..insert({'id': 'doc5', 'title': 'E', 'category': 'toys'});

      // Simulate search results — all 5 docs
      final results = <TokenScore>[
        (1, 1.0),
        (2, 0.9),
        (3, 0.8),
        (4, 0.7),
        (5, 0.6),
      ];

      final groups = getGroups(
        documents: db.documentsForFacets,
        externalIds: db.externalIdsMap,
        results: results,
        groupBy: const GroupBy(field: 'category', limit: 10),
      );

      expect(groups, hasLength(3));

      // Find each group
      final electronicsGroup =
          groups.firstWhere((g) => g.values.contains('electronics'));
      expect(electronicsGroup.result, hasLength(2));

      final booksGroup = groups.firstWhere((g) => g.values.contains('books'));
      expect(booksGroup.result, hasLength(2));

      final toysGroup = groups.firstWhere((g) => g.values.contains('toys'));
      expect(toysGroup.result, hasLength(1));
    });

    test('groups with limit restricts docs per group', () {
      final schema = Schema({
        'title': const TypedField(SchemaType.string),
        'category': const TypedField(SchemaType.string),
      });

      final db = Searchlight.create(schema: schema)
        ..insert({
          'id': 'doc1',
          'title': 'A',
          'category': 'electronics',
        })
        ..insert({
          'id': 'doc2',
          'title': 'B',
          'category': 'electronics',
        })
        ..insert({
          'id': 'doc3',
          'title': 'C',
          'category': 'electronics',
        })
        ..insert({'id': 'doc4', 'title': 'D', 'category': 'books'})
        ..insert({'id': 'doc5', 'title': 'E', 'category': 'books'});

      final results = <TokenScore>[
        (1, 1.0),
        (2, 0.9),
        (3, 0.8),
        (4, 0.7),
        (5, 0.6),
      ];

      final groups = getGroups(
        documents: db.documentsForFacets,
        externalIds: db.externalIdsMap,
        results: results,
        groupBy: const GroupBy(field: 'category', limit: 2),
      );

      // Electronics has 3 docs but limit is 2
      final electronicsGroup =
          groups.firstWhere((g) => g.values.contains('electronics'));
      expect(electronicsGroup.result, hasLength(2));

      // Books has 2 docs, within limit
      final booksGroup = groups.firstWhere((g) => g.values.contains('books'));
      expect(booksGroup.result, hasLength(2));
    });

    // Item 5: Multi-property grouping with Cartesian product
    test('multi-property grouping produces Cartesian product', () {
      final schema = Schema({
        'title': const TypedField(SchemaType.string),
        'category': const TypedField(SchemaType.string),
        'status': const TypedField(SchemaType.string),
      });

      final db = Searchlight.create(schema: schema)
        ..insert({
          'id': 'doc1',
          'title': 'A',
          'category': 'tech',
          'status': 'active',
        })
        ..insert({
          'id': 'doc2',
          'title': 'B',
          'category': 'tech',
          'status': 'inactive',
        })
        ..insert({
          'id': 'doc3',
          'title': 'C',
          'category': 'health',
          'status': 'active',
        });

      final results = <TokenScore>[
        (1, 1.0),
        (2, 0.9),
        (3, 0.8),
      ];

      final groups = getGroups(
        documents: db.documentsForFacets,
        externalIds: db.externalIdsMap,
        results: results,
        groupBy: const GroupBy.properties(
          properties: ['category', 'status'],
          limit: 10,
        ),
      );

      // Should produce groups for existing combinations only:
      // (tech, active), (tech, inactive), (health, active)
      // (health, inactive) would be empty and excluded
      expect(groups, hasLength(3));

      final techActive = groups.firstWhere(
        (g) => g.values.contains('tech') && g.values.contains('active'),
      );
      expect(techActive.result, hasLength(1)); // doc1

      final techInactive = groups.firstWhere(
        (g) => g.values.contains('tech') && g.values.contains('inactive'),
      );
      expect(techInactive.result, hasLength(1)); // doc2

      final healthActive = groups.firstWhere(
        (g) => g.values.contains('health') && g.values.contains('active'),
      );
      expect(healthActive.result, hasLength(1)); // doc3
    });

    // Item 15: Group property validation
    test('throws for unknown group property', () {
      final schema = Schema({
        'title': const TypedField(SchemaType.string),
      });

      final db = Searchlight.create(schema: schema)
        ..insert({'id': 'doc1', 'title': 'A'});

      final results = <TokenScore>[(1, 1.0)];

      expect(
        () => getGroups(
          documents: db.documentsForFacets,
          externalIds: db.externalIdsMap,
          results: results,
          groupBy: const GroupBy(field: 'nonexistent', limit: 10),
          schemaProperties: db.propertiesWithTypes,
        ),
        throwsA(isA<QueryException>()),
      );
    });

    test('throws for invalid group property type (geopoint)', () {
      final schema = Schema({
        'title': const TypedField(SchemaType.string),
        'location': const TypedField(SchemaType.geopoint),
      });

      final db = Searchlight.create(schema: schema)
        ..insert({
          'id': 'doc1',
          'title': 'A',
          'location': const GeoPoint(lat: 0, lon: 0),
        });

      final results = <TokenScore>[(1, 1.0)];

      expect(
        () => getGroups(
          documents: db.documentsForFacets,
          externalIds: db.externalIdsMap,
          results: results,
          groupBy: const GroupBy(field: 'location', limit: 10),
          schemaProperties: db.propertiesWithTypes,
        ),
        throwsA(isA<QueryException>()),
      );
    });

    // Item 16: Custom reduce for groups
    test('custom reduce aggregates group results', () {
      final schema = Schema({
        'title': const TypedField(SchemaType.string),
        'category': const TypedField(SchemaType.string),
      });

      final db = Searchlight.create(schema: schema)
        ..insert({'id': 'doc1', 'title': 'A', 'category': 'tech'})
        ..insert({'id': 'doc2', 'title': 'B', 'category': 'tech'})
        ..insert({
          'id': 'doc3',
          'title': 'C',
          'category': 'health',
        });

      final results = <TokenScore>[
        (1, 1.0),
        (2, 0.9),
        (3, 0.8),
      ];

      final groups = getGroups(
        documents: db.documentsForFacets,
        externalIds: db.externalIdsMap,
        results: results,
        groupBy: GroupBy(
          field: 'category',
          limit: 10,
          reduce: GroupReduce<List<SearchHit>>(
            reducer: (values, acc, res, index) {
              acc[index] = res;
              return acc;
            },
            getInitialValue: (length) => List<SearchHit>.filled(
              length,
              const SearchHit(
                id: '',
                score: 0,
                document: Document({}),
              ),
            ),
          ),
        ),
      );

      // Verify reduce was applied (same output as default in this case)
      expect(groups, hasLength(2));
      final techGroup = groups.firstWhere((g) => g.values.contains('tech'));
      expect(techGroup.result, hasLength(2));
    });
  });

  group('Searchlight.search() with groupBy', () {
    test('search with groupBy returns groups in SearchResult', () {
      final schema = Schema({
        'title': const TypedField(SchemaType.string),
        'category': const TypedField(SchemaType.string),
      });

      final db = Searchlight.create(schema: schema)
        ..insert({
          'id': 'doc1',
          'title': 'hello world',
          'category': 'tech',
        })
        ..insert({
          'id': 'doc2',
          'title': 'hello dart',
          'category': 'tech',
        })
        ..insert({
          'id': 'doc3',
          'title': 'hello flutter',
          'category': 'mobile',
        });

      final result = db.search(
        term: 'hello',
        groupBy: const GroupBy(field: 'category', limit: 3),
      );

      expect(result.count, 3);
      expect(result.groups, isNotNull);
      expect(result.groups, hasLength(2)); // tech and mobile

      final techGroup =
          result.groups!.firstWhere((g) => g.values.contains('tech'));
      expect(techGroup.result, hasLength(2));

      final mobileGroup =
          result.groups!.firstWhere((g) => g.values.contains('mobile'));
      expect(mobileGroup.result, hasLength(1));
    });

    // Item 15: Validation through database layer
    test('search with invalid groupBy property throws', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
      )..insert({'id': 'doc1', 'title': 'hello'});

      expect(
        () => db.search(
          term: 'hello',
          groupBy: const GroupBy(
            field: 'nonexistent',
            limit: 10,
          ),
        ),
        throwsA(isA<QueryException>()),
      );
    });
  });
}
