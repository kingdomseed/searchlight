// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;

/// A node in an AVL tree.
///
/// Generic over [K] (comparable key) and [V] (value stored in a Set per node).
class AVLNode<K extends Comparable<dynamic>, V> {
  /// Creates an AVL node with the given [key] and initial [values].
  AVLNode(this.key, List<V> values) : values = Set<V>.of(values);

  /// The key for this node.
  K key;

  /// The set of values stored at this node.
  Set<V> values;

  /// Left child.
  AVLNode<K, V>? left;

  /// Right child.
  AVLNode<K, V>? right;

  /// Height of this node in the tree.
  int height = 1;

  /// Returns the height of [node], or 0 if null.
  static int getHeight<K extends Comparable<dynamic>, V>(AVLNode<K, V>? node) {
    return node != null ? node.height : 0;
  }

  /// Updates this node's height based on children's heights.
  void updateHeight() {
    height = math.max(getHeight(left), getHeight(right)) + 1;
  }

  /// Returns the balance factor (left height - right height).
  int getBalanceFactor() {
    return getHeight(left) - getHeight(right);
  }

  /// Performs a left rotation on this node and returns the new root.
  AVLNode<K, V> rotateLeft() {
    final newRoot = right!;
    right = newRoot.left;
    newRoot.left = this;
    updateHeight();
    newRoot.updateHeight();
    return newRoot;
  }

  /// Performs a right rotation on this node and returns the new root.
  AVLNode<K, V> rotateRight() {
    final newRoot = left!;
    left = newRoot.right;
    newRoot.right = this;
    updateHeight();
    newRoot.updateHeight();
    return newRoot;
  }

  /// Serializes this node to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'k': key,
      'v': values.toList(),
      'l': left?.toJson(),
      'r': right?.toJson(),
      'h': height,
    };
  }

  /// Deserializes an [AVLNode] from a JSON map.
  ///
  /// [keyFromJson] and [valueFromJson] convert raw JSON values to typed K/V.
  static AVLNode<K, V> fromJson<K extends Comparable<dynamic>, V>(
    Map<String, dynamic> json, {
    required K Function(dynamic) keyFromJson,
    required V Function(dynamic) valueFromJson,
  }) {
    return AVLNode<K, V>(
      keyFromJson(json['k']),
      (json['v'] as List<dynamic>).map(valueFromJson).toList(),
    )
      ..left = json['l'] != null
          ? AVLNode.fromJson<K, V>(
              json['l'] as Map<String, dynamic>,
              keyFromJson: keyFromJson,
              valueFromJson: valueFromJson,
            )
          : null
      ..right = json['r'] != null
          ? AVLNode.fromJson<K, V>(
              json['r'] as Map<String, dynamic>,
              keyFromJson: keyFromJson,
              valueFromJson: valueFromJson,
            )
          : null
      ..height = json['h'] as int;
  }
}

/// A record tracking a node and its parent during path-based traversal.
typedef _PathEntry<K extends Comparable<dynamic>, V> = ({
  AVLNode<K, V>? parent,
  AVLNode<K, V> node,
});

/// An AVL tree generic over [K] (comparable key) and [V] (value type).
///
/// Matches the structure and behavior of Orama's AVL tree implementation,
/// including iterative insert with path tracking and deferred rebalancing.
class AVLTree<K extends Comparable<dynamic>, V> {
  /// Creates an AVL tree, optionally with an initial [key] and [values].
  AVLTree({K? key, List<V>? values}) {
    if (key != null && values != null) {
      root = AVLNode<K, V>(key, values);
    }
  }

  /// Deserializes an [AVLTree] from a JSON map.
  ///
  /// [keyFromJson] and [valueFromJson] convert raw JSON values to typed K/V.
  factory AVLTree.fromJson(
    Map<String, dynamic> json, {
    required K Function(dynamic) keyFromJson,
    required V Function(dynamic) valueFromJson,
  }) {
    return AVLTree<K, V>()
      ..root = json['root'] != null
          ? AVLNode.fromJson<K, V>(
              json['root'] as Map<String, dynamic>,
              keyFromJson: keyFromJson,
              valueFromJson: valueFromJson,
            )
          : null
      .._insertCount = (json['insertCount'] as int?) ?? 0;
  }

  /// The root node of the tree.
  AVLNode<K, V>? root;

  int _insertCount = 0;

  /// Inserts a [key]-[value] pair into the tree.
  ///
  /// Rebalancing is deferred and only performed when [_insertCount] reaches
  /// [rebalanceThreshold].
  void insert(K key, V value, {int rebalanceThreshold = 1000}) {
    root = _insertNode(root, key, value, rebalanceThreshold);
  }

  /// Inserts multiple [values] for the same [key].
  void insertMultiple(K key, List<V> values, {int rebalanceThreshold = 1000}) {
    for (final v in values) {
      insert(key, v, rebalanceThreshold: rebalanceThreshold);
    }
  }

  /// Returns whether the tree contains a node with the given [key].
  bool contains(K key) => find(key) != null;

  /// Returns the number of nodes in the tree.
  int getSize() {
    var count = 0;
    final stack = <AVLNode<K, V>>[];
    var current = root;

    while (current != null || stack.isNotEmpty) {
      while (current != null) {
        stack.add(current);
        current = current.left;
      }
      current = stack.removeLast();
      count++;
      current = current.right;
    }

    return count;
  }

  /// Returns whether the tree is balanced (all nodes have balance factor
  /// in {-1, 0, 1}).
  bool get isBalanced {
    if (root == null) return true;

    final stack = <AVLNode<K, V>>[root!];

    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      final balanceFactor = node.getBalanceFactor();
      if (balanceFactor.abs() > 1) return false;
      if (node.left != null) stack.add(node.left!);
      if (node.right != null) stack.add(node.right!);
    }

    return true;
  }

  /// Serializes this tree to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'root': root?.toJson(),
      'insertCount': _insertCount,
    };
  }

  /// Forces a full rebalance of the entire tree.
  void rebalance() {
    if (root != null) {
      root = _rebalanceTree(root!);
    }
  }

  AVLNode<K, V> _rebalanceTree(AVLNode<K, V> node) {
    if (node.left != null) {
      node.left = _rebalanceTree(node.left!);
    }
    if (node.right != null) {
      node.right = _rebalanceTree(node.right!);
    }
    node.updateHeight();
    return _rebalanceNode(node);
  }

  /// Finds the set of values for the given [key], or null if not found.
  Set<V>? find(K key) {
    final node = _findNodeByKey(key);
    return node?.values;
  }

  /// Returns all values where [min] <= key <= [max].
  Set<V> rangeSearch(K min, K max) {
    final result = <V>{};
    final stack = <AVLNode<K, V>>[];
    var current = root;

    while (current != null || stack.isNotEmpty) {
      while (current != null) {
        stack.add(current);
        current = current.left;
      }
      current = stack.removeLast();
      if (current.key.compareTo(min) >= 0 && current.key.compareTo(max) <= 0) {
        result.addAll(current.values);
      }
      if (current.key.compareTo(max) > 0) {
        break;
      }
      current = current.right;
    }

    return result;
  }

  /// Returns all values where key > [key] (or >= if [inclusive] is true).
  ///
  /// Traverses in reverse in-order (right subtree first) for early
  /// termination.
  Set<V> greaterThan(K key, {bool inclusive = false}) {
    final result = <V>{};
    final stack = <AVLNode<K, V>>[];
    var current = root;

    while (current != null || stack.isNotEmpty) {
      while (current != null) {
        stack.add(current);
        current = current.right; // Traverse right subtree first.
      }
      current = stack.removeLast();
      if ((inclusive && current.key.compareTo(key) >= 0) ||
          (!inclusive && current.key.compareTo(key) > 0)) {
        result.addAll(current.values);
      } else if (current.key.compareTo(key) <= 0) {
        // Traversing in descending order; can break early.
        break;
      }
      current = current.left;
    }

    return result;
  }

  /// Returns all values where key < [key] (or <= if [inclusive] is true).
  ///
  /// Traverses in in-order (left subtree first) for early termination.
  Set<V> lessThan(K key, {bool inclusive = false}) {
    final result = <V>{};
    final stack = <AVLNode<K, V>>[];
    var current = root;

    while (current != null || stack.isNotEmpty) {
      while (current != null) {
        stack.add(current);
        current = current.left;
      }
      current = stack.removeLast();
      if ((inclusive && current.key.compareTo(key) <= 0) ||
          (!inclusive && current.key.compareTo(key) < 0)) {
        result.addAll(current.values);
      } else if (current.key.compareTo(key) > 0) {
        // Traversing in ascending order; can break early.
        break;
      }
      current = current.right;
    }

    return result;
  }

  /// Removes the node with the given [key] from the tree.
  void remove(K key) {
    root = _removeNode(root, key);
  }

  /// Removes a single [value] from the set at [key].
  ///
  /// If the node has only one value remaining, the entire node is removed.
  void removeDocument(K key, V value) {
    final node = _findNodeByKey(key);
    if (node == null) return;

    if (node.values.length == 1) {
      root = _removeNode(root, key);
    } else {
      node.values = Set<V>.of(
        node.values.where((v) => v != value),
      );
    }
  }

  AVLNode<K, V>? _removeNode(AVLNode<K, V>? node, K key) {
    if (node == null) return null;

    final path = <AVLNode<K, V>>[];
    AVLNode<K, V>? rootNode = node;
    var current = node;

    // Find the node to remove, tracking path.
    while (current.key.compareTo(key) != 0) {
      path.add(current);
      final cmp = key.compareTo(current.key);
      if (cmp < 0) {
        if (current.left == null) return rootNode; // Key not found.
        current = current.left!;
      } else {
        if (current.right == null) return rootNode; // Key not found.
        current = current.right!;
      }
    }

    // Node with only one child or no child.
    if (current.left == null || current.right == null) {
      final child = current.left ?? current.right;

      if (path.isEmpty) {
        // Node to be deleted is root.
        return child;
      } else {
        final parent = path.last;
        if (parent.left == current) {
          parent.left = child;
        } else {
          parent.right = child;
        }
      }
    } else {
      // Node with two children: get the inorder successor.
      var successorParent = current;
      var successor = current.right!;

      while (successor.left != null) {
        successorParent = successor;
        successor = successor.left!;
      }

      // Copy successor's content to current node.
      current
        ..key = successor.key
        ..values = successor.values;

      // Delete the successor.
      if (successorParent.left == successor) {
        successorParent.left = successor.right;
      } else {
        successorParent.right = successor.right;
      }

      current = successorParent;
    }

    // Update heights and rebalance.
    path.add(current);
    for (var i = path.length - 1; i >= 0; i--) {
      final currentNode = path[i]..updateHeight();
      final rebalancedNode = _rebalanceNode(currentNode);
      if (i > 0) {
        final parent = path[i - 1];
        if (parent.left == currentNode) {
          parent.left = rebalancedNode;
        } else if (parent.right == currentNode) {
          parent.right = rebalancedNode;
        }
      } else {
        // Root node.
        rootNode = rebalancedNode;
      }
    }

    return rootNode;
  }

  AVLNode<K, V>? _findNodeByKey(K key) {
    var node = root;
    while (node != null) {
      final cmp = key.compareTo(node.key);
      if (cmp < 0) {
        node = node.left;
      } else if (cmp > 0) {
        node = node.right;
      } else {
        return node;
      }
    }
    return null;
  }

  /// Iterative insert with path tracking, matching Orama's implementation.
  AVLNode<K, V> _insertNode(
    AVLNode<K, V>? node,
    K key,
    V value,
    int rebalanceThreshold,
  ) {
    if (node == null) {
      return AVLNode<K, V>(key, [value]);
    }

    var rootNode = node;
    final path = <_PathEntry<K, V>>[];
    var current = rootNode;
    AVLNode<K, V>? parent;

    while (true) {
      path.add((parent: parent, node: current));

      final cmp = key.compareTo(current.key);
      if (cmp < 0) {
        if (current.left == null) {
          current.left = AVLNode<K, V>(key, [value]);
          path.add((parent: current, node: current.left!));
          break;
        } else {
          parent = current;
          current = current.left!;
        }
      } else if (cmp > 0) {
        if (current.right == null) {
          current.right = AVLNode<K, V>(key, [value]);
          path.add((parent: current, node: current.right!));
          break;
        } else {
          parent = current;
          current = current.right!;
        }
      } else {
        // Key already exists -- add value to existing set.
        current.values.add(value);
        return rootNode;
      }
    }

    // Update heights and rebalance if necessary.
    var needRebalance = false;
    if (_insertCount++ % rebalanceThreshold == 0) {
      needRebalance = true;
    }

    for (var i = path.length - 1; i >= 0; i--) {
      final entry = path[i];
      final currentNode = entry.node..updateHeight();

      if (needRebalance) {
        final rebalancedNode = _rebalanceNode(currentNode);
        final entryParent = entry.parent;
        if (entryParent != null) {
          if (entryParent.left == currentNode) {
            entryParent.left = rebalancedNode;
          } else if (entryParent.right == currentNode) {
            entryParent.right = rebalancedNode;
          }
        } else {
          // This is the root node.
          rootNode = rebalancedNode;
        }
      }
    }

    return rootNode;
  }

  AVLNode<K, V> _rebalanceNode(AVLNode<K, V> node) {
    final balanceFactor = node.getBalanceFactor();

    if (balanceFactor > 1) {
      // Left heavy.
      if (node.left != null && node.left!.getBalanceFactor() >= 0) {
        // Left Left Case.
        return node.rotateRight();
      } else if (node.left != null) {
        // Left Right Case.
        node.left = node.left!.rotateLeft();
        return node.rotateRight();
      }
    }

    if (balanceFactor < -1) {
      // Right heavy.
      if (node.right != null && node.right!.getBalanceFactor() <= 0) {
        // Right Right Case.
        return node.rotateLeft();
      } else if (node.right != null) {
        // Right Left Case.
        node.right = node.right!.rotateRight();
        return node.rotateLeft();
      }
    }

    return node;
  }
}
