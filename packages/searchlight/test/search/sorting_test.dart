// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/searchlight.dart';
import 'package:searchlight/src/indexing/index_manager.dart' show TokenScore;
import 'package:searchlight/src/indexing/sort_index.dart';
import 'package:test/test.dart';

void main() {
  group('SortIndex', () {
    test('sortBy ascending returns results sorted by field value asc', () {
      final sortIndex = SortIndex()
        // Insert documents with price values
        ..insert(property: 'price', docId: 1, value: 50)
        ..insert(property: 'price', docId: 2, value: 10)
        ..insert(property: 'price', docId: 3, value: 30);

      // Simulate search results (in score order)
      final results = <TokenScore>[
        (1, 1.0),
        (2, 0.9),
        (3, 0.8),
      ];

      final sorted = sortIndex.sortBy(
        results: results,
        property: 'price',
        order: SortOrder.asc,
      );

      // Should be sorted by price ascending: 10, 30, 50
      expect(sorted[0].$1, 2); // price=10
      expect(sorted[1].$1, 3); // price=30
      expect(sorted[2].$1, 1); // price=50
    });

    test('sortBy descending returns results sorted by field value desc', () {
      final sortIndex = SortIndex()
        ..insert(property: 'price', docId: 1, value: 50)
        ..insert(property: 'price', docId: 2, value: 10)
        ..insert(property: 'price', docId: 3, value: 30);

      final results = <TokenScore>[
        (1, 1.0),
        (2, 0.9),
        (3, 0.8),
      ];

      final sorted = sortIndex.sortBy(
        results: results,
        property: 'price',
        order: SortOrder.desc,
      );

      // Should be sorted by price descending: 50, 30, 10
      expect(sorted[0].$1, 1); // price=50
      expect(sorted[1].$1, 3); // price=30
      expect(sorted[2].$1, 2); // price=10
    });

    test('sortBy overrides score-based sorting', () {
      final sortIndex = SortIndex()
        // Doc 1 has highest score but highest price
        // Doc 2 has middle score and lowest price
        // Doc 3 has lowest score and middle price
        ..insert(property: 'price', docId: 1, value: 100)
        ..insert(property: 'price', docId: 2, value: 10)
        ..insert(property: 'price', docId: 3, value: 50);

      // Results are in score order (highest first)
      final results = <TokenScore>[
        (1, 10.0), // highest score, highest price
        (2, 5.0), // medium score, lowest price
        (3, 1.0), // lowest score, medium price
      ];

      final sorted = sortIndex.sortBy(
        results: results,
        property: 'price',
        order: SortOrder.asc,
      );

      // Sort by price asc should override score order
      expect(sorted[0].$1, 2); // price=10 (was ranked 2nd by score)
      expect(sorted[1].$1, 3); // price=50 (was ranked 3rd by score)
      expect(sorted[2].$1, 1); // price=100 (was ranked 1st by score)

      // Scores are preserved
      expect(sorted[0].$2, 5.0);
      expect(sorted[1].$2, 1.0);
      expect(sorted[2].$2, 10.0);
    });

    test('sortBy on booleans does not reverse equal false values', () {
      final sortIndex = SortIndex()
        ..insert(property: 'active', docId: 1, value: false)
        ..insert(property: 'active', docId: 2, value: false)
        ..insert(property: 'active', docId: 3, value: true);

      final results = <TokenScore>[
        (1, 1.0),
        (2, 0.9),
        (3, 0.8),
      ];

      final sorted = sortIndex.sortBy(
        results: results,
        property: 'active',
        order: SortOrder.asc,
      );

      expect(sorted.map((entry) => entry.$1).toList(), [1, 2, 3]);
    });

    test('sortBy on norwegian strings uses locale-aware ordering', () {
      final sortIndex = SortIndex(language: 'norwegian')
        ..insert(property: 'title', docId: 1, value: 'å')
        ..insert(property: 'title', docId: 2, value: 'a')
        ..insert(property: 'title', docId: 3, value: 'ø')
        ..insert(property: 'title', docId: 4, value: 'o')
        ..insert(property: 'title', docId: 5, value: 'æ');

      final results = <TokenScore>[
        (1, 1.0),
        (2, 0.9),
        (3, 0.8),
        (4, 0.7),
        (5, 0.6),
      ];

      final sorted = sortIndex.sortBy(
        results: results,
        property: 'title',
        order: SortOrder.asc,
      );

      expect(sorted.map((entry) => entry.$1).toList(), [2, 4, 5, 3, 1]);
    });
  });

  group('Searchlight.search() with sortBy', () {
    test('search with sortBy returns results sorted by field value', () {
      final schema = Schema({
        'title': const TypedField(SchemaType.string),
        'price': const TypedField(SchemaType.number),
      });

      final db = Searchlight.create(schema: schema)
        ..insert({
          'id': 'expensive',
          'title': 'hello A',
          'price': 100,
        })
        ..insert({
          'id': 'cheap',
          'title': 'hello B',
          'price': 10,
        })
        ..insert({
          'id': 'mid',
          'title': 'hello C',
          'price': 50,
        });

      // Search with sort by price ascending
      final result = db.search(
        term: 'hello',
        sortBy: const SortBy(field: 'price', order: SortOrder.asc),
      );

      expect(result.count, 3);
      expect(result.hits, hasLength(3));

      // Results should be sorted by price ascending, not by score
      expect(result.hits[0].id, 'cheap'); // price=10
      expect(result.hits[1].id, 'mid'); // price=50
      expect(result.hits[2].id, 'expensive'); // price=100
    });

    test(
      'search with sortBy desc returns results sorted descending',
      () {
        final schema = Schema({
          'title': const TypedField(SchemaType.string),
          'price': const TypedField(SchemaType.number),
        });

        final db = Searchlight.create(schema: schema)
          ..insert({
            'id': 'expensive',
            'title': 'hello A',
            'price': 100,
          })
          ..insert({
            'id': 'cheap',
            'title': 'hello B',
            'price': 10,
          })
          ..insert({
            'id': 'mid',
            'title': 'hello C',
            'price': 50,
          });

        final result = db.search(
          term: 'hello',
          sortBy: const SortBy(
            field: 'price',
            order: SortOrder.desc,
          ),
        );

        expect(result.hits[0].id, 'expensive'); // price=100
        expect(result.hits[1].id, 'mid'); // price=50
        expect(result.hits[2].id, 'cheap'); // price=10
      },
    );
  });
}
