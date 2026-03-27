// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

void main() {
  group('Edge cases', () {
    late Searchlight db;

    setUp(() {
      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'body': const TypedField(SchemaType.string),
          'category': const TypedField(SchemaType.enumType),
          'price': const TypedField(SchemaType.number),
        }),
      );
    });

    tearDown(() async {
      await db.dispose();
    });

    test('search on empty database returns empty results', () {
      final result = db.search(term: 'anything');
      expect(result.count, 0);
      expect(result.hits, isEmpty);
    });

    test('search with empty string term returns all documents with score 0',
        () {
      db
        ..insert({'id': 'a', 'title': 'Alpha', 'body': 'First', 'price': 10})
        ..insert({'id': 'b', 'title': 'Beta', 'body': 'Second', 'price': 20})
        ..insert({'id': 'c', 'title': 'Gamma', 'body': 'Third', 'price': 30});

      final result = db.search();
      expect(result.count, 3);
      expect(result.hits, hasLength(3));
      for (final hit in result.hits) {
        expect(hit.score, 0.0);
      }
    });

    test('insert duplicate data creates separate documents with different IDs',
        () {
      final id1 = db.insert({'title': 'Same Title', 'body': 'Same body'});
      final id2 = db.insert({'title': 'Same Title', 'body': 'Same body'});
      expect(id1, isNot(equals(id2)));
      expect(db.count, 2);

      // Both documents are searchable
      final result = db.search(term: 'Same Title');
      expect(result.count, 2);
    });

    test('remove non-existent ID returns false', () {
      db.insert({'id': 'exists', 'title': 'Hello', 'body': 'World'});
      final removed = db.remove('does-not-exist');
      expect(removed, isFalse);
      expect(db.count, 1);
    });

    test('replace correctly re-indexes all fields', () {
      db
        ..insert({
          'id': 'doc1',
          'title': 'Original Title',
          'body': 'Original body content',
          'price': 10,
        })
        // Replace with new content
        ..update('doc1', {
          'id': 'doc1',
          'title': 'Replaced Title',
          'body': 'Replaced body content',
          'price': 20,
        });

      // Old content should not be found
      final oldResult = db.search(term: 'Original');
      expect(oldResult.count, 0);

      // New content should be found
      final newResult = db.search(term: 'Replaced');
      expect(newResult.count, 1);
      expect(newResult.hits.first.id, 'doc1');
    });

    test('patch correctly re-indexes changed fields', () {
      db
        ..insert({
          'id': 'doc1',
          'title': 'Original Title',
          'body': 'Unchanged body',
          'price': 10,
        })
        // Patch only the title
        ..patch('doc1', {'title': 'Patched Title'});

      // Old title content should not be found
      final oldResult = db.search(term: 'Original');
      expect(oldResult.count, 0);

      // New title content should be found
      final newResult = db.search(term: 'Patched');
      expect(newResult.count, 1);
      expect(newResult.hits.first.id, 'doc1');

      // Unchanged body content should still be found
      final bodyResult = db.search(term: 'Unchanged');
      expect(bodyResult.count, 1);
      expect(bodyResult.hits.first.id, 'doc1');
    });

    test('search with filter on non-existent field throws QueryException', () {
      db.insert({'id': 'a', 'title': 'Hello', 'body': 'World', 'price': 10});
      expect(
        () => db.search(
          term: 'Hello',
          where: {'nonExistentField': eq('value')},
        ),
        throwsA(isA<QueryException>()),
      );
    });

    test('very long document content (1000+ words) is indexed correctly', () {
      // Generate a body with 1000+ words, with a unique needle at the end
      final words = List.generate(1000, (i) => 'word$i')
        ..add('xylophoneNeedle');
      final longBody = words.join(' ');

      db.insert({'id': 'long', 'title': 'Long doc', 'body': longBody});

      // Search for the unique needle buried in the content
      final result = db.search(term: 'xylophoneNeedle');
      expect(result.count, 1);
      expect(result.hits.first.id, 'long');
    });

    test('special characters in search term are handled gracefully', () {
      db.insert({
        'id': 'special',
        'title': 'C++ programming',
        'body': 'Curly braces {} and brackets []',
      });

      // Searching for terms with special characters should not throw
      expect(() => db.search(term: 'C++'), returnsNormally);
      expect(() => db.search(term: '{}'), returnsNormally);
      expect(() => db.search(term: '[]'), returnsNormally);
      expect(() => db.search(term: r'$pecial!@#%^&*()'), returnsNormally);
      expect(() => db.search(term: '...'), returnsNormally);
    });

    test('unicode emoji in content does not crash tokenizer', () {
      // Insert should not throw
      expect(
        () => db.insert({
          'id': 'emoji',
          'title': 'Hello World',
          'body': 'Great job! Keep it up!',
        }),
        returnsNormally,
      );

      // Search with emoji should not throw
      expect(() => db.search(), returnsNormally);

      // Normal search still works on the same document
      final result = db.search(term: 'Hello');
      expect(result.count, 1);
      expect(result.hits.first.id, 'emoji');
    });

    test('search immediately after clear returns empty', () {
      db
        ..insert({'id': 'a', 'title': 'Alpha', 'body': 'First', 'price': 10})
        ..insert({'id': 'b', 'title': 'Beta', 'body': 'Second', 'price': 20});
      expect(db.count, 2);

      db.clear();
      expect(db.count, 0);

      final result = db.search(term: 'Alpha');
      expect(result.count, 0);
      expect(result.hits, isEmpty);

      // Also verify empty-term search returns nothing
      final allResult = db.search();
      expect(allResult.count, 0);
      expect(allResult.hits, isEmpty);
    });

    test('multiple inserts then bulk remove then search', () {
      final ids = <String>[];
      for (var i = 0; i < 10; i++) {
        ids.add(
          db.insert({
            'id': 'doc$i',
            'title': 'Document number $i',
            'body': 'Content for document $i',
            'price': i * 10,
          }),
        );
      }
      expect(db.count, 10);

      // Remove the first 5
      final removedCount = db.removeMultiple(ids.sublist(0, 5));
      expect(removedCount, 5);
      expect(db.count, 5);

      // Search should only find remaining documents
      final result = db.search(term: 'Document');
      expect(result.count, 5);

      // Verify removed documents are not in results
      final resultIds = result.hits.map((h) => h.id).toSet();
      for (var i = 0; i < 5; i++) {
        expect(resultIds, isNot(contains('doc$i')));
      }
      for (var i = 5; i < 10; i++) {
        expect(resultIds, contains('doc$i'));
      }
    });

    test('update preserving same ID works correctly', () {
      db.insert({
        'id': 'persistent',
        'title': 'Alphanumeric',
        'body': 'Xylophone content',
        'price': 10,
      });

      // Update with the same ID preserved in the new document
      final newId = db.update('persistent', {
        'id': 'persistent',
        'title': 'Zephyr',
        'body': 'Quixotic content',
        'price': 20,
      });

      expect(newId, 'persistent');
      expect(db.count, 1);

      // Verify the document content was replaced
      final doc = db.getById('persistent');
      expect(doc, isNotNull);
      expect(doc!.getString('title'), 'Zephyr');
      expect(doc.getNumber('price'), 20);

      // Old unique content not findable, new unique content findable
      expect(db.search(term: 'Alphanumeric').count, 0);
      expect(db.search(term: 'Zephyr').count, 1);
    });

    test('sequential insert and search maintains consistent state', () {
      // Interleave inserts and searches to verify state consistency
      db.insert({'id': 'a', 'title': 'Aardvark', 'body': 'First animal'});
      expect(db.search(term: 'Aardvark').count, 1);
      expect(db.count, 1);

      db.insert({'id': 'b', 'title': 'Bison', 'body': 'Second animal'});
      expect(db.search(term: 'Bison').count, 1);
      expect(db.search(term: 'animal').count, 2);
      expect(db.count, 2);

      db.remove('a');
      expect(db.search(term: 'Aardvark').count, 0);
      expect(db.search(term: 'animal').count, 1);
      expect(db.count, 1);

      db.insert({'id': 'c', 'title': 'Chameleon', 'body': 'Third animal'});
      expect(db.search(term: 'animal').count, 2);
      expect(db.count, 2);

      // Verify final state is consistent
      final allResult = db.search();
      expect(allResult.count, 2);
      final ids = allResult.hits.map((h) => h.id).toSet();
      expect(ids, containsAll(['b', 'c']));
      expect(ids, isNot(contains('a')));
    });
  });
}
