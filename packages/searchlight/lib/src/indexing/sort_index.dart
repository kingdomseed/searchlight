// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/core/exceptions.dart';
import 'package:searchlight/src/core/types.dart';
import 'package:searchlight/src/indexing/index_manager.dart';
import 'package:searchlight/src/text/diacritics.dart';

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
///
/// Item 17: Orama uses `localeCompare(a, b, locale)` for string sorting.
/// Dart's `String.compareTo` uses Unicode code-point order, which is similar
/// but not locale-aware. For full locale-aware collation, the `intl` package
/// would be needed. This implementation accepts a language parameter for
/// future locale-aware sorting.
final class SortIndex {
  /// Creates an empty [SortIndex] with optional [language] for locale sorting.
  SortIndex({this.language});

  /// Restores a [SortIndex] from serialized component state.
  factory SortIndex.fromJson(
    Map<String, Object?> json, {
    String? fallbackLanguage,
  }) {
    final index = SortIndex(
      language: json['language'] as String? ?? fallbackLanguage,
    );

    final rawSorts = json['sorts'];
    if (rawSorts == null) {
      return index;
    }
    if (rawSorts is! Map) {
      throw const SerializationException(
        'Missing or invalid "sorting.sorts" in JSON',
      );
    }

    for (final entry in rawSorts.entries) {
      final property = entry.key as String;
      final rawSort = entry.value;
      if (rawSort is! Map) {
        throw SerializationException(
          'Invalid serialized sort state for "$property"',
        );
      }

      final sortJson = Map<String, Object?>.from(rawSort);
      final sort = _PropertySort();

      final rawDocs = sortJson['docs'];
      if (rawDocs is! Map) {
        throw SerializationException(
          'Missing or invalid sort doc positions for "$property"',
        );
      }
      for (final docEntry in rawDocs.entries) {
        sort.docs[int.parse(docEntry.key as String)] = docEntry.value as int;
      }

      final rawOrderedDocs = sortJson['orderedDocs'];
      if (rawOrderedDocs is! List) {
        throw SerializationException(
          'Missing or invalid ordered docs for "$property"',
        );
      }
      for (final rawEntry in rawOrderedDocs) {
        if (rawEntry is! List || rawEntry.length != 2) {
          throw SerializationException(
            'Invalid ordered doc entry for "$property"',
          );
        }

        final docId = rawEntry[0] as int;
        final value = rawEntry[1];
        if (value is! num && value is! String && value is! bool) {
          throw SerializationException(
            'Invalid ordered doc sort value for "$property"',
          );
        }
        sort.orderedDocs.add((docId, value));
      }

      sort.isSorted = sortJson['isSorted'] as bool? ?? true;
      index._sorts[property] = sort;
    }

    return index;
  }

  /// The language for locale-aware string sorting.
  ///
  /// Matches Orama's `Sorter.language`. Currently used for documentation
  /// purposes; full locale-aware collation requires the `intl` package.
  final String? language;

  /// Per-property sort data.
  final Map<String, _PropertySort> _sorts = {};

  /// Serializes the sort index to a JSON-compatible map.
  Map<String, Object?> toJson() {
    final properties = _sorts.keys.toList()..sort();
    final sortableTypes = <String, String>{};
    final sortsJson = <String, Object?>{};
    var isSorted = true;

    for (final property in properties) {
      final sort = _sorts[property]!;
      _ensureDeletedByProperty(sort);
      _ensurePropertyIsSorted(sort);

      isSorted = isSorted && sort.isSorted;
      if (sort.orderedDocs.isNotEmpty) {
        sortableTypes[property] = _sortValueType(sort.orderedDocs.first.$2);
      }

      sortsJson[property] = {
        'docs': {
          for (final entry in sort.docs.entries)
            entry.key.toString(): entry.value,
        },
        'orderedDocs': [
          for (final entry in sort.orderedDocs) [entry.$1, entry.$2],
        ],
        'isSorted': sort.isSorted,
      };
    }

    return {
      'language': language,
      'sortableProperties': properties,
      'sortablePropertiesWithTypes': sortableTypes,
      'sorts': sortsJson,
      'enabled': true,
      'isSorted': isSorted,
    };
  }

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
        return _compareStrings(va, vb);
      }
      if (va is bool && vb is bool) {
        if (va == vb) return 0;
        return va ? 1 : -1;
      }
      return 0;
    });

    // Update position map
    for (var i = 0; i < s.orderedDocs.length; i++) {
      s.docs[s.orderedDocs[i].$1] = i;
    }

    s.isSorted = true;
  }

  int _compareStrings(String a, String b) {
    final keyA = _stringSortKey(a);
    final keyB = _stringSortKey(b);
    return keyA.compareTo(keyB);
  }

  String _stringSortKey(String value) {
    final normalized = value.toLowerCase();

    switch (language) {
      case 'norwegian':
      case 'danish':
        return normalized
            .replaceAll('æ', '{a')
            .replaceAll('ø', '{b')
            .replaceAll('å', '{c');
      case 'swedish':
        return normalized
            .replaceAll('å', '{a')
            .replaceAll('ä', '{b')
            .replaceAll('ö', '{c');
      case 'german':
        return normalized
            .replaceAll('ä', 'ae')
            .replaceAll('ö', 'oe')
            .replaceAll('ü', 'ue')
            .replaceAll('ß', 'ss');
      default:
        return replaceDiacritics(normalized);
    }
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

  static String _sortValueType(SortValue value) {
    if (value is String) return 'string';
    if (value is num) return 'number';
    if (value is bool) return 'boolean';
    throw SerializationException(
      'Unsupported sort value type: ${value.runtimeType}',
    );
  }
}
