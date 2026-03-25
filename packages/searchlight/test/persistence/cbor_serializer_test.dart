// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';

import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

void main() {
  group('CBOR serialization', () {
    test('serialize() returns Uint8List', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
      );

      final bytes = db.serialize();

      expect(bytes, isA<Uint8List>());
      expect(bytes, isNotEmpty);
    });

    test('serialize/deserialize round-trip preserves documents', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'price': const TypedField(SchemaType.number),
        }),
      )
        ..insert({'id': 'doc-1', 'title': 'Hello World', 'price': 9.99})
        ..insert({'id': 'doc-2', 'title': 'Dart Language', 'price': 19.99});

      final bytes = db.serialize();
      final restored = Searchlight.deserialize(bytes);

      expect(restored.count, equals(2));
      expect(
        restored.getById('doc-1')?.getString('title'),
        equals('Hello World'),
      );
      expect(
        restored.getById('doc-1')?.getNumber('price'),
        equals(9.99),
      );
      expect(
        restored.getById('doc-2')?.getString('title'),
        equals('Dart Language'),
      );
      expect(
        restored.getById('doc-2')?.getNumber('price'),
        equals(19.99),
      );
    });

    test(
      'serialize/deserialize round-trip: search works on restored database',
      () {
        final db = Searchlight.create(
          schema: Schema({
            'title': const TypedField(SchemaType.string),
            'category': const TypedField(SchemaType.string),
          }),
        )
          ..insert({
            'id': 'doc-1',
            'title': 'Dart Programming',
            'category': 'tech',
          })
          ..insert({
            'id': 'doc-2',
            'title': 'Flutter Widgets',
            'category': 'tech',
          })
          ..insert({
            'id': 'doc-3',
            'title': 'Cooking Recipes',
            'category': 'food',
          });

        final bytes = db.serialize();
        final restored = Searchlight.deserialize(bytes);

        final results = restored.search(term: 'Dart');
        expect(results.count, equals(1));
        expect(results.hits.first.id, equals('doc-1'));
        expect(
          results.hits.first.document.getString('title'),
          equals('Dart Programming'),
        );
      },
    );

    test('deserialize with corrupt bytes throws SerializationException', () {
      final corruptBytes = Uint8List.fromList([0xFF, 0xFE, 0x00, 0x01]);

      expect(
        () => Searchlight.deserialize(corruptBytes),
        throwsA(isA<SerializationException>()),
      );
    });
  });
}
