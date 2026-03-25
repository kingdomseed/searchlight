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

    test('insert returns a DocId and increments count', () {
      final id = db.insert({'title': 'Hello', 'price': 9.99});
      expect(id, isA<DocId>());
      expect(db.count, 1);
    });

    test('insert stores the document — retrievable via getById', () {
      final id = db.insert({'title': 'Hello', 'price': 9.99});
      final doc = db.getById(id);
      expect(doc, isNotNull);
      expect(doc!.getString('title'), 'Hello');
      expect(doc.getNumber('price'), 9.99);
    });

    test('getById returns null for unknown ID', () {
      expect(db.getById(const DocId(999)), isNull);
    });

    test('insert with wrong field type throws DocumentValidationException', () {
      expect(
        () => db.insert({'title': 123}),
        throwsA(isA<DocumentValidationException>()),
      );
    });

    test(
        'insert with extra fields not in schema throws DocumentValidationException',
        () {
      expect(
        () => db.insert({'title': 'Hello', 'unknown': 'field'}),
        throwsA(isA<DocumentValidationException>()),
      );
    });

    test('insert allows missing fields (treated as null/absent)', () {
      final id = db.insert({'title': 'Partial'});
      expect(db.count, 1);
      final doc = db.getById(id);
      expect(doc, isNotNull);
      expect(doc!.getString('title'), 'Partial');
      expect(doc.tryGetNumber('price'), isNull);
    });

    test('remove decrements count', () {
      final id = db.insert({'title': 'Hello', 'price': 9.99});
      expect(db.count, 1);
      db.remove(id);
      expect(db.count, 0);
    });

    test('remove makes document unretrievable via getById', () {
      final id = db.insert({'title': 'Hello', 'price': 9.99});
      db.remove(id);
      expect(db.getById(id), isNull);
    });

    test('remove on unknown ID does nothing (no error)', () {
      db.insert({'title': 'Hello', 'price': 9.99});
      db.remove(const DocId(999));
      expect(db.count, 1);
    });

    test('removeMultiple removes multiple documents', () {
      final id1 = db.insert({'title': 'A', 'price': 1});
      final id2 = db.insert({'title': 'B', 'price': 2});
      db.insert({'title': 'C', 'price': 3});
      expect(db.count, 3);
      db.removeMultiple([id1, id2]);
      expect(db.count, 1);
    });
  });
}
