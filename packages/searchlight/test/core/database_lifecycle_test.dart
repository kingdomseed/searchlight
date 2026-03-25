// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/core/database.dart';
import 'package:searchlight/src/core/schema.dart';
import 'package:test/test.dart';

void main() {
  group('Searchlight', () {
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

    test('creates with valid schema', () {
      expect(db, isNotNull);
      expect(db.isEmpty, isTrue);
      expect(db.count, 0);
    });

    test('schema is accessible', () {
      expect(db.schema.fields, hasLength(2));
      expect(db.schema.typeAt('title'), SchemaType.string);
    });

    test('defaults to BM25 algorithm', () {
      expect(db.algorithm, SearchAlgorithm.bm25);
    });

    test('defaults to English language', () {
      expect(db.language, 'en');
    });

    test('accepts custom algorithm', () {
      final qpsDb = Searchlight.create(
        schema: Schema({'title': const TypedField(SchemaType.string)}),
        algorithm: SearchAlgorithm.qps,
      );
      expect(qpsDb.algorithm, SearchAlgorithm.qps);
    });

    test('accepts custom language', () {
      final deDb = Searchlight.create(
        schema: Schema({'title': const TypedField(SchemaType.string)}),
        language: 'de',
      );
      expect(deDb.language, 'de');
    });

    test('dispose completes without error', () async {
      await expectLater(db.dispose(), completes);
    });
  });
}
