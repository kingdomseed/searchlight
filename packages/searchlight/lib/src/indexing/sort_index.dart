// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/core/types.dart';
import 'package:searchlight/src/indexing/index_manager.dart';

/// A sort value stored per document.
typedef SortValue = Object;

/// Per-property sort data.
///
/// Matches Orama's `PropertySort` from `sorter.ts`.
final class _PropertySort {
  _PropertySort();

  /// docId -> position in orderedDocs.
  final Map<int, int> docs = {};

  /// Ordered list of (docId, value) pairs.
  final List<(int, SortValue)> orderedDocs = [];

  /// Set of docIds marked for lazy removal.
  final Set<int> orderedDocsToRemove = {};

  /// Whether the orderedDocs are currently sorted.
  bool isSorted = true;
}

/// A sort index that stores sortable field values per document for efficient
/// sorting at search time.
///
/// Matches Orama's `Sorter` from `sorter.ts`.
///
/// The sort index is populated during insert (not during search). At search
/// time, [sortBy] sorts results by pre-computed field values instead of by
/// relevance score.
final class SortIndex {
  /// Creates an empty [SortIndex].
  SortIndex();

  /// Per-property sort data.
  final Map<String, _PropertySort> _sorts = {};

  /// Inserts a document's sortable value for a property.
  ///
  /// Matches Orama's `insert` from `sorter.ts`.
  void insert({
    required String property,
    required int docId,
    required SortValue value,
  }) {
    final s = _sorts.putIfAbsent(property, _PropertySort.new)..isSorted = false;

    // If the doc was previously marked for removal, clean up first
    if (s.orderedDocsToRemove.contains(docId)) {
      _ensureDeletedByProperty(s);
    }

    s.docs[docId] = s.orderedDocs.length;
    s.orderedDocs.add((docId, value));
  }

  /// Removes a document from the sort index for a property.
  ///
  /// Uses lazy deletion matching Orama's `remove` from `sorter.ts`.
  void remove({
    required String property,
    required int docId,
  }) {
    final s = _sorts[property];
    if (s == null) return;

    final index = s.docs[docId];
    if (index == null) return;

    s.docs.remove(docId);
    s.orderedDocsToRemove.add(docId);
  }

  /// Sorts search results by a field value instead of by score.
  ///
  /// Matches Orama's `sortBy` from `sorter.ts`.
  List<TokenScore> sortBy({
    required List<TokenScore> results,
    required String property,
    required SortOrder order,
  }) {
    final s = _sorts[property];
    if (s == null) return results;

    _ensureDeletedByProperty(s);
    _ensurePropertyIsSorted(s);

    final isDesc = order == SortOrder.desc;

    final sorted = List<TokenScore>.from(results)
      ..sort((a, b) {
        final indexOfA = s.docs[a.$1];
        final indexOfB = s.docs[b.$1];
        final isAIndexed = indexOfA != null;
        final isBIndexed = indexOfB != null;

        if (!isAIndexed && !isBIndexed) return 0;
        // Unindexed documents are always at the end
        if (!isAIndexed) return 1;
        if (!isBIndexed) return -1;

        return isDesc ? indexOfB - indexOfA : indexOfA - indexOfB;
      });

    return sorted;
  }

  /// Sorts the orderedDocs for a property and updates position map.
  void _ensurePropertyIsSorted(_PropertySort s) {
    if (s.isSorted) return;

    s.orderedDocs.sort((a, b) {
      final va = a.$2;
      final vb = b.$2;
      if (va is num && vb is num) {
        return va.compareTo(vb);
      }
      if (va is String && vb is String) {
        return va.compareTo(vb);
      }
      if (va is bool && vb is bool) {
        return vb ? -1 : 1;
      }
      return 0;
    });

    // Update position map
    for (var i = 0; i < s.orderedDocs.length; i++) {
      s.docs[s.orderedDocs[i].$1] = i;
    }

    s.isSorted = true;
  }

  /// Removes lazily-deleted docs from orderedDocs.
  void _ensureDeletedByProperty(_PropertySort s) {
    if (s.orderedDocsToRemove.isEmpty) return;

    s.orderedDocs.removeWhere(
      (entry) => s.orderedDocsToRemove.contains(entry.$1),
    );
    s.orderedDocsToRemove.clear();

    // Rebuild position map
    for (var i = 0; i < s.orderedDocs.length; i++) {
      s.docs[s.orderedDocs[i].$1] = i;
    }
  }
}
