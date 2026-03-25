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

    test(
        'with valid documents returns BatchResult '
        'with all DocIds and no errors', () {
      final result = db.insertMultiple([
        {'title': 'A', 'price': 1.0},
        {'title': 'B', 'price': 2.0},
        {'title': 'C', 'price': 3.0},
      ]);

      expect(result, isA<BatchResult>());
      expect(result.insertedIds, hasLength(3));
      expect(result.errors, isEmpty);
    });

    test(
        'with empty list returns BatchResult '
        'with empty insertedIds and no errors', () {
      final result = db.insertMultiple([]);

      expect(result.insertedIds, isEmpty);
      expect(result.errors, isEmpty);
    });

    test(
        'with some invalid documents inserts valid '
        'ones and records errors for invalid ones', () {
      final result = db.insertMultiple([
        {'title': 'Valid', 'price': 1.0},
        {'title': 123}, // invalid: title should be String
        {'title': 'Also Valid', 'price': 3.0},
      ]);

      expect(result.insertedIds, hasLength(2));
      expect(result.errors, hasLength(1));
      expect(result.errors.first.error, isA<DocumentValidationException>());
    });

    test('hasErrors is true when errors exist and false when none', () {
      final withErrors = db.insertMultiple([
        {'title': 123}, // invalid
      ]);
      expect(withErrors.hasErrors, isTrue);

      final withoutErrors = db.insertMultiple([
        {'title': 'Valid', 'price': 1.0},
      ]);
      expect(withoutErrors.hasErrors, isFalse);
    });

    test(
        'BatchError.index correctly identifies '
        'which document in the input list failed', () {
      final result = db.insertMultiple([
        {'title': 'OK', 'price': 1.0}, // index 0: valid
        {'title': 123}, // index 1: invalid
        {'title': 'OK too', 'price': 2.0}, // index 2: valid
        {'unknown': 'field'}, // index 3: invalid
      ]);

      expect(result.errors, hasLength(2));
      expect(result.errors[0].index, 1);
      expect(result.errors[1].index, 3);
    });

    test(
        'count reflects only successfully inserted '
        'documents after insertMultiple', () {
      expect(db.count, 0);

      db.insertMultiple([
        {'title': 'A', 'price': 1.0},
        {'title': 123}, // invalid — should not count
        {'title': 'B', 'price': 2.0},
      ]);

      expect(db.count, 2);
    });

    test('accepts custom batchSize parameter', () {
      final result = db.insertMultiple(
        [
          {'title': 'A', 'price': 1.0},
          {'title': 'B', 'price': 2.0},
        ],
        batchSize: 1,
      );

      expect(result.insertedIds, hasLength(2));
      expect(result.errors, isEmpty);
    });
  });
}
