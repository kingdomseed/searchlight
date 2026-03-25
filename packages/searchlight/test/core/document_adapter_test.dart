// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

/// A concrete test implementation of DocumentAdapter.
class StringDocumentAdapter extends DocumentAdapter<String> {
  @override
  List<Map<String, Object?>> toDocuments(String source) {
    // Split CSV-like lines into separate documents.
    return source
        .split('\n')
        .where((line) => line.isNotEmpty)
        .map((line) => <String, Object?>{'content': line})
        .toList();
  }
}

void main() {
  group('DocumentAdapter', () {
    test('concrete implementation converts source to documents', () {
      final adapter = StringDocumentAdapter();
      final docs = adapter.toDocuments('hello\nworld');
      expect(docs, hasLength(2));
      expect(docs[0], {'content': 'hello'});
      expect(docs[1], {'content': 'world'});
    });

    test('concrete implementation handles empty source', () {
      final adapter = StringDocumentAdapter();
      final docs = adapter.toDocuments('');
      expect(docs, isEmpty);
    });
  });
}
