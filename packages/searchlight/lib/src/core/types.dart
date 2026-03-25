// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';
import 'package:searchlight/src/core/doc_id.dart';
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

/// A grouping specification for search results.
final class GroupBy {
  /// Creates a [GroupBy] on [field] with the given [limit] per group.
  const GroupBy({required this.field, required this.limit});

  /// The field to group on.
  final String field;

  /// Maximum number of hits per group.
  final int limit;
}

/// Configuration for faceted search on a field.
final class FacetConfig {
  /// Creates a [FacetConfig] with the given [limit] of facet values.
  const FacetConfig({required this.limit});

  /// Maximum number of facet values to return.
  final int limit;
}

/// A single facet value with its occurrence count.
final class FacetValue {
  /// Creates a [FacetValue] with the given [value] and [count].
  const FacetValue({required this.value, required this.count});

  /// The facet value (e.g. a category name).
  final String value;

  /// The number of documents matching this value.
  final int count;
}

/// A single search hit with its document, score, and ID.
final class SearchHit {
  /// Creates a [SearchHit] with the given [id], [score], and [document].
  const SearchHit({
    required this.id,
    required this.score,
    required this.document,
  });

  /// The document ID.
  final DocId id;

  /// The relevance score.
  final double score;

  /// The matched document.
  final Document document;
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

  /// Facet values keyed by field name, if facets were requested.
  final Map<String, List<FacetValue>>? facets;

  /// Grouped hits keyed by group value, if grouping was requested.
  final Map<String, List<SearchHit>>? groups;
}

/// An error that occurred while processing a single document in a batch.
final class BatchError {
  /// Creates a [BatchError] at [index] with the given [error].
  const BatchError({required this.index, required this.error});

  /// The zero-based index in the batch where the error occurred.
  final int index;

  /// The error that occurred.
  final Object error;
}

/// The result of a batch insert operation.
final class BatchResult {
  /// Creates a [BatchResult] with the given [insertedIds] and [errors].
  const BatchResult({required this.insertedIds, required this.errors});

  /// IDs of successfully inserted documents.
  final List<DocId> insertedIds;

  /// Errors encountered during the batch, if any.
  final List<BatchError> errors;

  /// Whether any errors occurred during the batch.
  bool get hasErrors => errors.isNotEmpty;
}
