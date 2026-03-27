// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/core/exceptions.dart';
import 'package:searchlight/src/core/schema.dart';
import 'package:test/test.dart';

void main() {
  group('SchemaType', () {
    test('has all 9 leaf types (nested is structural via NestedField)', () {
      expect(SchemaType.values, hasLength(9));
      expect(SchemaType.values, contains(SchemaType.string));
      expect(SchemaType.values, contains(SchemaType.geopoint));
      expect(SchemaType.values, contains(SchemaType.enumArray));
    });
  });

  group('SchemaField', () {
    test('TypedField holds a SchemaType', () {
      const field = TypedField(SchemaType.string);
      expect(field.type, SchemaType.string);
    });

    test('NestedField holds child fields', () {
      const field = NestedField({
        'rating': TypedField(SchemaType.number),
      });
      expect(field.children, hasLength(1));
      expect(field.children['rating'], isA<TypedField>());
    });

    test('SchemaField is exhaustively switchable', () {
      const SchemaField field = TypedField(SchemaType.string);
      final result = switch (field) {
        TypedField() => 'typed',
        NestedField() => 'nested',
      };
      expect(result, 'typed');
    });
  });

  group('Schema', () {
    test('validates successfully with valid fields', () {
      final schema = Schema({
        'title': const TypedField(SchemaType.string),
        'price': const TypedField(SchemaType.number),
      });
      expect(schema.fields, hasLength(2));
    });

    test('throws on empty schema', () {
      expect(
        () => Schema({}),
        throwsA(isA<SchemaValidationException>()),
      );
    });

    test('supports nested fields', () {
      final schema = Schema({
        'meta': const NestedField({
          'rating': TypedField(SchemaType.number),
        }),
      });
      expect(schema.fields['meta'], isA<NestedField>());
    });

    test('throws on empty nested field', () {
      expect(
        () => Schema({
          'meta': const NestedField({}),
        }),
        throwsA(isA<SchemaValidationException>()),
      );
    });

    test('fieldPaths returns flattened dot-path list', () {
      final schema = Schema({
        'title': const TypedField(SchemaType.string),
        'meta': const NestedField({
          'rating': TypedField(SchemaType.number),
        }),
      });
      expect(schema.fieldPaths, containsAll(['title', 'meta.rating']));
    });

    test('typeAt returns the SchemaType for a dot-path', () {
      final schema = Schema({
        'title': const TypedField(SchemaType.string),
        'meta': const NestedField({
          'rating': TypedField(SchemaType.number),
        }),
      });
      expect(schema.typeAt('title'), SchemaType.string);
      expect(schema.typeAt('meta.rating'), SchemaType.number);
    });

    test('typeAt throws for unknown path', () {
      final schema = Schema({
        'title': const TypedField(SchemaType.string),
      });
      expect(
        () => schema.typeAt('unknown'),
        throwsA(isA<SchemaValidationException>()),
      );
    });

    test('typeAt throws when path points to nested object', () {
      final schema = Schema({
        'meta': const NestedField({
          'rating': TypedField(SchemaType.number),
        }),
      });
      expect(
        () => schema.typeAt('meta'),
        throwsA(isA<SchemaValidationException>()),
      );
    });

    test('typeAt throws when path traverses non-nested field', () {
      final schema = Schema({
        'title': const TypedField(SchemaType.string),
      });
      expect(
        () => schema.typeAt('title.foo'),
        throwsA(isA<SchemaValidationException>()),
      );
    });

    test('stringFieldPaths returns only string-type field paths', () {
      final schema = Schema({
        'title': const TypedField(SchemaType.string),
        'body': const TypedField(SchemaType.string),
        'price': const TypedField(SchemaType.number),
        'tags': const TypedField(SchemaType.stringArray),
      });
      final stringPaths = schema.fieldPathsOfType(SchemaType.string);
      expect(stringPaths, containsAll(['title', 'body']));
      expect(stringPaths, isNot(contains('price')));
    });
  });
}
