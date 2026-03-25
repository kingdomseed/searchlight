// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/trees/flat_tree.dart';
import 'package:test/test.dart';

void main() {
  group('FlatTree', () {
    test('insert adds docId to key set', () {
      final tree = FlatTree()..insert('color', 1);
      expect(tree.find('color'), [1]);
    });

    test('insert multiple docIds to same key', () {
      final tree = FlatTree()
        ..insert('color', 1)
        ..insert('color', 2)
        ..insert('color', 3);
      expect(tree.find('color'), unorderedEquals([1, 2, 3]));
    });

    test('find returns docIds for existing key', () {
      final tree = FlatTree()
        ..insert('status', 10)
        ..insert('status', 20);
      final result = tree.find('status');
      expect(result, isNotNull);
      expect(result, unorderedEquals([10, 20]));
    });

    test('find returns null for missing key', () {
      final tree = FlatTree();
      expect(tree.find('missing'), isNull);
    });

    test('removeDocument removes single docId and cleans empty set', () {
      final tree = FlatTree()
        ..insert('color', 1)
        ..insert('color', 2)
        ..removeDocument(1, 'color');
      expect(tree.find('color'), [2]);

      // Removing last docId cleans up the key entirely.
      tree.removeDocument(2, 'color');
      expect(tree.find('color'), isNull);
      expect(tree.contains('color'), isFalse);
    });

    test('contains returns true for existing key and false for missing', () {
      final tree = FlatTree()..insert('color', 1);
      expect(tree.contains('color'), isTrue);
      expect(tree.contains('missing'), isFalse);
    });

    test('getSize returns total count of all docIds across all keys', () {
      final tree = FlatTree();
      expect(tree.getSize(), 0);
      tree
        ..insert('color', 1)
        ..insert('color', 2)
        ..insert('status', 3);
      expect(tree.getSize(), 3);
    });

    test('filterEq returns docIds for exact value match', () {
      final tree = FlatTree()
        ..insert('red', 1)
        ..insert('red', 2)
        ..insert('blue', 3);
      expect(tree.filterEq('red'), unorderedEquals([1, 2]));
      expect(tree.filterEq('missing'), isEmpty);
    });

    test('filterIn returns union of docIds for any of the values', () {
      final tree = FlatTree()
        ..insert('red', 1)
        ..insert('blue', 2)
        ..insert('green', 3);
      expect(
        tree.filterIn(['red', 'green']),
        unorderedEquals([1, 3]),
      );
      expect(tree.filterIn(['missing']), isEmpty);
    });

    test('filterNin returns docIds NOT matching excluded values', () {
      final tree = FlatTree()
        ..insert('red', 1)
        ..insert('blue', 2)
        ..insert('green', 3);
      expect(
        tree.filterNin(['red']),
        unorderedEquals([2, 3]),
      );
    });

    test('filterContainsAll returns intersection of docId sets', () {
      final tree = FlatTree()
        ..insert('a', 1)
        ..insert('b', 1)
        ..insert('a', 2)
        ..insert('b', 3);
      // Only doc 1 appears in BOTH 'a' and 'b'.
      expect(tree.filterContainsAll(['a', 'b']), [1]);
      expect(tree.filterContainsAll([]), isEmpty);
    });

    test('filterContainsAny returns union of docId sets', () {
      final tree = FlatTree()
        ..insert('a', 1)
        ..insert('b', 2)
        ..insert('c', 3);
      expect(
        tree.filterContainsAny(['a', 'c']),
        unorderedEquals([1, 3]),
      );
      expect(tree.filterContainsAny([]), isEmpty);
    });

    test('toJson/fromJson round-trip preserves data', () {
      final tree = FlatTree()
        ..insert('red', 1)
        ..insert('red', 2)
        ..insert('blue', 3);

      final json = tree.toJson();
      final restored = FlatTree.fromJson(json);

      expect(restored.find('red'), unorderedEquals([1, 2]));
      expect(restored.find('blue'), [3]);
      expect(restored.find('missing'), isNull);
      expect(restored.getSize(), 3);
    });
  });
}
