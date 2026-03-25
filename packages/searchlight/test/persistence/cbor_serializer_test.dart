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

    test('round-trip with geopoint fields through CBOR', () {
      final db = Searchlight.create(
        schema: Schema({
          'name': const TypedField(SchemaType.string),
          'location': const TypedField(SchemaType.geopoint),
        }),
      )
        ..insert({
          'id': 'nyc',
          'name': 'New York',
          'location': const GeoPoint(lat: 40.7128, lon: -74.0060),
        })
        ..insert({
          'id': 'london',
          'name': 'London',
          'location': const GeoPoint(lat: 51.5074, lon: -0.1278),
        });

      final bytes = db.serialize();
      final restored = Searchlight.deserialize(bytes);

      expect(restored.count, equals(2));

      final nyc = restored.getById('nyc');
      expect(nyc, isNotNull);
      expect(nyc!.getGeoPoint('location').lat, equals(40.7128));
      expect(nyc.getGeoPoint('location').lon, equals(-74.0060));

      final london = restored.getById('london');
      expect(london, isNotNull);
      expect(london!.getGeoPoint('location').lat, equals(51.5074));
      expect(london.getGeoPoint('location').lon, equals(-0.1278));
    });

    test('round-trip with enum fields through CBOR', () {
      final db = Searchlight.create(
        schema: Schema({
          'name': const TypedField(SchemaType.string),
          'color': const TypedField(SchemaType.enumType),
        }),
      )
        ..insert({'id': 'a', 'name': 'Apple', 'color': 'red'})
        ..insert({'id': 'b', 'name': 'Banana', 'color': 'yellow'});

      final bytes = db.serialize();
      final restored = Searchlight.deserialize(bytes);

      expect(restored.count, equals(2));
      expect(restored.getById('a')?.getString('color'), equals('red'));

      final results = restored.search(
        where: {'color': const EqFilter('red')},
      );
      expect(results.count, equals(1));
      expect(results.hits.first.id, equals('a'));
    });

    test('round-trip with array fields through CBOR', () {
      final db = Searchlight.create(
        schema: Schema({
          'name': const TypedField(SchemaType.string),
          'tags': const TypedField(SchemaType.stringArray),
          'scores': const TypedField(SchemaType.numberArray),
        }),
      )..insert({
          'id': 'doc1',
          'name': 'Widget',
          'tags': ['dart', 'flutter'],
          'scores': [95, 87, 91],
        });

      final bytes = db.serialize();
      final restored = Searchlight.deserialize(bytes);

      expect(restored.count, equals(1));
      final doc1 = restored.getById('doc1');
      expect(doc1, isNotNull);
      expect(doc1!.getStringList('tags'), equals(['dart', 'flutter']));
      expect(doc1.getNumberList('scores'), equals([95, 87, 91]));
    });

    test('round-trip with nested fields through CBOR', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'meta': const NestedField({
            'author': TypedField(SchemaType.string),
            'rating': TypedField(SchemaType.number),
          }),
        }),
      )..insert({
          'id': 'doc1',
          'title': 'Dart Guide',
          'meta': {'author': 'Alice', 'rating': 5},
        });

      final bytes = db.serialize();
      final restored = Searchlight.deserialize(bytes);

      expect(restored.count, equals(1));
      final doc1 = restored.getById('doc1');
      expect(doc1, isNotNull);
      expect(doc1!.getNested('meta').getString('author'), equals('Alice'));
      expect(doc1.getNested('meta').getNumber('rating'), equals(5));
    });

    test('delete-then-persist round-trip through CBOR', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
      )
        ..insert({'id': 'a', 'title': 'Alpha'})
        ..insert({'id': 'b', 'title': 'Beta'})
        ..insert({'id': 'c', 'title': 'Gamma'});

      expect(db.remove('b'), isTrue);
      expect(db.count, equals(2));

      final bytes = db.serialize();
      final restored = Searchlight.deserialize(bytes);

      expect(restored.count, equals(2));
      expect(restored.getById('a'), isNotNull);
      expect(restored.getById('c'), isNotNull);
      expect(restored.getById('b'), isNull);

      // Insert new doc without collision
      restored.insert({'id': 'd', 'title': 'Delta'});
      expect(restored.count, equals(3));
    });
  });
}
