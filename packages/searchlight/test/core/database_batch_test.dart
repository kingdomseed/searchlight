// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

void main() {
  group('Searchlight insertMultiple', () {
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

    test('with valid documents returns List<String> of external IDs', () {
      final ids = db.insertMultiple([
        {'title': 'A', 'price': 1.0},
        {'title': 'B', 'price': 2.0},
        {'title': 'C', 'price': 3.0},
      ]);

      expect(ids, isA<List<String>>());
      expect(ids, hasLength(3));
    });

    test('with empty list returns empty List<String>', () {
      final ids = db.insertMultiple([]);

      expect(ids, isEmpty);
    });

    test('with an invalid document throws (aborts entire batch)', () {
      expect(
        () => db.insertMultiple([
          {'title': 'Valid', 'price': 1.0},
          {'title': 123}, // invalid: title should be String
          {'title': 'Also Valid', 'price': 3.0},
        ]),
        throwsA(isA<DocumentValidationException>()),
      );

      // Only the first document was inserted before the error
      expect(db.count, 1);
    });

    test('count reflects all inserted documents on success', () {
      expect(db.count, 0);

      db.insertMultiple([
        {'title': 'A', 'price': 1.0},
        {'title': 'B', 'price': 2.0},
      ]);

      expect(db.count, 2);
    });

    test('accepts custom batchSize parameter (default is 1000)', () {
      final ids = db.insertMultiple(
        [
          {'title': 'A', 'price': 1.0},
          {'title': 'B', 'price': 2.0},
        ],
        batchSize: 1,
      );

      expect(ids, hasLength(2));
    });

    test('duplicate ID in batch aborts on the duplicate', () {
      expect(
        () => db.insertMultiple([
          {'id': 'same-id', 'title': 'First', 'price': 1.0},
          {'id': 'same-id', 'title': 'Second', 'price': 2.0},
        ]),
        throwsA(isA<DocumentValidationException>()),
      );
      expect(db.count, 1);
    });
  });
}
