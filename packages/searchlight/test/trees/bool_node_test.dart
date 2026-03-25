// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/trees/bool_node.dart';
import 'package:test/test.dart';

void main() {
  group('BoolNode', () {
    test('insert with flag=true adds value to trueSet', () {
      final node = BoolNode<String>()..insert('doc1', flag: true);
      expect(node.trueSet, contains('doc1'));
      expect(node.falseSet, isEmpty);
    });

    test('insert with flag=false adds value to falseSet', () {
      final node = BoolNode<String>()..insert('doc2', flag: false);
      expect(node.falseSet, contains('doc2'));
      expect(node.trueSet, isEmpty);
    });

    test('delete removes value from trueSet', () {
      final node = BoolNode<String>()
        ..insert('doc1', flag: true)
        ..delete('doc1', flag: true);
      expect(node.trueSet, isEmpty);
    });

    test('delete removes value from falseSet', () {
      final node = BoolNode<String>()
        ..insert('doc2', flag: false)
        ..delete('doc2', flag: false);
      expect(node.falseSet, isEmpty);
    });

    test('size returns combined count of trueSet and falseSet', () {
      final node = BoolNode<String>();
      expect(node.size, 0);
      node
        ..insert('a', flag: true)
        ..insert('b', flag: false)
        ..insert('c', flag: true);
      expect(node.size, 3);
    });

    test('toJson/fromJson round-trip preserves values', () {
      final node = BoolNode<String>()
        ..insert('doc1', flag: true)
        ..insert('doc2', flag: true)
        ..insert('doc3', flag: false);

      final json = node.toJson();
      expect(json['true'], isA<List<String>>());
      expect(json['false'], isA<List<String>>());

      final restored = BoolNode.fromJson<String>(json);
      expect(restored.trueSet, containsAll(['doc1', 'doc2']));
      expect(restored.falseSet, contains('doc3'));
      expect(restored.size, 3);
    });
  });
}
