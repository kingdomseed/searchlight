// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/core/document.dart';
import 'package:searchlight/src/core/exceptions.dart';
import 'package:searchlight/src/core/schema.dart';
import 'package:searchlight/src/core/types.dart';
import 'package:searchlight/src/indexing/index_manager.dart';

/// Allowed schema types for group-by properties.
///
/// Matches Orama's `ALLOWED_TYPES = ['string', 'number', 'boolean']`.
const Set<SchemaType> _allowedGroupTypes = {
  SchemaType.string,
  SchemaType.number,
  SchemaType.boolean,
};

/// Groups search results by one or more field values.
///
/// Matches Orama's `getGroups` from `groups.ts`, including:
/// - Multi-property grouping with Cartesian product combinations (Item 5)
/// - Property validation (Item 15)
/// - Custom reduce function support (Item 16)
///
/// Operates on the FULL result set (before pagination).
List<GroupResult> getGroups({
  required Map<int, Document> documents,
  required Map<int, String> externalIds,
  required List<TokenScore> results,
  required GroupBy groupBy,
  Map<String, SchemaType>? schemaProperties,
}) {
  final properties = groupBy.effectiveProperties;
  final maxResult = groupBy.limit;

  // Item 15: Validate group properties exist and are of allowed types
  if (schemaProperties != null) {
    for (final property in properties) {
      final type = schemaProperties[property];
      if (type == null) {
        throw QueryException(
          "Unknown group-by property: '$property'",
        );
      }
      if (!_allowedGroupTypes.contains(type)) {
        throw QueryException(
          "Invalid group-by property type: '$property' is '$type'. "
          'Allowed types: string, number, boolean.',
        );
      }
    }
  }

  // Build allDocs and allIDs
  final allIDs = <String>[];
  final allDocs = <Document?>[];
  for (final (docId, _) in results) {
    final extId = externalIds[docId];
    allIDs.add(extId ?? '');
    allDocs.add(documents[docId]);
  }

  // Per-property grouping: for each property, build a map of
  // value -> { indexes, count }
  final g = <String, _PropertyGroup>{};
  final listOfValues = <List<Object>>[];

  for (final property in properties) {
    final group = _PropertyGroup(property: property);
    final values = <Object>{};

    for (var j = 0; j < allDocs.length; j++) {
      final doc = allDocs[j];
      if (doc == null) continue;

      final value = _resolveValue(doc.toMap(), property);
      if (value == null) continue;

      // Orama: typeof value !== 'boolean' ? value : '' + value
      final keyValue = value is bool ? value.toString() : value;

      final perValue = group.perValue.putIfAbsent(
        keyValue.toString(),
        _PerValueData.new,
      );
      if (perValue.count >= maxResult) continue;

      perValue.indexes.add(j);
      perValue.count++;

      values.add(value);
    }

    listOfValues.add(values.toList());
    g[property] = group;
  }

  // Calculate Cartesian product combinations
  final combinations = _calculateCombinations(listOfValues);

  // Build groups from combinations
  final groups = <_Group>[];
  for (final combination in combinations) {
    final group = _Group(values: [], indexes: []);
    final indexSets = <List<int>>[];

    for (var j = 0; j < combination.length; j++) {
      final value = combination[j];
      final property = properties[j];
      final keyValue = value is bool ? value.toString() : value;
      final perValue = g[property]!.perValue[keyValue.toString()];
      if (perValue == null) {
        indexSets.clear();
        break;
      }
      indexSets.add(perValue.indexes);
      group.values.add(value);
    }

    // Intersect indexes across properties
    if (indexSets.isNotEmpty) {
      group.indexes = _intersect(indexSets)..sort();
    }

    // Don't generate empty groups
    if (group.indexes.isEmpty) continue;

    groups.add(group);
  }

  // Build final result with reduce
  final result = <GroupResult>[];
  for (final group in groups) {
    final docs = group.indexes.map((index) {
      return SearchHit(
        id: allIDs[index],
        score: results[index].$2,
        document: allDocs[index]!,
      );
    }).toList();

    // Item 16: Apply custom reduce if provided
    List<SearchHit> aggregatedResult;
    if (groupBy.reduce != null) {
      final reduce = groupBy.reduce!;
      List<SearchHit> func(
        List<SearchHit> acc,
        SearchHit res,
        int index,
      ) =>
          reduce.reducer(group.values, acc, res, index);
      var accumulator = reduce.getInitialValue(docs.length);
      for (var i = 0; i < docs.length; i++) {
        accumulator = func(accumulator, docs[i], i);
      }
      aggregatedResult = accumulator;
    } else {
      aggregatedResult = docs;
    }

    result.add(GroupResult(values: group.values, result: aggregatedResult));
  }

  return result;
}

/// Calculates Cartesian product of lists of values.
///
/// Matches Orama's `calculateCombination` from `groups.ts`.
List<List<Object>> _calculateCombinations(
  List<List<Object>> arrs, [
  int index = 0,
]) {
  if (arrs.isEmpty) return [];
  if (index + 1 == arrs.length) {
    return arrs[index].map((item) => [item]).toList();
  }

  final head = arrs[index];
  final c = _calculateCombinations(arrs, index + 1);

  final combinations = <List<Object>>[];
  for (final value in head) {
    for (final combination in c) {
      combinations.add([value, ...combination]);
    }
  }

  return combinations;
}

/// Intersects multiple index lists (returns common elements).
List<int> _intersect(List<List<int>> arrays) {
  if (arrays.isEmpty) return [];
  if (arrays.length == 1) return arrays.first;

  var result = arrays.first.toSet();
  for (var i = 1; i < arrays.length; i++) {
    result = result.intersection(arrays[i].toSet());
    if (result.isEmpty) return [];
  }
  return result.toList();
}

class _PropertyGroup {
  _PropertyGroup({required this.property});
  final String property;
  final Map<String, _PerValueData> perValue = {};
}

class _PerValueData {
  final List<int> indexes = [];
  int count = 0;
}

class _Group {
  _Group({required this.values, required this.indexes});
  final List<Object> values;
  List<int> indexes;
}

/// Resolves a dot-separated path in a nested map.
Object? _resolveValue(Map<String, Object?> data, String path) {
  final segments = path.split('.');
  Object? current = data;
  for (final segment in segments) {
    if (current is Map<String, Object?>) {
      current = current[segment];
    } else {
      return null;
    }
  }
  return current;
}
