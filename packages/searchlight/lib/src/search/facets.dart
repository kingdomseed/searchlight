// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;

import 'package:searchlight/src/core/document.dart';
import 'package:searchlight/src/core/schema.dart';
import 'package:searchlight/src/core/types.dart';
import 'package:searchlight/src/indexing/index_manager.dart';

/// Computes facets for the given search [results].
///
/// Matches Orama's `getFacets` from `facets.ts`.
///
/// Operates on the FULL result set (before pagination). For each field in
/// [facetsConfig], counts occurrences of each value across all result
/// documents.
Map<String, FacetResult> getFacets({
  required Map<int, Document> documents,
  required List<TokenScore> results,
  required Map<String, FacetConfig> facetsConfig,
  required Map<String, SchemaType> propertiesWithTypes,
}) {
  final facets = <String, FacetResult>{};
  final allIDs = results.map((r) => r.$1).toList();

  for (final entry in facetsConfig.entries) {
    final facetField = entry.key;
    final config = entry.value;
    final propertyType = propertiesWithTypes[facetField];

    // Item 14: Pre-initialize number range buckets with 0 counts
    // Matches Orama: values = Object.fromEntries(ranges.map(r => ['from-to', 0]))
    final values = <String, int>{};
    if ((propertyType == SchemaType.number ||
            propertyType == SchemaType.numberArray) &&
        config.ranges != null) {
      for (final range in config.ranges!) {
        values['${range.from}-${range.to}'] = 0;
      }
    }

    for (final docId in allIDs) {
      final doc = documents[docId];
      if (doc == null) continue;

      final rawValue = _resolveValue(doc.toMap(), facetField);
      if (rawValue == null) continue;

      switch (propertyType) {
        case SchemaType.string:
          _countStringValue(values, rawValue as String);
        case SchemaType.boolean:
          _countStringValue(values, rawValue.toString());
        case SchemaType.number:
          _countNumberValue(values, rawValue as num, config.ranges ?? []);
        case SchemaType.enumType:
          _countStringValue(values, rawValue.toString());
        // Item 4: Array types use alreadyInsertedValues Set per document
        // to prevent double-counting. Matches Orama's pattern.
        case SchemaType.stringArray:
          if (rawValue is List) {
            final alreadyInserted = <String>{};
            for (final v in rawValue) {
              final sv = v as String;
              if (alreadyInserted.contains(sv)) continue;
              _countStringValue(values, sv);
              alreadyInserted.add(sv);
            }
          }
        case SchemaType.numberArray:
          if (rawValue is List) {
            final alreadyInserted = <String>{};
            for (final v in rawValue) {
              _countNumberValueWithDedup(
                values,
                v as num,
                config.ranges ?? [],
                alreadyInserted,
              );
            }
          }
        case SchemaType.booleanArray:
          if (rawValue is List) {
            final alreadyInserted = <String>{};
            for (final v in rawValue) {
              final sv = v.toString();
              if (alreadyInserted.contains(sv)) continue;
              _countStringValue(values, sv);
              alreadyInserted.add(sv);
            }
          }
        case SchemaType.enumArray:
          if (rawValue is List) {
            final alreadyInserted = <String>{};
            for (final v in rawValue) {
              final sv = v.toString();
              if (alreadyInserted.contains(sv)) continue;
              _countStringValue(values, sv);
              alreadyInserted.add(sv);
            }
          }
        case SchemaType.geopoint || null:
          break; // Not facetable
      }
    }

    // Count distinct values
    final count = values.length;

    // Sort and paginate string facets
    Map<String, int> finalValues;
    if (propertyType == SchemaType.string) {
      final sorted = values.entries.toList();
      if (config.sort == FacetSorting.asc) {
        sorted.sort((a, b) => a.value.compareTo(b.value));
      } else {
        sorted.sort((a, b) => b.value.compareTo(a.value));
      }
      // Item 3: Match Orama's slice(offset, limit) semantics.
      // Orama: Object.entries(values).sort(pred).slice(offset, limit)
      // JS slice(start, end) returns items from start up to (not including) end.
      final offset = config.offset;
      final limit = config.limit;
      final end = math.min(limit, sorted.length);
      final start = math.min(offset, sorted.length);
      final sliced = sorted.sublist(start, end);
      finalValues = Map.fromEntries(sliced);
    } else {
      finalValues = values;
    }

    facets[facetField] = FacetResult(count: count, values: finalValues);
  }

  return facets;
}

void _countStringValue(Map<String, int> values, String value) {
  values[value] = (values[value] ?? 0) + 1;
}

void _countNumberValue(
  Map<String, int> values,
  num value,
  List<NumberFacetRange> ranges,
) {
  for (final range in ranges) {
    final key = '${range.from}-${range.to}';
    if (value >= range.from && value <= range.to) {
      values[key] = (values[key] ?? 0) + 1;
    }
  }
}

/// Number facet counting with per-document deduplication.
///
/// Matches Orama's `calculateNumberFacetBuilder` with `alreadyInsertedValues`.
void _countNumberValueWithDedup(
  Map<String, int> values,
  num value,
  List<NumberFacetRange> ranges,
  Set<String> alreadyInserted,
) {
  for (final range in ranges) {
    final key = '${range.from}-${range.to}';
    if (alreadyInserted.contains(key)) continue;
    if (value >= range.from && value <= range.to) {
      values[key] = (values[key] ?? 0) + 1;
      alreadyInserted.add(key);
    }
  }
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
