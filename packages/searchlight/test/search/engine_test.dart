// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

void main() {
  group('Searchlight search()', () {
    late Searchlight db;

    setUp(() {
      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'body': const TypedField(SchemaType.string),
          'price': const TypedField(SchemaType.number),
        }),
      );
    });

    tearDown(() async {
      await db.dispose();
    });

    test('search by matching term returns the document with score > 0', () {
      db.insert({
        'id': 'doc1',
        'title': 'hello world',
        'body': 'foo',
        'price': 10,
      });

      final result = db.search(term: 'hello');

      expect(result.count, 1);
      expect(result.hits, hasLength(1));
      expect(result.hits.first.id, 'doc1');
      expect(result.hits.first.score, greaterThan(0));
    });

    test('search returns results sorted by score descending', () {
      // Doc with "hello" in title only
      db
        ..insert(
          {'id': 'a', 'title': 'hello', 'body': 'nothing', 'price': 1},
        )
        // Doc with "hello" in both title and body — higher relevance
        ..insert({
          'id': 'b',
          'title': 'hello world',
          'body': 'hello again',
          'price': 2,
        });

      final result = db.search(term: 'hello');

      expect(result.hits.length, greaterThanOrEqualTo(2));
      // First hit should have score >= second hit
      expect(
        result.hits[0].score,
        greaterThanOrEqualTo(result.hits[1].score),
      );
    });

    test('search with limit restricts result count', () {
      db
        ..insert(
          {'id': 'a', 'title': 'hello alpha', 'body': 'x', 'price': 1},
        )
        ..insert(
          {'id': 'b', 'title': 'hello beta', 'body': 'x', 'price': 2},
        )
        ..insert(
          {'id': 'c', 'title': 'hello gamma', 'body': 'x', 'price': 3},
        );

      final result = db.search(term: 'hello', limit: 2);

      expect(result.hits, hasLength(2));
      expect(result.count, 3); // total matches, not just page
    });

    test('search with offset skips results', () {
      db
        ..insert(
          {'id': 'a', 'title': 'hello alpha', 'body': 'x', 'price': 1},
        )
        ..insert(
          {'id': 'b', 'title': 'hello beta', 'body': 'x', 'price': 2},
        )
        ..insert(
          {'id': 'c', 'title': 'hello gamma', 'body': 'x', 'price': 3},
        );

      final all = db.search(term: 'hello');
      final page2 = db.search(term: 'hello', offset: 1);

      expect(page2.hits, hasLength(2));
      expect(page2.count, 3); // total is still 3
      // The first hit from page2 should be the second hit from all
      expect(page2.hits.first.id, all.hits[1].id);
    });

    test('search with no matching term returns empty results', () {
      db.insert(
        {'id': 'a', 'title': 'hello world', 'body': 'x', 'price': 1},
      );

      final result = db.search(term: 'nonexistent');

      expect(result.count, 0);
      expect(result.hits, isEmpty);
    });

    test('search with empty term returns all documents with score 0', () {
      db
        ..insert(
          {'id': 'a', 'title': 'hello', 'body': 'x', 'price': 1},
        )
        ..insert(
          {'id': 'b', 'title': 'world', 'body': 'y', 'price': 2},
        );

      final result = db.search(); // empty term

      expect(result.count, 2);
      expect(result.hits, hasLength(2));
      for (final hit in result.hits) {
        expect(hit.score, 0.0);
      }
    });

    test('search with properties restricts which fields are searched', () {
      // "hello" appears only in body, not in title
      db.insert(
        {'id': 'a', 'title': 'world', 'body': 'hello', 'price': 1},
      );

      // Search only title — should NOT find "hello"
      final titleOnly = db.search(term: 'hello', properties: ['title']);
      expect(titleOnly.count, 0);

      // Search only body — should find "hello"
      final bodyOnly = db.search(term: 'hello', properties: ['body']);
      expect(bodyOnly.count, 1);
      expect(bodyOnly.hits.first.id, 'a');
    });

    test('search with tolerance: 1 matches typos', () {
      db.insert(
        {'id': 'a', 'title': 'javascript', 'body': 'x', 'price': 1},
      );

      // "javscript" is 1 edit away from "javascript"
      final result = db.search(term: 'javscript', tolerance: 1);

      expect(result.count, 1);
      expect(result.hits.first.id, 'a');
    });

    test('search with exact: true requires exact term match', () {
      final dbExact = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
      )
        ..insert({'id': 'a', 'title': 'cat'})
        ..insert({'id': 'b', 'title': 'catalog'});

      // Non-exact search — "cat" is a prefix of "catalog" tokens
      // (after stemming "cat" -> "cat", "catalog" -> "catalog")
      final nonExact = dbExact.search(term: 'cat');
      // Exact search should only match "cat" exactly
      final exactResult = dbExact.search(term: 'cat', exact: true);

      // "cat" exact should find only the document with exact token "cat"
      expect(exactResult.hits.any((h) => h.id == 'a'), isTrue);
      // "catalog" stem is "catalog", which is not "cat" exactly
      expect(exactResult.hits.any((h) => h.id == 'b'), isFalse);
      // Non-exact may find both (prefix match)
      expect(nonExact.count, greaterThanOrEqualTo(1));
    });

    test('search with threshold: 0 requires all terms to match (AND)', () {
      db
        ..insert({
          'id': 'a',
          'title': 'hello world',
          'body': 'x',
          'price': 1,
        })
        ..insert({
          'id': 'b',
          'title': 'hello',
          'body': 'x',
          'price': 2,
        });

      // threshold=0 means ALL terms must match
      final result = db.search(term: 'hello world', threshold: 0);

      // Only doc 'a' has both "hello" and "world"
      expect(result.hits.any((h) => h.id == 'a'), isTrue);
      expect(result.hits.any((h) => h.id == 'b'), isFalse);
    });

    test('search with threshold: 1 returns any matching term (OR)', () {
      db
        ..insert({
          'id': 'a',
          'title': 'hello world',
          'body': 'x',
          'price': 1,
        })
        ..insert({
          'id': 'b',
          'title': 'hello',
          'body': 'x',
          'price': 2,
        });

      // threshold=1 (default) means ANY term can match
      final result = db.search(term: 'hello world');

      // Both docs have at least "hello"
      expect(result.hits.any((h) => h.id == 'a'), isTrue);
      expect(result.hits.any((h) => h.id == 'b'), isTrue);
    });

    test('search with boost increases score for boosted fields', () {
      // Doc 'a' has "hello" in body only
      db
        ..insert(
          {'id': 'a', 'title': 'nothing', 'body': 'hello', 'price': 1},
        )
        // Doc 'b' has "hello" in title only
        ..insert(
          {'id': 'b', 'title': 'hello', 'body': 'nothing', 'price': 2},
        );

      // Without boost, scores may be similar
      final noBoosted = db.search(term: 'hello');

      // With heavy boost on body, doc 'a' should score higher
      final boosted = db.search(
        term: 'hello',
        boost: {'body': 10.0},
      );

      // Find doc 'a' score in both
      final aScoreNoBoosted =
          noBoosted.hits.firstWhere((h) => h.id == 'a').score;
      final aScoreBoosted = boosted.hits.firstWhere((h) => h.id == 'a').score;

      expect(aScoreBoosted, greaterThan(aScoreNoBoosted));
    });

    test('count in SearchResult reflects total matches, not just page', () {
      for (var i = 0; i < 25; i++) {
        db.insert({
          'id': 'doc$i',
          'title': 'hello $i',
          'body': 'x',
          'price': i,
        });
      }

      // Default limit is 10
      final result = db.search(term: 'hello');

      expect(result.hits, hasLength(10));
      expect(result.count, 25);
    });

    test('elapsed in SearchResult is a non-negative Duration', () {
      db.insert(
        {'id': 'a', 'title': 'hello', 'body': 'x', 'price': 1},
      );

      final result = db.search(term: 'hello');

      expect(result.elapsed, isA<Duration>());
      expect(result.elapsed.inMicroseconds, greaterThanOrEqualTo(0));
    });

    test('after remove, search no longer finds the document', () {
      db.insert(
        {'id': 'a', 'title': 'hello world', 'body': 'x', 'price': 1},
      );

      // Verify it's findable before removal
      final before = db.search(term: 'hello');
      expect(before.count, 1);

      db.remove('a');

      final after = db.search(term: 'hello');
      expect(after.count, 0);
      expect(after.hits, isEmpty);
    });

    test('not filter count matches hits after deleting a document', () {
      final filteredDb = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'active': const TypedField(SchemaType.boolean),
        }),
      )
        ..insert({'id': 'doc1', 'title': 'hello alpha', 'active': true})
        ..insert({'id': 'doc2', 'title': 'hello beta', 'active': false})
        ..insert({'id': 'doc3', 'title': 'hello gamma', 'active': true})
        ..remove('doc2');

      final result = filteredDb.search(
        term: 'hello',
        where: {
          'logic': not({'active': eq(false)}),
        },
      );

      expect(result.count, 2);
      expect(result.hits, hasLength(2));
      expect(result.hits.map((h) => h.id).toSet(), {'doc1', 'doc3'});
    });

    // Item 19: Exact-term post-filtering
    test('exact search filters to docs containing whole-word matches', () {
      db
        ..insert({
          'id': 'a',
          'title': 'hello world',
          'body': 'greetings',
          'price': 1,
        })
        ..insert({
          'id': 'b',
          'title': 'helloworld together',
          'body': 'no space',
          'price': 2,
        })
        ..insert({
          'id': 'c',
          'title': 'say hello now',
          'body': 'greeting again',
          'price': 3,
        });

      final result = db.search(term: 'hello', exact: true);

      // Both 'a' and 'c' have 'hello' as a whole word in title
      // 'b' has 'helloworld' which is not a whole word match for 'hello'
      final ids = result.hits.map((h) => h.id).toSet();
      expect(ids, contains('a'));
      expect(ids, contains('c'));
      // 'b' should be excluded by exact post-filtering
      expect(ids, isNot(contains('b')));
    });

    // Item 6: Empty term + properties triggers search path
    test('empty term with properties triggers search (returns all docs)', () {
      db
        ..insert(
          {'id': 'a', 'title': 'hello world', 'body': 'foo', 'price': 1},
        )
        ..insert(
          {'id': 'b', 'title': 'goodbye moon', 'body': 'bar', 'price': 2},
        );

      // In Orama: term='' + properties=['title'] triggers index.search()
      // which pushes '' token and returns all docs that have the property
      final result = db.search(properties: ['title']);

      // Should trigger the search path and find all docs with 'title'
      expect(result.count, 2);
      final ids = result.hits.map((h) => h.id).toSet();
      expect(ids, containsAll(['a', 'b']));
    });

    test('after update, search finds the new document content', () {
      db
        ..insert(
          {'id': 'a', 'title': 'hello world', 'body': 'x', 'price': 1},
        )
        // Update: change title from "hello world" to "goodbye moon"
        ..update('a', {
          'id': 'a',
          'title': 'goodbye moon',
          'body': 'x',
          'price': 1,
        });

      // Old term should not match
      final oldResult = db.search(term: 'hello');
      expect(oldResult.count, 0);

      // New term should match
      final newResult = db.search(term: 'goodbye');
      expect(newResult.count, 1);
      expect(newResult.hits.first.id, 'a');
    });
  });
}
