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
  });
}
