// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/core/document.dart';
import 'package:searchlight/src/core/types.dart';
import 'package:searchlight/src/indexing/index_manager.dart';

/// Groups search results by a field value.
///
/// Matches Orama's `getGroups` from `groups.ts`.
///
/// Operates on the FULL result set (before pagination). For each unique value
/// of the group field, collects the matching documents (up to the group
/// limit).
List<GroupResult> getGroups({
  required Map<int, Document> documents,
  required Map<int, String> externalIds,
  required List<TokenScore> results,
  required GroupBy groupBy,
}) {
  final field = groupBy.field;
  final maxResult = groupBy.limit;

  // Build per-value groups
  final groupMap = <String, List<SearchHit>>{};

  for (final (docId, score) in results) {
    final doc = documents[docId];
    if (doc == null) continue;
    final externalId = externalIds[docId];
    if (externalId == null) continue;

    final rawValue = _resolveValue(doc.toMap(), field);
    if (rawValue == null) continue;

    final key = rawValue.toString();

    final group = groupMap.putIfAbsent(key, () => <SearchHit>[]);
    if (group.length >= maxResult) continue;

    group.add(SearchHit(id: externalId, score: score, document: doc));
  }

  // Convert to GroupResult list
  return groupMap.entries
      .map(
        (e) => GroupResult(values: [e.key], result: e.value),
      )
      .toList();
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
