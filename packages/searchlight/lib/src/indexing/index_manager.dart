// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/core/exceptions.dart';
import 'package:searchlight/src/core/schema.dart';
import 'package:searchlight/src/core/types.dart';
import 'package:searchlight/src/scoring/bm25.dart';
import 'package:searchlight/src/text/tokenizer.dart';
import 'package:searchlight/src/trees/avl_tree.dart';
import 'package:searchlight/src/trees/bkd_tree.dart';
import 'package:searchlight/src/trees/bool_node.dart';
import 'package:searchlight/src/trees/flat_tree.dart';
import 'package:searchlight/src/trees/radix_tree.dart';

/// A scored search result: (internalDocId, score).
///
/// Matches Orama's `TokenScore` type.
typedef TokenScore = (int docId, double score);

/// The type of tree backing an index for a field.
///
/// Matches Orama's `TreeType` from `index.ts`.
enum TreeType {
  /// Radix tree for string fields (full-text search).
  radix,

  /// AVL tree for number fields (range queries).
  avl,

  /// Bool node for boolean fields.
  bool,

  /// Flat tree for enum fields (equality/set queries).
  flat,

  /// BKD tree for geopoint fields (radius/polygon queries).
  bkd,
}

/// A tagged tree wrapper storing the tree type, node, and whether it is
/// an array field.
///
/// Matches Orama's `TTree` from `index.ts`.
final class IndexTree {
  /// Creates an [IndexTree].
  const IndexTree({
    required this.type,
    required this.node,
    required this.isArray,
  });

  /// The type of tree.
  final TreeType type;

  /// The underlying tree node.
  final Object node;

  /// Whether the field is an array type.
  final bool isArray;
}

/// Frequency map: property -> docId -> { token: tf }.
///
/// Matches Orama's `FrequencyMap` from `index.ts`.
typedef FrequencyMap = Map<String, Map<int, Map<String, double>>>;

/// The search index managing per-field tree indexes and BM25 scoring data.
///
/// Matches Orama's `Index` interface from `index.ts`.
final class SearchIndex {
  SearchIndex._({
    required this.indexes,
    required this.searchableProperties,
    required this.searchablePropertiesWithTypes,
    required this.frequencies,
    required this.tokenOccurrences,
    required this.avgFieldLength,
    required this.fieldLengths,
  });

  /// Creates a [SearchIndex] from a [Schema], mapping each field to the
  /// appropriate tree type.
  ///
  /// Matches Orama's `create` function from `index.ts:138-212`.
  factory SearchIndex.create({required Schema schema}) {
    final indexes = <String, IndexTree>{};
    final searchableProperties = <String>[];
    final searchablePropertiesWithTypes = <String, SchemaType>{};
    final frequencies = <String, Map<int, Map<String, double>>>{};
    final tokenOccurrences = <String, Map<String, int>>{};
    final avgFieldLength = <String, double>{};
    final fieldLengths = <String, Map<int, int>>{};

    _buildIndexes(
      schema.fields,
      '',
      indexes,
      searchableProperties,
      searchablePropertiesWithTypes,
      frequencies,
      tokenOccurrences,
      avgFieldLength,
      fieldLengths,
    );

    return SearchIndex._(
      indexes: indexes,
      searchableProperties: searchableProperties,
      searchablePropertiesWithTypes: searchablePropertiesWithTypes,
      frequencies: frequencies,
      tokenOccurrences: tokenOccurrences,
      avgFieldLength: avgFieldLength,
      fieldLengths: fieldLengths,
    );
  }

  /// Per-field tree indexes.
  final Map<String, IndexTree> indexes;

  /// All indexed field paths.
  final List<String> searchableProperties;

  /// Field path -> SchemaType mapping.
  final Map<String, SchemaType> searchablePropertiesWithTypes;

  /// prop -> docId -> { token: tf }.
  final FrequencyMap frequencies;

  /// prop -> token -> document count.
  final Map<String, Map<String, int>> tokenOccurrences;

  /// prop -> average token count across all documents.
  final Map<String, double> avgFieldLength;

  /// prop -> docId -> token count.
  final Map<String, Map<int, int>> fieldLengths;

  /// The number of documents currently indexed.
  int _docsCount = 0;

  /// The number of documents currently indexed.
  int get docsCount => _docsCount;

  /// Returns the [TreeType] for the given field [path].
  TreeType treeTypeAt(String path) => indexes[path]!.type;

  /// Inserts a document into all applicable indexes.
  ///
  /// [docId] is the internal numeric document ID.
  /// [data] is a flat map of field values (may contain nested maps).
  /// [tokenizer] is used for string field tokenization.
  ///
  /// Matches Orama's `insert` function from `index.ts:260-297`.
  void insertDocument({
    required int docId,
    required Map<String, Object?> data,
    required Tokenizer tokenizer,
    String? language,
  }) {
    _docsCount++;

    for (final prop in searchableProperties) {
      final value = resolveValue(data, prop);
      if (value == null) continue;

      final indexTree = indexes[prop];
      if (indexTree == null) continue;

      final isArray = indexTree.isArray;

      // Orama: insertScalarBuilder is called per element, and each call
      // to the Radix case calls insertDocumentScoreParameters. So for
      // arrays, scoring is done per element (last element overwrites).
      if (isArray && value is List) {
        for (final element in value) {
          _insertScalar(
            prop,
            docId,
            element as Object,
            indexTree,
            tokenizer,
            language,
          );
        }
      } else {
        _insertScalar(prop, docId, value, indexTree, tokenizer, language);
      }
    }
  }

  void _insertScalar(
    String prop,
    int docId,
    Object value,
    IndexTree indexTree,
    Tokenizer tokenizer,
    String? language,
  ) {
    switch (indexTree.type) {
      case TreeType.bool:
        final node = indexTree.node as BoolNode<int>;
        node.insert(docId, flag: value as bool);
      case TreeType.avl:
        final node = indexTree.node as AVLTree<num, int>;
        node.insert(value as num, docId);
      case TreeType.radix:
        final node = indexTree.node as RadixTree;
        // Item 10: Orama passes withCache=false during insert tokenization
        final tokens = tokenizer.tokenize(
          value as String,
          property: prop,
          withCache: false,
        );

        // Item 9: Orama's insertScalarBuilder calls
        // insertDocumentScoreParameters for EVERY element (including array
        // elements). For arrays, the last element's tokens overwrite.
        _insertDocumentScoreParameters(prop, docId, tokens);
        for (final token in tokens) {
          _insertTokenScoreParameters(prop, docId, tokens, token);
          node.insert(token, docId);
        }
      case TreeType.flat:
        final node = indexTree.node as FlatTree;
        node.insert(value, docId);
      case TreeType.bkd:
        final node = indexTree.node as BKDTree;
        final point = value as GeoPoint;
        node.insert(point, [docId]);
    }
  }

  /// Updates avgFieldLength, fieldLengths, and initializes frequencies for a
  /// document.
  ///
  /// Matches Orama's `insertDocumentScoreParameters` from `index.ts:79-91`.
  void _insertDocumentScoreParameters(
    String prop,
    int docId,
    List<String> tokens,
  ) {
    avgFieldLength[prop] =
        ((avgFieldLength[prop] ?? 0) * (_docsCount - 1) + tokens.length) /
            _docsCount;
    fieldLengths[prop]![docId] = tokens.length;
    frequencies[prop]![docId] = {};
  }

  /// Counts token frequency in a document and computes TF.
  ///
  /// Matches Orama's `insertTokenScoreParameters` from `index.ts:93-119`.
  void _insertTokenScoreParameters(
    String prop,
    int docId,
    List<String> tokens,
    String token,
  ) {
    var tokenFrequency = 0;
    for (final t in tokens) {
      if (t == token) tokenFrequency++;
    }

    final tf = tokenFrequency / tokens.length;
    frequencies[prop]![docId]![token] = tf;

    tokenOccurrences[prop]![token] = (tokenOccurrences[prop]![token] ?? 0) + 1;
  }

  /// Removes a document from all applicable indexes.
  ///
  /// Matches Orama's `remove` function from `index.ts:359-406`.
  void removeDocument({
    required int docId,
    required Map<String, Object?> data,
    required Tokenizer tokenizer,
    String? language,
  }) {
    for (final prop in searchableProperties) {
      final value = resolveValue(data, prop);
      if (value == null) continue;

      final indexTree = indexes[prop];
      if (indexTree == null) continue;

      if (indexTree.isArray && value is List) {
        for (final element in value) {
          _removeScalar(
            prop,
            docId,
            element as Object,
            indexTree,
            tokenizer,
            language,
          );
        }
      } else {
        _removeScalar(prop, docId, value, indexTree, tokenizer, language);
      }
    }

    _docsCount--;
  }

  void _removeScalar(
    String prop,
    int docId,
    Object value,
    IndexTree indexTree,
    Tokenizer tokenizer,
    String? language,
  ) {
    switch (indexTree.type) {
      case TreeType.bool:
        final node = indexTree.node as BoolNode<int>;
        node.delete(docId, flag: value as bool);
      case TreeType.avl:
        final node = indexTree.node as AVLTree<num, int>;
        node.removeDocument(value as num, docId);
      case TreeType.radix:
        final node = indexTree.node as RadixTree;
        final tokens = tokenizer.tokenize(
          value as String,
          property: prop,
        );
        _removeDocumentScoreParameters(prop, docId);
        for (final token in tokens) {
          _removeTokenScoreParameters(prop, token);
          node.removeDocumentByWord(token, docId);
        }
      case TreeType.flat:
        final node = indexTree.node as FlatTree;
        node.removeDocument(docId, value);
      case TreeType.bkd:
        final node = indexTree.node as BKDTree;
        final point = value as GeoPoint;
        node.removeDocByID(point, docId);
    }
  }

  /// Recalculates avgFieldLength, clears fieldLengths and frequencies for doc.
  ///
  /// Matches Orama's `removeDocumentScoreParameters` from `index.ts:121-132`.
  void _removeDocumentScoreParameters(String prop, int docId) {
    if (_docsCount > 1) {
      avgFieldLength[prop] = (avgFieldLength[prop]! * _docsCount -
              (fieldLengths[prop]![docId] ?? 0)) /
          (_docsCount - 1);
    } else {
      // Item 11: Orama sets avgFieldLength[prop] = undefined, which
      // becomes NaN in subsequent calculations. Match that behavior.
      avgFieldLength[prop] = double.nan;
    }
    fieldLengths[prop]!.remove(docId);
    frequencies[prop]!.remove(docId);
  }

  /// Decrements tokenOccurrences for a token.
  ///
  /// Matches Orama's `removeTokenScoreParameters` from `index.ts:134-136`.
  void _removeTokenScoreParameters(String prop, String token) {
    final count = tokenOccurrences[prop]![token];
    if (count != null) {
      tokenOccurrences[prop]![token] = count - 1;
    }
  }

  /// Searches the index for [term] across [propertiesToSearch] and returns
  /// scored results.
  ///
  /// Matches Orama's `search` function from `index.ts:457-592`.
  ///
  /// Parameters:
  /// - [term]: The search query string.
  /// - [tokenizer]: Tokenizer for breaking the term into tokens.
  /// - [propertiesToSearch]: Which string fields to search.
  /// - [relevance]: BM25 tuning parameters.
  /// - [exact]: If true, only exact word matches are returned.
  /// - [tolerance]: Levenshtein distance for fuzzy matching.
  /// - [boost]: Per-property score multipliers.
  /// - [whereFiltersIDs]: If provided, only score these document IDs.
  /// - [threshold]: 0 = all terms required, 1 = any term, between = percentage.
  List<TokenScore> search({
    required String term,
    required Tokenizer tokenizer,
    required List<String> propertiesToSearch,
    required BM25Params relevance,
    bool exact = false,
    int tolerance = 0,
    Map<String, double> boost = const {},
    Set<int>? whereFiltersIDs,
    double threshold = 0,
    String? language,
  }) {
    final tokens = tokenizer.tokenize(term);
    final keywordsCount = tokens.isEmpty ? 1 : tokens.length;

    // Track keyword matches per document and property
    final keywordMatchesMap = <int, Map<String, int>>{};
    // Track which tokens were found in the search
    final tokenFoundMap = <String, bool>{};
    final resultsMap = <int, double>{};

    for (final prop in propertiesToSearch) {
      if (!indexes.containsKey(prop)) continue;

      final tree = indexes[prop]!;
      // Item 13: Orama throws WRONG_SEARCH_PROPERTY_TYPE for non-Radix
      if (tree.type != TreeType.radix) {
        throw QueryException(
          "Property '$prop' is not a searchable string field "
          '(type: ${tree.type})',
        );
      }

      final boostPerProperty = boost[prop] ?? 1.0;
      // Item 12: Orama throws INVALID_BOOST_VALUE for boost <= 0
      if (boostPerProperty <= 0) {
        throw QueryException(
          'Invalid boost value: $boostPerProperty. '
          'Boost must be greater than 0.',
        );
      }
      final node = tree.node as RadixTree;

      // If the tokenizer returns an empty list, search for empty string
      if (tokens.isEmpty && term.isEmpty) {
        tokens.add('');
      }

      for (final token in tokens) {
        final searchResult = node.find(
          term: token,
          exact: exact,
          tolerance: tolerance > 0 ? tolerance : null,
        );

        final termsFound = searchResult.keys.toList();
        if (termsFound.isNotEmpty) {
          tokenFoundMap[token] = true;
        }

        for (final word in termsFound) {
          final ids = searchResult[word]!;
          _calculateResultScores(
            prop,
            word,
            ids,
            relevance,
            resultsMap,
            boostPerProperty,
            whereFiltersIDs,
            keywordMatchesMap,
          );
        }
      }
    }

    // Convert to list and sort by score descending
    final results = resultsMap.entries
        .map<TokenScore>((e) => (e.key, e.value))
        .toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));

    if (results.isEmpty) return [];

    // threshold = 1: return all results
    if (threshold == 1) return results;

    // threshold = 0: require all keywords
    if (threshold == 0) {
      if (keywordsCount == 1) return results;

      // Verify all tokens were found
      for (final token in tokens) {
        if (tokenFoundMap[token] != true) return [];
      }

      // Filter to documents matching all keywords in at least one property
      return results.where((r) {
        final propertyMatches = keywordMatchesMap[r.$1];
        if (propertyMatches == null) return false;
        return propertyMatches.values.any((m) => m == keywordsCount);
      }).toList();
    }

    // Partial threshold: full matches + percentage of partial matches
    final fullMatches = results.where((r) {
      final propertyMatches = keywordMatchesMap[r.$1];
      if (propertyMatches == null) return false;
      return propertyMatches.values.any((m) => m == keywordsCount);
    }).toList();

    if (fullMatches.isNotEmpty) {
      final fullMatchIds = fullMatches.map((r) => r.$1).toSet();
      final remaining =
          results.where((r) => !fullMatchIds.contains(r.$1)).toList();
      final additionalCount = (remaining.length * threshold).ceil();
      return [...fullMatches, ...remaining.take(additionalCount)];
    }

    return results;
  }

  /// Calculates BM25 scores for matching documents.
  ///
  /// Matches Orama's `calculateResultScores` from `index.ts:408-455`.
  void _calculateResultScores(
    String prop,
    String term,
    List<int> ids,
    BM25Params relevance,
    Map<int, double> resultsMap,
    double boostPerProperty,
    Set<int>? whereFiltersIDs,
    Map<int, Map<String, int>> keywordMatchesMap,
  ) {
    final avgFL = avgFieldLength[prop] ?? 0;
    final fLengths = fieldLengths[prop] ?? {};
    final occurrences = tokenOccurrences[prop] ?? {};
    final freqs = frequencies[prop] ?? {};

    final termOccurrences = occurrences[term] ?? 0;

    for (final internalId in ids) {
      if (whereFiltersIDs != null && !whereFiltersIDs.contains(internalId)) {
        continue;
      }

      // Track keyword matches per property
      keywordMatchesMap.putIfAbsent(internalId, () => {});
      final propertyMatches = keywordMatchesMap[internalId]!;
      propertyMatches[prop] = (propertyMatches[prop] ?? 0) + 1;

      final tf = freqs[internalId]?[term] ?? 0;
      final fieldLen = fLengths[internalId] ?? 0;

      final score = bm25(
        tf: tf,
        matchingCount: termOccurrences,
        docsCount: _docsCount,
        fieldLength: fieldLen,
        averageFieldLength: avgFL,
        params: relevance,
      );

      final boostedScore = score * boostPerProperty;
      resultsMap[internalId] = (resultsMap[internalId] ?? 0) + boostedScore;
    }
  }

  /// Resolves a dot-separated path in a nested map.
  static Object? resolveValue(Map<String, Object?> data, String path) {
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

  static void _buildIndexes(
    Map<String, SchemaField> fields,
    String prefix,
    Map<String, IndexTree> indexes,
    List<String> searchableProperties,
    Map<String, SchemaType> searchablePropertiesWithTypes,
    FrequencyMap frequencies,
    Map<String, Map<String, int>> tokenOccurrences,
    Map<String, double> avgFieldLength,
    Map<String, Map<int, int>> fieldLengths,
  ) {
    for (final entry in fields.entries) {
      final path = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';

      switch (entry.value) {
        case NestedField(:final children):
          _buildIndexes(
            children,
            path,
            indexes,
            searchableProperties,
            searchablePropertiesWithTypes,
            frequencies,
            tokenOccurrences,
            avgFieldLength,
            fieldLengths,
          );
        case TypedField(:final type):
          final isArray = switch (type) {
            SchemaType.stringArray ||
            SchemaType.numberArray ||
            SchemaType.booleanArray ||
            SchemaType.enumArray =>
              true,
            _ => false,
          };

          switch (type) {
            case SchemaType.string || SchemaType.stringArray:
              indexes[path] = IndexTree(
                type: TreeType.radix,
                node: RadixTree(),
                isArray: isArray,
              );
              avgFieldLength[path] = 0;
              frequencies[path] = {};
              tokenOccurrences[path] = {};
              fieldLengths[path] = {};
            case SchemaType.number || SchemaType.numberArray:
              // Orama: new AVLTree<number, InternalDocumentID>(0, [])
              indexes[path] = IndexTree(
                type: TreeType.avl,
                node: AVLTree<num, int>(key: 0, values: []),
                isArray: isArray,
              );
            case SchemaType.boolean || SchemaType.booleanArray:
              indexes[path] = IndexTree(
                type: TreeType.bool,
                node: BoolNode<int>(),
                isArray: isArray,
              );
            case SchemaType.enumType || SchemaType.enumArray:
              indexes[path] = IndexTree(
                type: TreeType.flat,
                node: FlatTree(),
                isArray: isArray,
              );
            case SchemaType.geopoint:
              indexes[path] = IndexTree(
                type: TreeType.bkd,
                node: BKDTree(),
                isArray: false,
              );
          }

          searchableProperties.add(path);
          searchablePropertiesWithTypes[path] = type;
      }
    }
  }
}
