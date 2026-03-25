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

      final db = Searchlight.create(schema: schema);
      db
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

      final db = Searchlight.create(schema: schema);
      db
        ..insert({'id': 'doc1', 'title': 'A', 'category': 'electronics'})
        ..insert({'id': 'doc2', 'title': 'B', 'category': 'electronics'})
        ..insert({'id': 'doc3', 'title': 'C', 'category': 'electronics'})
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
  });

  group('Searchlight.search() with groupBy', () {
    test('search with groupBy returns groups in SearchResult', () {
      final schema = Schema({
        'title': const TypedField(SchemaType.string),
        'category': const TypedField(SchemaType.string),
      });

      final db = Searchlight.create(schema: schema);
      db
        ..insert({'id': 'doc1', 'title': 'hello world', 'category': 'tech'})
        ..insert({'id': 'doc2', 'title': 'hello dart', 'category': 'tech'})
        ..insert(
          {'id': 'doc3', 'title': 'hello flutter', 'category': 'mobile'},
        );

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
  });
}
