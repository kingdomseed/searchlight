// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';
import 'package:searchlight/src/core/document.dart';

/// A geographic point with latitude and longitude.
@immutable
final class GeoPoint {
  /// Creates a [GeoPoint] with the given [lat] and [lon].
  const GeoPoint({required this.lat, required this.lon});

  /// The latitude in decimal degrees.
  final double lat;

  /// The longitude in decimal degrees.
  final double lon;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeoPoint && lat == other.lat && lon == other.lon;

  @override
  int get hashCode => Object.hash(lat, lon);

  @override
  String toString() => 'GeoPoint(lat: $lat, lon: $lon)';
}

/// How the search engine combines query terms.
enum SearchMode {
  /// All terms must match.
  matchAll,

  /// Any term may match.
  matchAny,

  /// Prefix matching on the last term.
  prefix,
}

/// Sort direction.
enum SortOrder {
  /// Ascending (smallest first).
  asc,

  /// Descending (largest first).
  desc,
}

/// A sort specification for search results.
final class SortBy {
  /// Creates a [SortBy] on [field] in the given [order].
  const SortBy({required this.field, required this.order});

  /// The field to sort on.
  final String field;

  /// The sort direction.
  final SortOrder order;
}

/// A custom reduce function for group aggregation.
///
/// Matches Orama's `Reduce` type from `types.ts`.
/// The [reducer] takes the group values, accumulator, current
/// result, and index, and returns the new accumulator value.
/// The [getInitialValue] creates the initial accumulator for a
/// given result count.
final class GroupReduce<T> {
  /// Creates a [GroupReduce] with the given [reducer] and [getInitialValue].
  const GroupReduce({required this.reducer, required this.getInitialValue});

  /// Reduces a list of search hits into a custom aggregation.
  final T Function(List<Object> values, T acc, SearchHit res, int index)
      reducer;

  /// Returns the initial accumulator value for a group of the given length.
  final T Function(int length) getInitialValue;
}

/// A grouping specification for search results.
///
/// Supports multi-property grouping with Cartesian product, matching Orama's
/// `GroupByParams` which accepts `properties: string[]`.
final class GroupBy {
  /// Creates a [GroupBy] on a single [field] with the given [limit] per group.
  ///
  /// This is the backward-compatible constructor. For multi-property grouping,
  /// use [GroupBy.properties].
  const GroupBy({required String field, required this.limit, this.reduce})
      : properties = null,
        _field = field;

  /// Creates a [GroupBy] on multiple [properties] with the given [limit].
  ///
  /// Matches Orama's multi-property grouping with Cartesian product
  /// combinations.
  const GroupBy.properties({
    required this.properties,
    required this.limit,
    this.reduce,
  }) : _field = null;

  /// Single field (backward-compatible).
  final String? _field;

  /// Multiple properties for Cartesian product grouping.
  /// Matches Orama's `properties: string[]`.
  final List<String>? properties;

  /// Maximum number of hits per group.
  final int limit;

  /// Optional custom reduce function for group aggregation.
  /// Matches Orama's `reduce` parameter.
  final GroupReduce<List<SearchHit>>? reduce;

  /// Returns the effective list of properties to group by.
  List<String> get effectiveProperties =>
      properties ?? (_field != null ? [_field] : []);
}

/// Sort direction for facet value ordering.
///
/// Matches Orama's `FacetSorting` type.
enum FacetSorting {
  /// Sort by count ascending.
  asc,

  /// Sort by count descending (default).
  desc,
}

/// A numeric range for number facets.
///
/// Matches Orama's `NumberFacetDefinition.ranges` entries.
@immutable
final class NumberFacetRange {
  /// Creates a [NumberFacetRange] from [from] to [to] (inclusive).
  const NumberFacetRange({required this.from, required this.to});

  /// The lower bound (inclusive).
  final num from;

  /// The upper bound (inclusive).
  final num to;
}

/// Configuration for faceted search on a field.
///
/// Matches Orama's `StringFacetDefinition` and `NumberFacetDefinition`.
final class FacetConfig {
  /// Creates a [FacetConfig].
  ///
  /// For string/boolean facets, [limit] and [offset] control pagination of
  /// value counts. [sort] controls the ordering (default: desc by count).
  ///
  /// For number facets, [ranges] must be provided to define the buckets.
  const FacetConfig({
    this.limit = 10,
    this.offset = 0,
    this.sort = FacetSorting.desc,
    this.ranges,
  });

  /// Maximum number of facet values to return (string facets only).
  final int limit;

  /// Number of facet values to skip (string facets only).
  final int offset;

  /// Sort order for facet values (string facets only).
  final FacetSorting sort;

  /// Numeric ranges for number facets. Required when the field is a number.
  final List<NumberFacetRange>? ranges;
}

/// The result of facet computation for a single field.
///
/// Matches Orama's `FacetResult[field]` shape: `{count, values}`.
@immutable
final class FacetResult {
  /// Creates a [FacetResult].
  const FacetResult({required this.count, required this.values});

  /// The total number of distinct facet values (before offset/limit).
  final int count;

  /// Value -> occurrence count mapping.
  final Map<String, int> values;
}

/// A single search hit with its document, score, and ID.
final class SearchHit {
  /// Creates a [SearchHit] with the given [id], [score], and [document].
  const SearchHit({
    required this.id,
    required this.score,
    required this.document,
  });

  /// The external string document ID.
  final String id;

  /// The relevance score.
  final double score;

  /// The matched document.
  final Document document;
}

/// A group of search results sharing a common field value.
///
/// Matches Orama's `GroupResult` entries.
@immutable
final class GroupResult {
  /// Creates a [GroupResult].
  const GroupResult({required this.values, required this.result});

  /// The group key values.
  final List<Object> values;

  /// The hits in this group.
  final List<SearchHit> result;
}

/// The result of a search query.
final class SearchResult {
  /// Creates a [SearchResult] with the given [hits], [count], and [elapsed].
  const SearchResult({
    required this.hits,
    required this.count,
    required this.elapsed,
    this.facets,
    this.groups,
  });

  /// The matching hits (page of results).
  final List<SearchHit> hits;

  /// Total number of matching documents (may exceed [hits] length when paged).
  final int count;

  /// Time taken for the search.
  final Duration elapsed;

  /// Facet results keyed by field name, if facets were requested.
  ///
  /// Matches Orama's `FacetResult` shape.
  final Map<String, FacetResult>? facets;

  /// Grouped results, if grouping was requested.
  ///
  /// Each entry maps a group value to its list of hits.
  final List<GroupResult>? groups;
}
