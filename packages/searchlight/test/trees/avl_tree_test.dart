// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/trees/avl_tree.dart';
import 'package:test/test.dart';

void main() {
  group('AVLTree', () {
    test('insert single key-value, find returns it', () {
      final tree = AVLTree<int, int>()..insert(10, 1);
      expect(tree.find(10), {1});
    });

    test(
      'insert multiple values for same key, find returns Set with all',
      () {
        final tree = AVLTree<int, int>()
          ..insert(10, 1)
          ..insert(10, 2)
          ..insert(10, 3);
        expect(tree.find(10), {1, 2, 3});
      },
    );

    test('insert maintains BST ordering (left < root < right)', () {
      final tree = AVLTree<int, int>()
        ..insert(10, 1)
        ..insert(5, 2)
        ..insert(15, 3);
      expect(tree.root!.key, 10);
      expect(tree.root!.left!.key, 5);
      expect(tree.root!.right!.key, 15);
    });

    test('height updates correctly after inserts', () {
      final tree = AVLTree<int, int>()..insert(10, 1);
      expect(tree.root!.height, 1);
      tree.insert(5, 2);
      expect(tree.root!.height, 2);
      tree.insert(15, 3);
      expect(tree.root!.height, 2);
      tree.insert(3, 4);
      expect(tree.root!.height, 3);
    });

    test('rebalance corrects an unbalanced tree', () {
      // Use a very high threshold so inserts do NOT auto-rebalance,
      // then call rebalance() explicitly.
      final tree = AVLTree<int, int>()
        // Insert ascending keys to create right-heavy imbalance.
        ..insert(1, 1, rebalanceThreshold: 100000)
        ..insert(2, 2, rebalanceThreshold: 100000)
        ..insert(3, 3, rebalanceThreshold: 100000)
        ..insert(4, 4, rebalanceThreshold: 100000)
        ..insert(5, 5, rebalanceThreshold: 100000)
        ..rebalance();

      // After rebalance, all nodes should have balance factor
      // in {-1, 0, 1}.
      bool isBalanced(AVLNode<int, int>? node) {
        if (node == null) return true;
        final bf = node.getBalanceFactor();
        return bf >= -1 &&
            bf <= 1 &&
            isBalanced(node.left) &&
            isBalanced(node.right);
      }

      expect(isBalanced(tree.root), isTrue);
    });

    test('rotateLeft produces correct structure', () {
      //     A(10)             B(20)
      //       \              /    \
      //      B(20)   =>   A(10)  C(30)
      //        \
      //       C(30)
      final a = AVLNode<int, int>(10, [1])
        ..right =
            (AVLNode<int, int>(20, [2])..right = AVLNode<int, int>(30, [3]));
      // Update heights bottom-up.
      a.right!.right!.updateHeight();
      a.right!.updateHeight();
      a.updateHeight();

      final newRoot = a.rotateLeft();
      expect(newRoot.key, 20);
      expect(newRoot.left!.key, 10);
      expect(newRoot.right!.key, 30);
    });

    test('rotateRight produces correct structure', () {
      //       C(30)          B(20)
      //       /              /    \
      //     B(20)    =>   A(10)  C(30)
      //     /
      //   A(10)
      final c = AVLNode<int, int>(30, [3])
        ..left =
            (AVLNode<int, int>(20, [2])..left = AVLNode<int, int>(10, [1]));
      c.left!.left!.updateHeight();
      c.left!.updateHeight();
      c.updateHeight();

      final newRoot = c.rotateRight();
      expect(newRoot.key, 20);
      expect(newRoot.left!.key, 10);
      expect(newRoot.right!.key, 30);
    });

    test('rangeSearch(min, max) returns values in range', () {
      final tree = AVLTree<int, int>()
        ..insert(1, 10)
        ..insert(3, 30)
        ..insert(5, 50)
        ..insert(7, 70)
        ..insert(9, 90);
      final result = tree.rangeSearch(3, 7);
      expect(result, {30, 50, 70});
    });

    test(
      'greaterThan(key, inclusive: false) returns values > key',
      () {
        final tree = AVLTree<int, int>()
          ..insert(1, 10)
          ..insert(3, 30)
          ..insert(5, 50)
          ..insert(7, 70)
          ..insert(9, 90);
        final result = tree.greaterThan(5);
        expect(result, {70, 90});
      },
    );

    test(
      'greaterThan(key, inclusive: true) returns values >= key',
      () {
        final tree = AVLTree<int, int>()
          ..insert(1, 10)
          ..insert(3, 30)
          ..insert(5, 50)
          ..insert(7, 70)
          ..insert(9, 90);
        final result = tree.greaterThan(5, inclusive: true);
        expect(result, {50, 70, 90});
      },
    );

    test(
      'lessThan(key, inclusive: false) returns values < key',
      () {
        final tree = AVLTree<int, int>()
          ..insert(1, 10)
          ..insert(3, 30)
          ..insert(5, 50)
          ..insert(7, 70)
          ..insert(9, 90);
        final result = tree.lessThan(5);
        expect(result, {10, 30});
      },
    );

    test(
      'lessThan(key, inclusive: true) returns values <= key',
      () {
        final tree = AVLTree<int, int>()
          ..insert(1, 10)
          ..insert(3, 30)
          ..insert(5, 50)
          ..insert(7, 70)
          ..insert(9, 90);
        final result = tree.lessThan(5, inclusive: true);
        expect(result, {10, 30, 50});
      },
    );

    test('remove(key) removes the node', () {
      final tree = AVLTree<int, int>()
        ..insert(10, 1)
        ..insert(5, 2)
        ..insert(15, 3)
        ..remove(10);
      expect(tree.find(10), isNull);
      // Other nodes still accessible.
      expect(tree.find(5), {2});
      expect(tree.find(15), {3});
    });

    test(
      'removeDocument(key, id) removes single value from node set',
      () {
        final tree = AVLTree<int, int>()
          ..insert(10, 1)
          ..insert(10, 2)
          ..insert(10, 3)
          ..removeDocument(10, 2);
        expect(tree.find(10), {1, 3});
      },
    );

    test('removeDocument removes node when last value is removed', () {
      final tree = AVLTree<int, int>()
        ..insert(10, 1)
        ..removeDocument(10, 1);
      expect(tree.find(10), isNull);
    });

    test('find returns null for missing key', () {
      final tree = AVLTree<int, int>()..insert(10, 1);
      expect(tree.find(99), isNull);
    });

    test('toJson/fromJson round-trip preserves tree', () {
      final tree = AVLTree<int, int>()
        ..insert(10, 1)
        ..insert(5, 2)
        ..insert(15, 3)
        ..insert(10, 4);

      final json = tree.toJson();
      final restored = AVLTree<int, int>.fromJson(
        json,
        keyFromJson: (v) => v as int,
        valueFromJson: (v) => v as int,
      );

      expect(restored.find(10), {1, 4});
      expect(restored.find(5), {2});
      expect(restored.find(15), {3});
      expect(restored.root!.height, tree.root!.height);
    });
  });
}
