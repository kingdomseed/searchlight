// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

void main() {
  group('Searchlight patch', () {
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

    test('merges new fields into existing document', () {
      db
        ..insert({
          'id': 'doc-1',
          'title': 'Original Title',
          'price': 10.0,
        })
        ..patch('doc-1', {'title': 'Updated Title'});

      final doc = db.getById('doc-1');
      expect(doc, isNotNull);
      expect(doc!.getString('title'), 'Updated Title');
      expect(doc.getNumber('price'), 10.0);
    });

    test('preserves the same external ID', () {
      db.insert({
        'id': 'keep-this-id',
        'title': 'Before',
        'price': 5.0,
      });

      final returnedId = db.patch('keep-this-id', {'title': 'After'});

      expect(returnedId, 'keep-this-id');
      expect(db.getById('keep-this-id'), isNotNull);
      expect(db.getById('keep-this-id')!.getString('title'), 'After');
    });

    test('throws DocumentNotFoundException for unknown ID', () {
      expect(
        () => db.patch('no-such-id', {'title': 'Nope'}),
        throwsA(isA<DocumentNotFoundException>()),
      );
    });

    test(
        'validates merged result — rejects invalid merged data without '
        'modifying original', () {
      db.insert({
        'id': 'valid-doc',
        'title': 'Good Title',
        'price': 10.0,
      });

      // price must be num, not String — merged result should fail validation
      expect(
        () => db.patch('valid-doc', {'price': 'not-a-number'}),
        throwsA(isA<DocumentValidationException>()),
      );

      // Original document must be preserved
      final doc = db.getById('valid-doc');
      expect(doc, isNotNull);
      expect(doc!.getString('title'), 'Good Title');
      expect(doc.getNumber('price'), 10.0);
    });

    test('can update a single field while preserving others', () {
      db
        ..insert({
          'id': 'doc-1',
          'title': 'Keep This',
          'price': 99.0,
        })
        ..patch('doc-1', {'price': 42.0});

      final doc = db.getById('doc-1')!;
      expect(doc.getString('title'), 'Keep This');
      expect(doc.getNumber('price'), 42.0);
    });

    test('after patch, count stays the same (no new document added)', () {
      db
        ..insert({
          'id': 'doc-1',
          'title': 'First',
          'price': 1.0,
        })
        ..insert({
          'id': 'doc-2',
          'title': 'Second',
          'price': 2.0,
        });

      expect(db.count, 2);

      db.patch('doc-1', {'title': 'Patched First'});

      expect(db.count, 2);
    });
  });
}
