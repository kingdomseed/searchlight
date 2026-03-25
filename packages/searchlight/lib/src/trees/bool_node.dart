// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// A boolean index node that partitions values into `true` and `false` sets.
///
/// Mirrors Orama's `BoolNode` from `trees/bool.ts`.
final class BoolNode<V> {
  /// Creates an empty [BoolNode].
  BoolNode();

  /// Values associated with `true`.
  final Set<V> trueSet = {};

  /// Values associated with `false`.
  final Set<V> falseSet = {};

  /// Inserts [value] into the set identified by [flag].
  void insert(V value, {required bool flag}) {
    if (flag) {
      trueSet.add(value);
    } else {
      falseSet.add(value);
    }
  }

  /// Removes [value] from the set identified by [flag].
  void delete(V value, {required bool flag}) {
    if (flag) {
      trueSet.remove(value);
    } else {
      falseSet.remove(value);
    }
  }

  /// The total number of values across both sets.
  int get size => trueSet.length + falseSet.length;

  /// Serializes this node to a JSON-compatible map.
  ///
  /// The map uses `'true'` and `'false'` keys with [List] values,
  /// matching Orama's `toJSON` output.
  Map<String, Object?> toJson() {
    return {
      'true': trueSet.toList(),
      'false': falseSet.toList(),
    };
  }

  /// Deserializes a [BoolNode] from a JSON-compatible map.
  static BoolNode<V> fromJson<V>(Map<String, Object?> json) {
    final node = BoolNode<V>();
    final trueList = json['true']! as List<dynamic>;
    final falseList = json['false']! as List<dynamic>;
    node.trueSet.addAll(trueList.cast<V>());
    node.falseSet.addAll(falseList.cast<V>());
    return node;
  }
}
