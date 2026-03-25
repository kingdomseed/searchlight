// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/core/doc_id.dart';
import 'package:searchlight/src/core/exceptions.dart';
import 'package:test/test.dart';

void main() {
  group('SearchlightException', () {
    test('SchemaValidationException has message', () {
      const e = SchemaValidationException('Invalid field type');
      expect(e.message, 'Invalid field type');
      expect(e, isA<SearchlightException>());
    });

    test('DocumentValidationException includes field name', () {
      const e = DocumentValidationException('Type mismatch', field: 'price');
      expect(e.field, 'price');
      expect(e, isA<SearchlightException>());
    });

    test('DocumentNotFoundException includes DocId', () {
      final e = DocumentNotFoundException(const DocId(42));
      expect(e.message, contains('42'));
      expect(e.id, const DocId(42));
      expect(e, isA<SearchlightException>());
    });

    test('all exception types are exhaustively switchable', () {
      const SearchlightException e = SchemaValidationException('test');
      final result = switch (e) {
        SchemaValidationException() => 'schema',
        DocumentValidationException() => 'document',
        DocumentNotFoundException() => 'not_found',
        SerializationException() => 'serialization',
        StorageException() => 'storage',
        QueryException() => 'query',
      };
      expect(result, 'schema');
    });
  });
}
