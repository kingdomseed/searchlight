// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// A flat index that maps scalar keys to sets of document IDs.
///
/// Mirrors Orama's `FlatTree` from `trees/flat.ts`.
/// Used for enum/equality-based fields.
final class FlatTree {
  /// Creates an empty [FlatTree].
  FlatTree();

  /// Deserializes a [FlatTree] from a JSON map produced by [toJson].
  ///
  /// Throws [ArgumentError] if the JSON is missing `numberToDocumentId`.
  factory FlatTree.fromJson(Map<String, Object> json) {
    final raw = json['numberToDocumentId'];
    if (raw == null) {
      throw ArgumentError('Invalid Flat Tree JSON');
    }
    final entries = raw as List<Object?>;
    final tree = FlatTree();
    for (final entry in entries) {
      final pair = entry! as List<Object?>;
      final key = pair[0]!;
      final ids = (pair[1]! as List<Object?>).cast<int>();
      tree._data[key] = ids.toSet();
    }
    return tree;
  }

  final Map<Object, Set<int>> _data = {};

  /// Adds [docId] to the set for [key].
  void insert(Object key, int docId) {
    (_data[key] ??= {}).add(docId);
  }

  /// Returns the document IDs for [key], or `null` if [key] is absent.
  List<int>? find(Object key) {
    return _data[key]?.toList();
  }

  /// Removes [docId] from [key]'s set. Deletes the key if the set is empty.
  void removeDocument(int docId, Object key) {
    final idSet = _data[key];
    if (idSet != null) {
      idSet.remove(docId);
      if (idSet.isEmpty) {
        _data.remove(key);
      }
    }
  }

  /// Returns `true` if [key] exists in the tree.
  bool contains(Object key) => _data.containsKey(key);

  /// Returns the total number of document IDs across all keys.
  int getSize() {
    var size = 0;
    for (final idSet in _data.values) {
      size += idSet.length;
    }
    return size;
  }

  /// Returns document IDs matching [value] exactly, or an empty list.
  List<int> filterEq(Object value) {
    final idSet = _data[value];
    return idSet != null ? idSet.toList() : [];
  }

  /// Returns the union of document IDs for any of the given [values].
  List<int> filterIn(List<Object> values) {
    final result = <int>{};
    for (final value in values) {
      final idSet = _data[value];
      if (idSet != null) {
        result.addAll(idSet);
      }
    }
    return result.toList();
  }

  /// Returns document IDs for keys NOT in [excludeValues].
  List<int> filterNin(List<Object> excludeValues) {
    final excluded = excludeValues.toSet();
    final result = <int>{};
    for (final entry in _data.entries) {
      if (!excluded.contains(entry.key)) {
        result.addAll(entry.value);
      }
    }
    return result.toList();
  }

  /// Returns document IDs that appear in the sets of ALL given [values].
  List<int> filterContainsAll(List<Object> values) {
    if (values.isEmpty) return [];
    final idSets = values.map((v) => _data[v] ?? <int>{}).toList();
    final intersection = idSets.reduce(
      (prev, curr) => prev.intersection(curr),
    );
    return intersection.toList();
  }

  /// Returns document IDs that appear in the set of ANY of the given [values].
  List<int> filterContainsAny(List<Object> values) {
    if (values.isEmpty) return [];
    final idSets = values.map((v) => _data[v] ?? <int>{}).toList();
    final union = idSets.reduce((prev, curr) => prev.union(curr));
    return union.toList();
  }

  /// Removes an entire key and all its document IDs.
  void remove(Object key) {
    _data.remove(key);
  }

  /// Serializes the tree to a JSON-compatible map.
  ///
  /// Mirrors Orama's `toJSON()`: stores entries as a list of `[key, [ids]]`.
  Map<String, Object> toJson() {
    return {
      'numberToDocumentId': [
        for (final entry in _data.entries) [entry.key, entry.value.toList()],
      ],
    };
  }
}
