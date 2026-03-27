// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

void main() {
  group('Searchlight CRUD', () {
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

    test('insert returns a String external ID and increments count', () {
      final id = db.insert({'title': 'Hello', 'price': 9.99});
      expect(id, isA<String>());
      expect(id, isNotEmpty);
      expect(db.count, 1);
    });

    test('insert uses provided string id from document', () {
      final id =
          db.insert({'id': 'my-custom-id', 'title': 'Hello', 'price': 9.99});
      expect(id, 'my-custom-id');
      expect(db.count, 1);
    });

    test('insert auto-generates unique string IDs when id not provided', () {
      final id1 = db.insert({'title': 'A', 'price': 1});
      final id2 = db.insert({'title': 'B', 'price': 2});
      expect(id1, isA<String>());
      expect(id2, isA<String>());
      expect(id1, isNot(equals(id2)));
    });

    test('insert throws on duplicate external ID', () {
      db.insert({'id': 'dup-id', 'title': 'First', 'price': 1});
      expect(
        () => db.insert({'id': 'dup-id', 'title': 'Second', 'price': 2}),
        throwsA(isA<DocumentValidationException>()),
      );
    });

    test('insert stores the document — retrievable via getById with String',
        () {
      final id = db.insert({'title': 'Hello', 'price': 9.99});
      final doc = db.getById(id);
      expect(doc, isNotNull);
      expect(doc!.getString('title'), 'Hello');
      expect(doc.getNumber('price'), 9.99);
    });

    test('getById returns null for unknown String ID', () {
      expect(db.getById('nonexistent'), isNull);
    });

    test(
      'insert with wrong field type throws DocumentValidationException',
      () {
        expect(
          () => db.insert({'title': 123}),
          throwsA(isA<DocumentValidationException>()),
        );
      },
    );

    test('insert allows extra fields not in schema (silently ignored)', () {
      final id = db.insert({'title': 'Hello', 'unknown': 'field'});
      expect(id, isA<String>());
      expect(db.count, 1);
    });

    test('insert allows missing fields (treated as null/absent)', () {
      final id = db.insert({'title': 'Partial'});
      expect(db.count, 1);
      final doc = db.getById(id);
      expect(doc, isNotNull);
      expect(doc!.getString('title'), 'Partial');
      expect(doc.tryGetNumber('price'), isNull);
    });

    test('remove with String ID decrements count and returns true', () {
      final id = db.insert({'title': 'Hello', 'price': 9.99});
      expect(db.count, 1);
      final removed = db.remove(id);
      expect(removed, isTrue);
      expect(db.count, 0);
    });

    test('remove makes document unretrievable via getById', () {
      final id = db.insert({'title': 'Hello', 'price': 9.99});
      db.remove(id);
      expect(db.getById(id), isNull);
    });

    test('remove on unknown String ID returns false (no error)', () {
      db.insert({'title': 'Hello', 'price': 9.99});
      final removed = db.remove('nonexistent');
      expect(removed, isFalse);
      expect(db.count, 1);
    });

    test('removeMultiple removes multiple documents and returns count', () {
      final id1 = db.insert({'title': 'A', 'price': 1});
      final id2 = db.insert({'title': 'B', 'price': 2});
      db.insert({'title': 'C', 'price': 3});
      expect(db.count, 3);
      final count = db.removeMultiple([id1, id2]);
      expect(count, 2);
      expect(db.count, 1);
    });

    test('clear resets count to 0 and empties the database', () {
      db
        ..insert({'title': 'A', 'price': 1})
        ..insert({'title': 'B', 'price': 2});
      expect(db.count, 2);
      db.clear();
      expect(db.count, 0);
    });

    test('isEmpty returns true after clear, false after insert', () {
      expect(db.isEmpty, isTrue);
      db.insert({'title': 'A', 'price': 1});
      expect(db.isEmpty, isFalse);
      db.clear();
      expect(db.isEmpty, isTrue);
    });
  });
}
