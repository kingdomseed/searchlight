// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

void main() {
  group('Algorithm selection', () {
    test('BM25 (default) search works', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'body': const TypedField(SchemaType.string),
        }),
      )..insert({'id': 'doc1', 'title': 'hello world', 'body': 'foo bar'});

      final result = db.search(term: 'hello');
      expect(result.count, 1);
      expect(result.hits.first.id, 'doc1');
      expect(result.hits.first.score, greaterThan(0));
      expect(db.algorithm, SearchAlgorithm.bm25);
    });

    test('QPS: insert and search use QPS algorithm (not BM25)', () {
      // This test verifies QPS wiring by checking that QPS-specific
      // scoring is used. We verify by checking the SearchIndex was
      // created with the correct algorithm and that search still works.
      final db = Searchlight.create(
        schema: Schema({
          'body': const TypedField(SchemaType.string),
        }),
        algorithm: SearchAlgorithm.qps,
      )
        ..insert({
          'id': 'doc1',
          'body': 'The quick brown fox jumps over the lazy dog.',
        })
        ..insert({
          'id': 'doc2',
          'body': 'A lazy cat sleeps on the mat.',
        });

      // Basic search must work with QPS
      final result = db.search(term: 'quick brown');
      expect(result.count, greaterThanOrEqualTo(1));
      expect(result.hits.first.id, 'doc1');
      expect(result.hits.first.score, greaterThan(0));
      expect(db.algorithm, SearchAlgorithm.qps);

      // Verify the index uses QPSStats (algorithm stored on index)
      expect(db.indexAlgorithm, SearchAlgorithm.qps);
    });

    test('QPS: proximity scoring — same sentence scores higher', () {
      final db = Searchlight.create(
        schema: Schema({
          'body': const TypedField(SchemaType.string),
        }),
        algorithm: SearchAlgorithm.qps,
      )
        // "brown" and "fox" in the same sentence
        ..insert({
          'id': 'close',
          'body': 'The quick brown fox jumps over the lazy dog.',
        })
        // "brown" and "fox" in different sentences
        ..insert({
          'id': 'far',
          'body': 'The brown bear sleeps. A fox runs through the forest.',
        });

      final result = db.search(term: 'brown fox');
      expect(result.count, 2);
      // The doc with both terms in the same sentence should score higher
      // due to QPS proximity bonus
      expect(result.hits.first.id, 'close');
      expect(result.hits[0].score, greaterThan(result.hits[1].score));
    });

    test('PT15: create with algorithm, insert docs, search returns results',
        () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'body': const TypedField(SchemaType.string),
        }),
        algorithm: SearchAlgorithm.pt15,
      )
        ..insert({'id': 'doc1', 'title': 'hello world', 'body': 'foo bar'})
        ..insert({'id': 'doc2', 'title': 'goodbye moon', 'body': 'baz qux'});

      final result = db.search(term: 'hello');
      expect(result.count, 1);
      expect(result.hits.first.id, 'doc1');
      expect(result.hits.first.score, greaterThan(0));
      expect(db.algorithm, SearchAlgorithm.pt15);
      expect(db.indexAlgorithm, SearchAlgorithm.pt15);
    });

    test('PT15: positional scoring — term at start scores higher', () {
      final db = Searchlight.create(
        schema: Schema({
          'body': const TypedField(SchemaType.string),
        }),
        algorithm: SearchAlgorithm.pt15,
      )
        // "hello" at the start of a longer document
        ..insert({
          'id': 'start',
          'body':
              'hello world this is a document with many words to fill up space',
        })
        // "hello" at the end of a longer document
        ..insert({
          'id': 'end',
          'body':
              'this is a document with many words to fill up space hello world',
        });

      final result = db.search(term: 'hello');
      expect(result.count, 2);
      // PT15 scores based on position: terms at the start get higher buckets
      expect(result.hits.first.id, 'start');
      expect(result.hits[0].score, greaterThan(result.hits[1].score));
    });

    test('PT15: prefix matching works', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        algorithm: SearchAlgorithm.pt15,
      )
        ..insert({'id': 'doc1', 'title': 'hello world'})
        ..insert({'id': 'doc2', 'title': 'goodbye moon'});

      // PT15 stores all prefixes, so "hel" should find "hello"
      final result = db.search(term: 'hel');
      expect(result.count, 1);
      expect(result.hits.first.id, 'doc1');
    });

    test('All algorithms: non-string fields work identically', () {
      for (final algo in SearchAlgorithm.values) {
        final db = Searchlight.create(
          schema: Schema({
            'title': const TypedField(SchemaType.string),
            'price': const TypedField(SchemaType.number),
            'active': const TypedField(SchemaType.boolean),
            'category': const TypedField(SchemaType.enumType),
          }),
          algorithm: algo,
        )
          ..insert({
            'id': 'doc1',
            'title': 'hello world',
            'price': 10,
            'active': true,
            'category': 'books',
          })
          ..insert({
            'id': 'doc2',
            'title': 'goodbye moon',
            'price': 20,
            'active': false,
            'category': 'movies',
          });

        // Number filter
        final priceResult = db.search(
          where: {'price': const GtFilter(15)},
        );
        expect(
          priceResult.count,
          1,
          reason: '$algo: number filter should work',
        );
        expect(priceResult.hits.first.id, 'doc2');

        // Boolean filter
        final activeResult = db.search(
          where: {'active': const EqFilter(true)},
        );
        expect(
          activeResult.count,
          1,
          reason: '$algo: boolean filter should work',
        );
        expect(activeResult.hits.first.id, 'doc1');

        // Enum filter
        final categoryResult = db.search(
          where: {'category': const EqFilter('movies')},
        );
        expect(
          categoryResult.count,
          1,
          reason: '$algo: enum filter should work',
        );
        expect(categoryResult.hits.first.id, 'doc2');
      }
    });

    test('reindex: switch from BM25 to QPS, search still works', () {
      final bm25 = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'body': const TypedField(SchemaType.string),
        }),
      )
        ..insert({'id': 'doc1', 'title': 'hello world', 'body': 'foo bar'})
        ..insert({
          'id': 'doc2',
          'title': 'goodbye moon',
          'body': 'baz qux',
        });

      final qps = bm25.reindex(algorithm: SearchAlgorithm.qps);

      expect(qps.algorithm, SearchAlgorithm.qps);
      expect(qps.indexAlgorithm, SearchAlgorithm.qps);
      expect(qps.count, 2);

      final result = qps.search(term: 'hello');
      expect(result.count, 1);
      expect(result.hits.first.id, 'doc1');
      expect(result.hits.first.score, greaterThan(0));
    });

    test('reindex: switch from QPS to PT15, search still works', () {
      final qps = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        algorithm: SearchAlgorithm.qps,
      )
        ..insert({'id': 'doc1', 'title': 'hello world'})
        ..insert({'id': 'doc2', 'title': 'goodbye moon'});

      final pt15 = qps.reindex(algorithm: SearchAlgorithm.pt15);

      expect(pt15.algorithm, SearchAlgorithm.pt15);
      expect(pt15.indexAlgorithm, SearchAlgorithm.pt15);
      expect(pt15.count, 2);

      final result = pt15.search(term: 'hello');
      expect(result.count, 1);
      expect(result.hits.first.id, 'doc1');
      expect(result.hits.first.score, greaterThan(0));
    });

    test('reindex: document count preserved after reindex', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'price': const TypedField(SchemaType.number),
          'active': const TypedField(SchemaType.boolean),
        }),
      )
        ..insert({
          'id': 'doc1',
          'title': 'hello',
          'price': 10,
          'active': true,
        })
        ..insert({
          'id': 'doc2',
          'title': 'world',
          'price': 20,
          'active': false,
        })
        ..insert({
          'id': 'doc3',
          'title': 'test',
          'price': 30,
          'active': true,
        });

      expect(db.count, 3);

      final reindexed = db.reindex(algorithm: SearchAlgorithm.pt15);
      expect(reindexed.count, 3);

      // Verify all documents are accessible by ID
      expect(reindexed.getById('doc1'), isNotNull);
      expect(reindexed.getById('doc2'), isNotNull);
      expect(reindexed.getById('doc3'), isNotNull);

      // Verify non-string fields work after reindex
      final priceResult = reindexed.search(
        where: {'price': const GtFilter(15)},
      );
      expect(priceResult.count, 2);
    });
  });

  group('PT15 parameter validation (Phase 6 audit F1/F2)', () {
    test('PT15 search with tolerance > 0 throws QueryException', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        algorithm: SearchAlgorithm.pt15,
      )..insert({'id': 'doc1', 'title': 'hello world'});

      expect(
        () => db.search(term: 'hello', tolerance: 2),
        throwsA(isA<QueryException>()),
      );
    });

    test('PT15 search with exact: true throws QueryException', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        algorithm: SearchAlgorithm.pt15,
      )..insert({'id': 'doc1', 'title': 'hello world'});

      expect(
        () => db.search(term: 'hello', exact: true),
        throwsA(isA<QueryException>()),
      );
    });
  });
}
