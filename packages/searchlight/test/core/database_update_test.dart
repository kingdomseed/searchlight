// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

void main() {
  group('Searchlight update', () {
    late Searchlight db;

    setUp(() {
      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'price': const TypedField(SchemaType.number),
        }),
      );
    });

    tearDown(() async {
      await db.dispose();
    });

    test('replaces a document and returns a new ID', () {
      db.insert({
        'id': 'doc-1',
        'title': 'Original',
        'price': 10.0,
      });

      final newId = db.update('doc-1', {
        'id': 'doc-2',
        'title': 'Updated',
        'price': 20.0,
      });

      expect(newId, 'doc-2');
      expect(db.count, 1);
    });
    test('on non-existent ID still inserts the new document', () {
      // Orama's update does remove (returns false silently) then insert
      expect(db.count, 0);

      final newId = db.update('non-existent-id', {
        'id': 'fresh-doc',
        'title': 'Brand New',
        'price': 42.0,
      });

      expect(newId, 'fresh-doc');
      expect(db.count, 1);
      final doc = db.getById('fresh-doc');
      expect(doc, isNotNull);
      expect(doc!.getString('title'), 'Brand New');
    });

    test('after update old ID is gone and new ID is retrievable', () {
      db
        ..insert({
          'id': 'old-doc',
          'title': 'Old Title',
          'price': 5.0,
        })
        ..update('old-doc', {
          'id': 'new-doc',
          'title': 'New Title',
          'price': 15.0,
        });

      // Old ID should be gone
      expect(db.getById('old-doc'), isNull);

      // New ID should be retrievable
      final doc = db.getById('new-doc');
      expect(doc, isNotNull);
      expect(doc!.getString('title'), 'New Title');
      expect(doc.getNumber('price'), 15.0);

      // Count should still be 1 (replaced, not added)
      expect(db.count, 1);
    });

    test('with user-provided id in new doc uses that ID', () {
      db.insert({
        'id': 'old-id',
        'title': 'Original',
        'price': 10.0,
      });

      final newId = db.update('old-id', {
        'id': 'new-custom-id',
        'title': 'Updated',
        'price': 20.0,
      });

      expect(newId, 'new-custom-id');
      final doc = db.getById('new-custom-id');
      expect(doc, isNotNull);
      expect(doc!.getString('title'), 'Updated');
      expect(doc.getNumber('price'), 20.0);
    });
    test('validates new doc against schema and throws on invalid', () {
      db.insert({
        'id': 'valid-doc',
        'title': 'Valid',
        'price': 10.0,
      });

      // title should be String, not int
      expect(
        () => db.update('valid-doc', {
          'title': 123,
          'price': 20.0,
        }),
        throwsA(isA<DocumentValidationException>()),
      );

      // Original document should still exist (insert failed, but remove
      // already happened — matching Orama's behavior: remove then insert,
      // insert validates and throws)
    });
  });

  group('Searchlight updateMultiple', () {
    late Searchlight db;

    setUp(() {
      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'price': const TypedField(SchemaType.number),
        }),
      );
    });

    tearDown(() async {
      await db.dispose();
    });

    test('replaces multiple documents and returns new IDs', () {
      final id1 = db.insert({
        'id': 'doc-1',
        'title': 'First',
        'price': 10.0,
      });
      final id2 = db.insert({
        'id': 'doc-2',
        'title': 'Second',
        'price': 20.0,
      });

      final newIds = db.updateMultiple(
        [id1, id2],
        [
          {'id': 'new-1', 'title': 'Updated First', 'price': 11.0},
          {'id': 'new-2', 'title': 'Updated Second', 'price': 22.0},
        ],
      );

      expect(newIds, ['new-1', 'new-2']);
      expect(db.count, 2);

      // Old IDs gone
      expect(db.getById('doc-1'), isNull);
      expect(db.getById('doc-2'), isNull);

      // New IDs present
      expect(db.getById('new-1'), isNotNull);
      expect(db.getById('new-2'), isNotNull);
      expect(db.getById('new-1')!.getString('title'), 'Updated First');
      expect(db.getById('new-2')!.getString('title'), 'Updated Second');
    });
    test(
        'validates ALL docs before any removes — '
        'invalid doc prevents operation', () {
      db
        ..insert({
          'id': 'doc-1',
          'title': 'First',
          'price': 10.0,
        })
        ..insert({
          'id': 'doc-2',
          'title': 'Second',
          'price': 20.0,
        });

      expect(
        () => db.updateMultiple(
          ['doc-1', 'doc-2'],
          [
            {'title': 'Valid Update', 'price': 11.0},
            {'title': 123, 'price': 22.0}, // invalid: title must be String
          ],
        ),
        throwsA(isA<DocumentValidationException>()),
      );

      // Both original documents should still exist (no removes happened)
      expect(db.count, 2);
      expect(db.getById('doc-1'), isNotNull);
      expect(db.getById('doc-2'), isNotNull);
      expect(db.getById('doc-1')!.getString('title'), 'First');
      expect(db.getById('doc-2')!.getString('title'), 'Second');
    });
    test(
        'with one invalid doc in a batch of three '
        'throws and no docs are removed', () {
      final id1 = db.insert({
        'id': 'a',
        'title': 'A',
        'price': 1.0,
      });
      final id2 = db.insert({
        'id': 'b',
        'title': 'B',
        'price': 2.0,
      });
      final id3 = db.insert({
        'id': 'c',
        'title': 'C',
        'price': 3.0,
      });

      expect(db.count, 3);

      // Second doc is invalid (price should be num, not String)
      expect(
        () => db.updateMultiple(
          [id1, id2, id3],
          [
            {'title': 'A2', 'price': 10.0},
            {'title': 'B2', 'price': 'not-a-number'}, // invalid
            {'title': 'C2', 'price': 30.0},
          ],
        ),
        throwsA(isA<DocumentValidationException>()),
      );

      // All three original documents should still be intact
      expect(db.count, 3);
      expect(db.getById('a')!.getString('title'), 'A');
      expect(db.getById('b')!.getString('title'), 'B');
      expect(db.getById('c')!.getString('title'), 'C');
    });
  });
}
