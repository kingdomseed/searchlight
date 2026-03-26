// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/core/exceptions.dart';
import 'package:searchlight/src/core/types.dart';
import 'package:searchlight/src/indexing/index_manager.dart';
import 'package:searchlight/src/text/tokenizer.dart';
import 'package:searchlight/src/trees/avl_tree.dart';
import 'package:searchlight/src/trees/bkd_tree.dart';
import 'package:searchlight/src/trees/bool_node.dart';
import 'package:searchlight/src/trees/flat_tree.dart';
import 'package:searchlight/src/trees/radix_tree.dart';

// ---------------------------------------------------------------------------
// Filter sealed hierarchy
// ---------------------------------------------------------------------------

/// A filter condition for querying indexed fields.
///
/// Matches Orama's `WhereCondition` filter operations.
sealed class Filter {
  /// Creates a [Filter].
  const Filter();
}

/// Exact equality filter.
final class EqFilter extends Filter {
  /// Creates an [EqFilter] matching [value].
  const EqFilter(this.value);

  /// The value to match.
  final Object value;
}

/// Greater-than filter (number fields).
final class GtFilter extends Filter {
  /// Creates a [GtFilter] for values > [value].
  const GtFilter(this.value);

  /// The threshold value.
  final num value;
}

/// Greater-than-or-equal filter (number fields).
final class GteFilter extends Filter {
  /// Creates a [GteFilter] for values >= [value].
  const GteFilter(this.value);

  /// The threshold value.
  final num value;
}

/// Less-than filter (number fields).
final class LtFilter extends Filter {
  /// Creates a [LtFilter] for values < [value].
  const LtFilter(this.value);

  /// The threshold value.
  final num value;
}

/// Less-than-or-equal filter (number fields).
final class LteFilter extends Filter {
  /// Creates a [LteFilter] for values <= [value].
  const LteFilter(this.value);

  /// The threshold value.
  final num value;
}

/// Range filter (number fields, inclusive on both ends).
final class BetweenFilter extends Filter {
  /// Creates a [BetweenFilter] matching values in [min]..[max].
  const BetweenFilter(this.min, this.max);

  /// The lower bound (inclusive).
  final num min;

  /// The upper bound (inclusive).
  final num max;
}

/// Inclusion filter (enum/flat fields).
final class InFilter extends Filter {
  /// Creates an [InFilter] matching any of [values].
  const InFilter(this.values);

  /// The set of acceptable values.
  final List<Object> values;
}

/// Exclusion filter (enum/flat fields).
final class NinFilter extends Filter {
  /// Creates a [NinFilter] excluding all of [values].
  const NinFilter(this.values);

  /// The set of excluded values.
  final List<Object> values;
}

/// Contains-all filter (enum array fields).
final class ContainsAllFilter extends Filter {
  /// Creates a [ContainsAllFilter] requiring all [values].
  const ContainsAllFilter(this.values);

  /// The values that must all be present.
  final List<Object> values;
}

/// Contains-any filter (enum array fields).
final class ContainsAnyFilter extends Filter {
  /// Creates a [ContainsAnyFilter] requiring any of [values].
  const ContainsAnyFilter(this.values);

  /// The values, at least one of which must be present.
  final List<Object> values;
}

/// Geo-radius filter (geopoint fields).
final class GeoRadiusFilter extends Filter {
  /// Creates a [GeoRadiusFilter].
  const GeoRadiusFilter({
    required this.lat,
    required this.lon,
    required this.radius,
    this.unit = DistanceUnit.m,
    this.inside = true,
    this.highPrecision = false,
  });

  /// Center latitude.
  final double lat;

  /// Center longitude.
  final double lon;

  /// Radius value in the given [unit].
  final double radius;

  /// Distance unit (default meters).
  final DistanceUnit unit;

  /// Whether to return points inside (true) or outside (false) the radius.
  final bool inside;

  /// Whether to use high-precision (Vincenty) distance.
  final bool highPrecision;
}

/// Geo-polygon filter (geopoint fields).
final class GeoPolygonFilter extends Filter {
  /// Creates a [GeoPolygonFilter].
  const GeoPolygonFilter({
    required this.coordinates,
    this.inside = true,
    this.highPrecision = false,
  });

  /// The polygon vertices.
  final List<({double lat, double lon})> coordinates;

  /// Whether to return points inside (true) or outside (false) the polygon.
  final bool inside;

  /// Whether to use high-precision distance for sorting.
  final bool highPrecision;
}

/// Logical AND combinator: intersection of all sub-filter results.
final class AndFilter extends Filter {
  /// Creates an [AndFilter] combining [filters] with AND.
  const AndFilter(this.filters);

  /// Each element is a property-name -> Filter map.
  final List<Map<String, Filter>> filters;
}

/// Logical OR combinator: union of all sub-filter results.
final class OrFilter extends Filter {
  /// Creates an [OrFilter] combining [filters] with OR.
  const OrFilter(this.filters);

  /// Each element is a property-name -> Filter map.
  final List<Map<String, Filter>> filters;
}

/// Logical NOT combinator: all docs minus the sub-filter results.
final class NotFilter extends Filter {
  /// Creates a [NotFilter] negating [filter].
  const NotFilter(this.filter);

  /// The filter to negate.
  final Map<String, Filter> filter;
}

// ---------------------------------------------------------------------------
// Convenience constructors
// ---------------------------------------------------------------------------

/// Creates an [EqFilter] for exact equality.
Filter eq(Object value) => EqFilter(value);

/// Creates a [GtFilter] for greater-than.
Filter gt(num value) => GtFilter(value);

/// Creates a [GteFilter] for greater-than-or-equal.
Filter gte(num value) => GteFilter(value);

/// Creates a [LtFilter] for less-than.
Filter lt(num value) => LtFilter(value);

/// Creates a [LteFilter] for less-than-or-equal.
Filter lte(num value) => LteFilter(value);

/// Creates a [BetweenFilter] for range (inclusive).
Filter between(num min, num max) => BetweenFilter(min, max);

/// Creates an [InFilter] for set membership.
Filter inFilter(List<Object> values) => InFilter(values);

/// Creates a [NinFilter] for set exclusion.
Filter ninFilter(List<Object> values) => NinFilter(values);

/// Creates a [ContainsAllFilter] for array containment (all).
Filter filterContainsAll(List<Object> values) => ContainsAllFilter(values);

/// Creates a [ContainsAnyFilter] for array containment (any).
Filter filterContainsAny(List<Object> values) => ContainsAnyFilter(values);

/// Creates a [GeoRadiusFilter].
Filter geoRadius({
  required double lat,
  required double lon,
  required double radius,
  DistanceUnit unit = DistanceUnit.m,
  bool inside = true,
  bool highPrecision = false,
}) =>
    GeoRadiusFilter(
      lat: lat,
      lon: lon,
      radius: radius,
      unit: unit,
      inside: inside,
      highPrecision: highPrecision,
    );

/// Creates a [GeoPolygonFilter].
Filter geoPolygon({
  required List<({double lat, double lon})> coordinates,
  bool inside = true,
  bool highPrecision = false,
}) =>
    GeoPolygonFilter(
      coordinates: coordinates,
      inside: inside,
      highPrecision: highPrecision,
    );

/// Creates an [AndFilter].
Filter and(List<Map<String, Filter>> filters) => AndFilter(filters);

/// Creates an [OrFilter].
Filter or(List<Map<String, Filter>> filters) => OrFilter(filters);

/// Creates a [NotFilter].
Filter not(Map<String, Filter> filter) => NotFilter(filter);

// ---------------------------------------------------------------------------
// searchByWhereClause — matches Orama's index.ts:594-771
// ---------------------------------------------------------------------------

/// Evaluates [filters] against the [index] and returns the set of internal
/// document IDs that match all conditions.
///
/// Matches Orama's `searchByWhereClause` from `index.ts:594-771`.
///
/// - Properties are ANDed (intersection across all property filters).
/// - Logical operators (and/or/not) compose recursively.
Set<int> searchByWhereClause(
  SearchIndex index,
  Map<String, Filter> filters, {
  required Set<int> existingDocIds,
  Tokenizer? tokenizer,
  String? language,
}) {
  final filtersMap = <String, Set<int>>{};

  for (final entry in filters.entries) {
    final param = entry.key;
    final operation = entry.value;

    // Handle logical operators stored under special keys
    if (operation is AndFilter) {
      if (operation.filters.isEmpty) return {};
      final results = operation.filters
          .map(
            (f) => searchByWhereClause(
              index,
              f,
              existingDocIds: existingDocIds,
              tokenizer: tokenizer,
              language: language,
            ),
          )
          .toList();
      return _setIntersection(results);
    }

    if (operation is OrFilter) {
      if (operation.filters.isEmpty) return {};
      final results = operation.filters
          .map(
            (f) => searchByWhereClause(
              index,
              f,
              existingDocIds: existingDocIds,
              tokenizer: tokenizer,
              language: language,
            ),
          )
          .toList();
      return results.reduce((acc, s) => acc.union(s));
    }

    if (operation is NotFilter) {
      final allDocs = Set<int>.from(existingDocIds);
      final notResult = searchByWhereClause(
        index,
        operation.filter,
        existingDocIds: existingDocIds,
        tokenizer: tokenizer,
        language: language,
      );
      return allDocs.difference(notResult);
    }

    // Validate the field exists in the index
    final indexTree = index.indexes[param];
    if (indexTree == null) {
      throw QueryException(
        "Unknown filter property: '$param'",
      );
    }

    filtersMap.putIfAbsent(param, () => <int>{});

    switch (indexTree.type) {
      case TreeType.bool:
        final node = indexTree.node as BoolNode<int>;
        if (operation is EqFilter) {
          final flag = operation.value as bool;
          final ids = flag ? node.trueSet : node.falseSet;
          filtersMap[param] = filtersMap[param]!.union(ids);
        }

      case TreeType.avl:
        final node = indexTree.node as AVLTree<num, int>;
        Set<int> filteredIDs;

        switch (operation) {
          case GtFilter(:final value):
            filteredIDs = node.greaterThan(value);
          case GteFilter(:final value):
            filteredIDs = node.greaterThan(value, inclusive: true);
          case LtFilter(:final value):
            filteredIDs = node.lessThan(value);
          case LteFilter(:final value):
            filteredIDs = node.lessThan(value, inclusive: true);
          case EqFilter(:final value):
            filteredIDs = node.find(value as num) ?? {};
          case BetweenFilter(:final min, :final max):
            filteredIDs = node.rangeSearch(min, max);
          default:
            throw QueryException(
              "Invalid filter operation for AVL field '$param'",
            );
        }

        filtersMap[param] = filtersMap[param]!.union(filteredIDs);

      case TreeType.flat:
        final node = indexTree.node as FlatTree;
        List<int> results;

        if (indexTree.isArray) {
          switch (operation) {
            case ContainsAllFilter(:final values):
              results = node.filterContainsAll(values);
            case ContainsAnyFilter(:final values):
              results = node.filterContainsAny(values);
            default:
              throw QueryException(
                "Invalid filter operation for array enum field '$param'",
              );
          }
        } else {
          switch (operation) {
            case EqFilter(:final value):
              results = node.filterEq(value);
            case InFilter(:final values):
              results = node.filterIn(values);
            case NinFilter(:final values):
              results = node.filterNin(values);
            default:
              throw QueryException(
                "Invalid filter operation for enum field '$param'",
              );
          }
        }

        filtersMap[param] = filtersMap[param]!.union(results.toSet());

      case TreeType.bkd:
        final node = indexTree.node as BKDTree;
        final Set<int> geoIDs;

        switch (operation) {
          case GeoRadiusFilter(
              :final lat,
              :final lon,
              :final radius,
              :final unit,
              :final inside,
              :final highPrecision,
            ):
            final center = GeoPoint(lat: lat, lon: lon);
            final distanceInMeters =
                BKDTree.convertDistanceToMeters(radius, unit);
            final results = node.searchByRadius(
              center,
              distanceInMeters,
              inclusive: inside,
              sort: null,
              highPrecision: highPrecision,
            );
            geoIDs = <int>{};
            for (final r in results) {
              geoIDs.addAll(r.docIDs);
            }
          case GeoPolygonFilter(
              :final coordinates,
              :final inside,
              :final highPrecision,
            ):
            final polygon = coordinates
                .map((c) => GeoPoint(lat: c.lat, lon: c.lon))
                .toList();
            final results = node.searchByPolygon(
              polygon,
              inclusive: inside,
              highPrecision: highPrecision,
            );
            geoIDs = <int>{};
            for (final r in results) {
              geoIDs.addAll(r.docIDs);
            }
          default:
            throw QueryException(
              "Invalid filter operation for geopoint field '$param'",
            );
        }

        filtersMap[param] = filtersMap[param]!.union(geoIDs);

      case TreeType.radix:
        // Item 2: Orama supports string/array where-clause filters on Radix
        // fields by tokenizing the filter value and performing exact find.
        // Matches Orama's index.ts:699-708.
        final node = indexTree.node as RadixTree;
        if (tokenizer == null) {
          throw QueryException(
            'Tokenizer required for string field filter on '
            "'$param'.",
          );
        }

        if (operation is EqFilter && operation.value is String) {
          final raw = operation.value as String;
          final terms = tokenizer.tokenize(raw, property: param);
          for (final t in terms) {
            final foundResult = node.find(term: t, exact: true);
            final ids = foundResult[t];
            if (ids != null) {
              filtersMap[param] = filtersMap[param]!.union(ids.toSet());
            }
          }
        } else if (operation is InFilter) {
          // Phase 6 audit D1: Orama QPS handles Array.isArray(filter) on
          // string fields by tokenizing each item and taking the first token,
          // then performing an exact find. Union results across all values.
          for (final value in operation.values) {
            if (value is! String) continue;
            final terms = tokenizer.tokenize(value, property: param);
            if (terms.isEmpty) continue;
            final token = terms.first;
            final foundResult = node.find(term: token, exact: true);
            final ids = foundResult[token];
            if (ids != null) {
              filtersMap[param] = filtersMap[param]!.union(ids.toSet());
            }
          }
        } else {
          throw QueryException(
            'Invalid filter operation for string field '
            "'$param'. Use EqFilter with a String value or InFilter "
            'with a list of String values.',
          );
        }

      case TreeType.position:
        // PT15 doesn't support string where-clause filters (matching Orama).
        throw QueryException(
          "String filters are not supported for PT15 field '$param'.",
        );
    }
  }

  if (filtersMap.isEmpty) return {};

  // AND: intersect all property filter results
  return _setIntersection(filtersMap.values.toList());
}

/// Computes the intersection of multiple sets.
Set<int> _setIntersection(List<Set<int>> sets) {
  if (sets.isEmpty) return {};
  if (sets.length == 1) return sets.first;

  // Start with the smallest set for efficiency
  final sorted = [...sets]..sort((a, b) => a.length.compareTo(b.length));
  var result = Set<int>.of(sorted.first);

  for (var i = 1; i < sorted.length; i++) {
    result = result.intersection(sorted[i]);
    if (result.isEmpty) return {};
  }

  return result;
}
