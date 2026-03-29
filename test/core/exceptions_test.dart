// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

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

    test('DocumentNotFoundException includes String id', () {
      final e = DocumentNotFoundException('doc-42');
      expect(e.message, contains('doc-42'));
      expect(e.id, 'doc-42');
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
        ExtensionResolutionException() => 'extension',
      };
      expect(result, 'schema');
    });
  });
}
