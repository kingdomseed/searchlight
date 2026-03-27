// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/core/database.dart' show SearchAlgorithm;
import 'package:searchlight/src/core/exceptions.dart';
import 'package:searchlight/src/core/schema.dart';
import 'package:searchlight/src/core/types.dart';
import 'package:searchlight/src/scoring/bm25.dart';
import 'package:searchlight/src/scoring/pt15.dart' as pt15;
import 'package:searchlight/src/scoring/qps.dart';
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

  /// Position buckets for PT15 string fields.
  position,
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
    required this.algorithm,
    required this.indexes,
    required this.searchableProperties,
    required this.searchablePropertiesWithTypes,
    required this.frequencies,
    required this.tokenOccurrences,
    required this.avgFieldLength,
    required this.fieldLengths,
    required this.qpsStats,
  });

  /// Creates a [SearchIndex] from a [Schema], mapping each field to the
  /// appropriate tree type.
  ///
  /// Matches Orama's `create` function from `index.ts:138-212`.
  factory SearchIndex.create({
    required Schema schema,
    SearchAlgorithm algorithm = SearchAlgorithm.bm25,
  }) {
    final indexes = <String, IndexTree>{};
    final searchableProperties = <String>[];
    final searchablePropertiesWithTypes = <String, SchemaType>{};
    final frequencies = <String, Map<int, Map<String, double>>>{};
    final tokenOccurrences = <String, Map<String, int>>{};
    final avgFieldLength = <String, double>{};
    final fieldLengths = <String, Map<int, int>>{};
    final qpsStats = <String, QPSStats>{};

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
      algorithm: algorithm,
      qpsStats: qpsStats,
    );

    return SearchIndex._(
      algorithm: algorithm,
      indexes: indexes,
      searchableProperties: searchableProperties,
      searchablePropertiesWithTypes: searchablePropertiesWithTypes,
      frequencies: frequencies,
      tokenOccurrences: tokenOccurrences,
      avgFieldLength: avgFieldLength,
      fieldLengths: fieldLengths,
      qpsStats: qpsStats,
    );
  }

  /// Restores a [SearchIndex] from serialized component state.
  factory SearchIndex.fromJson(
    Map<String, Object?> json, {
    required SearchAlgorithm algorithm,
  }) {
    final rawIndexes = json['indexes'];
    if (rawIndexes is! Map) {
      throw const SerializationException(
        'Missing or invalid "index.indexes" in JSON',
      );
    }

    final rawSearchableProperties = json['searchableProperties'];
    if (rawSearchableProperties is! List) {
      throw const SerializationException(
        'Missing or invalid "index.searchableProperties" in JSON',
      );
    }

    final rawSearchablePropertiesWithTypes =
        json['searchablePropertiesWithTypes'];
    if (rawSearchablePropertiesWithTypes is! Map) {
      throw const SerializationException(
        'Missing or invalid "index.searchablePropertiesWithTypes" in JSON',
      );
    }

    final indexes = <String, IndexTree>{};
    for (final entry in rawIndexes.entries) {
      final prop = entry.key as String;
      final rawTree = entry.value;
      if (rawTree is! Map) {
        throw SerializationException('Invalid serialized index for "$prop"');
      }

      final treeJson = Map<String, Object?>.from(
        rawTree.cast<Object?, Object?>(),
      );
      final rawType = treeJson['type'];
      if (rawType is! String) {
        throw SerializationException(
          'Missing or invalid tree type for "$prop"',
        );
      }

      final treeType = _treeTypeFromJsonName(rawType);
      final rawNode = treeJson['node'];
      final isArray = treeJson['isArray'] as bool? ?? false;

      indexes[prop] = IndexTree(
        type: treeType,
        node: _deserializeTreeNode(treeType, rawNode, prop),
        isArray: isArray,
      );
    }

    return SearchIndex._(
      algorithm: algorithm,
      indexes: indexes,
      searchableProperties: rawSearchableProperties.cast<String>(),
      searchablePropertiesWithTypes: {
        for (final entry in rawSearchablePropertiesWithTypes.entries)
          entry.key as String: _schemaTypeFromJsonName(
            entry.value as String,
            property: entry.key as String,
          ),
      },
      frequencies: _deserializeFrequencyMap(json['frequencies']),
      tokenOccurrences: _deserializeTokenOccurrences(json['tokenOccurrences']),
      avgFieldLength: _deserializeAvgFieldLength(json['avgFieldLength']),
      fieldLengths: _deserializeFieldLengths(json['fieldLengths']),
      qpsStats: _deserializeQpsStats(json['qpsStats']),
    );
  }

  /// The scoring algorithm used for string field indexing and search.
  final SearchAlgorithm algorithm;

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

  /// Per-property QPS statistics (only populated when algorithm is QPS).
  final Map<String, QPSStats> qpsStats;

  /// The number of documents currently indexed.
  int _docsCount = 0;

  /// The number of documents currently indexed.
  int get docsCount => _docsCount;

  /// Restores the indexed document count after loading a serialized snapshot.
  // ignore: use_setters_to_change_properties
  void restoreDocsCount(int count) {
    _docsCount = count;
  }

  /// Serializes the search index to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return {
      'indexes': {
        for (final entry in indexes.entries)
          entry.key: {
            'type': _treeTypeToJsonName(entry.value.type),
            'node': _serializeTreeNode(entry.value),
            'isArray': entry.value.isArray,
          },
      },
      'searchableProperties': List<String>.from(searchableProperties),
      'searchablePropertiesWithTypes': {
        for (final entry in searchablePropertiesWithTypes.entries)
          entry.key: entry.value.name,
      },
      'frequencies': {
        for (final propEntry in frequencies.entries)
          propEntry.key: {
            for (final docEntry in propEntry.value.entries)
              docEntry.key.toString(): {
                for (final tokenEntry in docEntry.value.entries)
                  tokenEntry.key: tokenEntry.value,
              },
          },
      },
      'tokenOccurrences': {
        for (final propEntry in tokenOccurrences.entries)
          propEntry.key: Map<String, int>.from(propEntry.value),
      },
      'avgFieldLength': {
        for (final entry in avgFieldLength.entries) entry.key: entry.value,
      },
      'fieldLengths': {
        for (final propEntry in fieldLengths.entries)
          propEntry.key: {
            for (final docEntry in propEntry.value.entries)
              docEntry.key.toString(): docEntry.value,
          },
      },
      if (qpsStats.isNotEmpty)
        'qpsStats': {
          for (final entry in qpsStats.entries) entry.key: entry.value.toJson(),
        },
    };
  }

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
      final isBm25StringArray = algorithm == SearchAlgorithm.bm25 &&
          isArray &&
          indexTree.type == TreeType.radix &&
          value is List;
      final isQpsStringArray = algorithm == SearchAlgorithm.qps &&
          isArray &&
          indexTree.type == TreeType.radix &&
          value is List;

      if (isBm25StringArray) {
        _insertBm25StringArray(
          prop,
          docId,
          value.cast<Object>(),
          indexTree,
          tokenizer,
        );
        continue;
      }
      if (isQpsStringArray) {
        _insertQpsStringArray(
          prop,
          docId,
          value.cast<Object>(),
          indexTree,
          tokenizer,
          language,
        );
        continue;
      }

      // Searchlight hardening: for BM25 string arrays we score the entire
      // property once using the concatenated token stream, then index every
      // element's tokens.
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

  void _insertBm25StringArray(
    String prop,
    int docId,
    List<Object> values,
    IndexTree indexTree,
    Tokenizer tokenizer,
  ) {
    final node = indexTree.node as RadixTree;
    final allTokens = <String>[];

    for (final value in values) {
      final tokens = tokenizer.tokenize(
        value as String,
        property: prop,
        withCache: false,
      );
      allTokens.addAll(tokens);
      for (final token in tokens) {
        node.insert(token, docId);
      }
    }

    _insertDocumentScoreParameters(prop, docId, allTokens);
    for (final token in allTokens.toSet()) {
      _insertTokenScoreParameters(prop, docId, allTokens, token);
    }
  }

  void _insertQpsStringArray(
    String prop,
    int docId,
    List<Object> values,
    IndexTree indexTree,
    Tokenizer tokenizer,
    String? language,
  ) {
    final node = indexTree.node as RadixTree;
    final stats = qpsStats[prop]!;
    stats.tokenQuantums[docId] = {};

    for (final value in values) {
      qpsInsertString(
        value: value as String,
        radixTree: node,
        stats: stats,
        prop: prop,
        internalId: docId,
        tokenizer: tokenizer,
        language: language,
      );
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
        switch (algorithm) {
          case SearchAlgorithm.bm25:
            final node = indexTree.node as RadixTree;
            // Item 10: Orama passes withCache=false during insert tokenization
            final tokens = tokenizer.tokenize(
              value as String,
              property: prop,
              withCache: false,
            );

            _insertDocumentScoreParameters(prop, docId, tokens);
            for (final token in tokens) {
              node.insert(token, docId);
            }
            for (final token in tokens.toSet()) {
              _insertTokenScoreParameters(prop, docId, tokens, token);
            }
          case SearchAlgorithm.qps:
            final node = indexTree.node as RadixTree;
            final stats = qpsStats[prop]!;
            stats.tokenQuantums[docId] = {};
            qpsInsertString(
              value: value as String,
              radixTree: node,
              stats: stats,
              prop: prop,
              internalId: docId,
              tokenizer: tokenizer,
              language: language,
            );
          case SearchAlgorithm.pt15:
            // PT15 uses position tree type, not radix — should not reach here
            break;
        }
      case TreeType.flat:
        final node = indexTree.node as FlatTree;
        node.insert(value, docId);
      case TreeType.bkd:
        final node = indexTree.node as BKDTree;
        final point = value as GeoPoint;
        node.insert(point, [docId]);
      case TreeType.position:
        final storage = indexTree.node as pt15.PositionsStorage;
        pt15.insertString(
          value: value as String,
          positionsStorage: storage,
          prop: prop,
          internalId: docId,
          language: language,
          tokenizer: tokenizer,
        );
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
    final currentAvg = avgFieldLength[prop];
    final safeAvg = currentAvg == null || currentAvg.isNaN ? 0.0 : currentAvg;
    avgFieldLength[prop] =
        (safeAvg * (_docsCount - 1) + tokens.length) / _docsCount;
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

      final isBm25StringArray = algorithm == SearchAlgorithm.bm25 &&
          indexTree.isArray &&
          indexTree.type == TreeType.radix &&
          value is List;

      if (isBm25StringArray) {
        _removeBm25StringArray(
          prop,
          docId,
          value.cast<Object>(),
          indexTree,
          tokenizer,
        );
        continue;
      }

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

  void _removeBm25StringArray(
    String prop,
    int docId,
    List<Object> values,
    IndexTree indexTree,
    Tokenizer tokenizer,
  ) {
    final node = indexTree.node as RadixTree;
    final allTokens = <String>[];

    for (final value in values) {
      final tokens = tokenizer.tokenize(
        value as String,
        property: prop,
      );
      allTokens.addAll(tokens);
    }

    _removeDocumentScoreParameters(prop, docId);
    for (final token in allTokens.toSet()) {
      _removeTokenScoreParameters(prop, token);
    }
    for (final token in allTokens) {
      node.removeDocumentByWord(token, docId);
    }
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
        switch (algorithm) {
          case SearchAlgorithm.bm25:
            final node = indexTree.node as RadixTree;
            final tokens = tokenizer.tokenize(
              value as String,
              property: prop,
            );
            _removeDocumentScoreParameters(prop, docId);
            for (final token in tokens.toSet()) {
              _removeTokenScoreParameters(prop, token);
            }
            for (final token in tokens) {
              node.removeDocumentByWord(token, docId);
            }
          case SearchAlgorithm.qps:
            final node = indexTree.node as RadixTree;
            final stats = qpsStats[prop]!;
            qpsRemoveString(
              value: value as String,
              radixTree: node,
              stats: stats,
              prop: prop,
              internalId: docId,
              tokenizer: tokenizer,
              language: language,
            );
          case SearchAlgorithm.pt15:
            // PT15 uses position tree type, not radix — should not reach here
            break;
        }
      case TreeType.flat:
        final node = indexTree.node as FlatTree;
        node.removeDocument(docId, value);
      case TreeType.bkd:
        final node = indexTree.node as BKDTree;
        final point = value as GeoPoint;
        node.removeDocByID(point, docId);
      case TreeType.position:
        final storage = indexTree.node as pt15.PositionsStorage;
        pt15.removeString(
          value: value as String,
          positionsStorage: storage,
          prop: prop,
          internalId: docId,
          tokenizer: tokenizer,
          language: language,
        );
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
      // Dart's closest equivalent to Orama's `undefined` is an absent key.
      // Leaving a stored NaN here poisons subsequent inserts because NaN
      // does not trigger the `?? 0`-style fallback used for fresh averages.
      avgFieldLength.remove(prop);
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
    // PT15 does not support tolerance or exact matching (matching Orama).
    if (algorithm == SearchAlgorithm.pt15) {
      if (tolerance != 0) {
        throw const QueryException(
          'Tolerance is not supported with the PT15 algorithm',
        );
      }
      if (exact) {
        throw const QueryException(
          'Exact matching is not supported with the PT15 algorithm',
        );
      }
    }

    switch (algorithm) {
      case SearchAlgorithm.bm25:
        return _searchBM25(
          term: term,
          tokenizer: tokenizer,
          propertiesToSearch: propertiesToSearch,
          relevance: relevance,
          exact: exact,
          tolerance: tolerance,
          boost: boost,
          whereFiltersIDs: whereFiltersIDs,
          threshold: threshold,
          language: language,
        );
      case SearchAlgorithm.qps:
        return _searchQPS(
          term: term,
          tokenizer: tokenizer,
          propertiesToSearch: propertiesToSearch,
          exact: exact,
          tolerance: tolerance,
          boost: boost,
          whereFiltersIDs: whereFiltersIDs,
          language: language,
        );
      case SearchAlgorithm.pt15:
        return _searchPT15(
          term: term,
          tokenizer: tokenizer,
          propertiesToSearch: propertiesToSearch,
          boost: boost,
          whereFiltersIDs: whereFiltersIDs,
        );
    }
  }

  // ---------------------------------------------------------------------------
  // BM25 search (original implementation)
  // ---------------------------------------------------------------------------

  List<TokenScore> _searchBM25({
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

  // ---------------------------------------------------------------------------
  // QPS search
  // ---------------------------------------------------------------------------

  List<TokenScore> _searchQPS({
    required String term,
    required Tokenizer tokenizer,
    required List<String> propertiesToSearch,
    bool exact = false,
    int tolerance = 0,
    Map<String, double> boost = const {},
    Set<int>? whereFiltersIDs,
    String? language,
  }) {
    final tokens = tokenizer.tokenize(term);
    final resultMap = <int, (double, int)>{};

    for (final prop in propertiesToSearch) {
      if (!indexes.containsKey(prop)) continue;

      final tree = indexes[prop]!;
      if (tree.type != TreeType.radix) {
        throw QueryException(
          "Property '$prop' is not a searchable string field "
          '(type: ${tree.type})',
        );
      }

      final boostPerProp = boost[prop] ?? 1.0;
      if (boostPerProp <= 0) {
        throw QueryException(
          'Invalid boost value: $boostPerProp. '
          'Boost must be greater than 0.',
        );
      }

      final stats = qpsStats[prop]!;
      final node = tree.node as RadixTree;

      qpsSearchString(
        tokens: tokens,
        radixNode: node,
        exact: exact,
        tolerance: tolerance,
        stats: stats,
        boostPerProp: boostPerProp,
        resultMap: resultMap,
        whereFiltersIDs: whereFiltersIDs,
      );
    }

    // Extract score (first element of tuple) and sort descending
    final results = resultMap.entries
        .map<TokenScore>((e) => (e.key, e.value.$1))
        .toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));

    return results;
  }

  // ---------------------------------------------------------------------------
  // PT15 search
  // ---------------------------------------------------------------------------

  List<TokenScore> _searchPT15({
    required String term,
    required Tokenizer tokenizer,
    required List<String> propertiesToSearch,
    Map<String, double> boost = const {},
    Set<int>? whereFiltersIDs,
  }) {
    final propertyStorages = <String, pt15.PositionsStorage>{};

    for (final prop in propertiesToSearch) {
      if (!indexes.containsKey(prop)) continue;

      final tree = indexes[prop]!;
      if (tree.type != TreeType.position) {
        throw QueryException(
          "Property '$prop' is not a searchable string field "
          '(type: ${tree.type})',
        );
      }

      propertyStorages[prop] = tree.node as pt15.PositionsStorage;
    }

    final results = pt15.searchProperties(
      tokenizer: tokenizer,
      term: term,
      propertyStorages: propertyStorages,
      boost: boost,
      whereFiltersIDs: whereFiltersIDs,
    );

    // Sort by score descending
    return results..sort((a, b) => b.$2.compareTo(a.$2));
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
    Map<String, Map<int, int>> fieldLengths, {
    SearchAlgorithm algorithm = SearchAlgorithm.bm25,
    Map<String, QPSStats>? qpsStats,
  }) {
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
            algorithm: algorithm,
            qpsStats: qpsStats,
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
              switch (algorithm) {
                case SearchAlgorithm.bm25:
                  indexes[path] = IndexTree(
                    type: TreeType.radix,
                    node: RadixTree(),
                    isArray: isArray,
                  );
                  avgFieldLength[path] = 0;
                  frequencies[path] = {};
                  tokenOccurrences[path] = {};
                  fieldLengths[path] = {};
                case SearchAlgorithm.qps:
                  indexes[path] = IndexTree(
                    type: TreeType.radix,
                    node: RadixTree(),
                    isArray: isArray,
                  );
                  qpsStats![path] = QPSStats();
                case SearchAlgorithm.pt15:
                  indexes[path] = IndexTree(
                    type: TreeType.position,
                    node: pt15.createPositionsStorage(),
                    isArray: isArray,
                  );
              }
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

  static Object _serializeTreeNode(IndexTree tree) {
    return switch (tree.type) {
      TreeType.radix => (tree.node as RadixTree).toJson(),
      TreeType.avl => (tree.node as AVLTree<num, int>).toJson(),
      TreeType.bool => (tree.node as BoolNode<int>).toJson(),
      TreeType.flat => (tree.node as FlatTree).toJson(),
      TreeType.bkd => (tree.node as BKDTree).toJson(),
      TreeType.position => _serializePositionsStorage(
          tree.node as pt15.PositionsStorage,
        ),
    };
  }

  static Object _deserializeTreeNode(
    TreeType type,
    Object? rawNode,
    String property,
  ) {
    return switch (type) {
      TreeType.radix => RadixTree.fromJson(
          _asObjectMap(rawNode, 'Invalid Radix tree for "$property"'),
        ),
      TreeType.avl => AVLTree<num, int>.fromJson(
          _asDynamicMap(rawNode, 'Invalid AVL tree for "$property"'),
          keyFromJson: (value) => value as num,
          valueFromJson: (value) => value as int,
        ),
      TreeType.bool => BoolNode.fromJson<int>(
          _asObjectMap(rawNode, 'Invalid Bool tree for "$property"'),
        ),
      TreeType.flat => FlatTree.fromJson(
          Map<String, Object>.from(
            _asObjectMap(rawNode, 'Invalid Flat tree for "$property"'),
          ),
        ),
      TreeType.bkd => BKDTree.fromJson(
          _asDynamicMap(rawNode, 'Invalid BKD tree for "$property"'),
        ),
      TreeType.position => _deserializePositionsStorage(rawNode, property),
    };
  }

  static List<Object?> _serializePositionsStorage(
    pt15.PositionsStorage storage,
  ) {
    return [
      for (final bucket in storage)
        {
          for (final entry in bucket.entries)
            entry.key: List<int>.from(entry.value),
        },
    ];
  }

  static pt15.PositionsStorage _deserializePositionsStorage(
    Object? raw,
    String property,
  ) {
    if (raw is! List || raw.length != pt15.maxPosition) {
      throw SerializationException(
        'Invalid position storage for "$property"',
      );
    }

    return [
      for (final bucket in raw)
        {
          for (final entry in _asMap(
            bucket,
            'Invalid position bucket for "$property"',
          ).entries)
            _asString(
              entry.key,
              'Invalid position token for "$property"',
            ): _asList(
              entry.value,
              'Invalid position token list for "$property"',
            ).cast<int>(),
        },
    ];
  }

  static FrequencyMap _deserializeFrequencyMap(Object? raw) {
    if (raw == null) return <String, Map<int, Map<String, double>>>{};
    final rawMap = _asMap(raw, 'Invalid "index.frequencies" payload');

    return {
      for (final propEntry in rawMap.entries)
        _asString(
          propEntry.key,
          'Invalid indexed property name in frequencies',
        ): {
          for (final docEntry in _asMap(
            propEntry.value,
            'Invalid frequency map for "${propEntry.key}"',
          ).entries)
            int.parse(
              _asString(
                docEntry.key,
                'Invalid frequency document ID for "${propEntry.key}"',
              ),
            ): {
              for (final tokenEntry in _asMap(
                docEntry.value,
                'Invalid token frequency map for "${propEntry.key}"',
              ).entries)
                _asString(
                  tokenEntry.key,
                  'Invalid token key for "${propEntry.key}"',
                ): _asNum(
                  tokenEntry.value,
                  'Invalid token frequency for "${propEntry.key}"',
                ).toDouble(),
            },
        },
    };
  }

  static Map<String, Map<String, int>> _deserializeTokenOccurrences(
    Object? raw,
  ) {
    if (raw == null) return <String, Map<String, int>>{};
    final rawMap = _asMap(raw, 'Invalid "index.tokenOccurrences" payload');

    return {
      for (final propEntry in rawMap.entries)
        _asString(
          propEntry.key,
          'Invalid indexed property name in token occurrences',
        ): {
          for (final tokenEntry in _asMap(
            propEntry.value,
            'Invalid token occurrences for "${propEntry.key}"',
          ).entries)
            _asString(
              tokenEntry.key,
              'Invalid token key for "${propEntry.key}"',
            ): _asInt(
              tokenEntry.value,
              'Invalid token occurrence count for "${propEntry.key}"',
            ),
        },
    };
  }

  static Map<String, double> _deserializeAvgFieldLength(Object? raw) {
    if (raw == null) return <String, double>{};
    final rawMap = _asMap(raw, 'Invalid "index.avgFieldLength" payload');

    return {
      for (final entry in rawMap.entries)
        _asString(entry.key, 'Invalid property name in avgFieldLength'): _asNum(
          entry.value,
          'Invalid avgFieldLength value for "${entry.key}"',
        ).toDouble(),
    };
  }

  static Map<String, Map<int, int>> _deserializeFieldLengths(Object? raw) {
    if (raw == null) return <String, Map<int, int>>{};
    final rawMap = _asMap(raw, 'Invalid "index.fieldLengths" payload');

    return {
      for (final propEntry in rawMap.entries)
        _asString(
          propEntry.key,
          'Invalid indexed property name in field lengths',
        ): {
          for (final docEntry in _asMap(
            propEntry.value,
            'Invalid field lengths for "${propEntry.key}"',
          ).entries)
            int.parse(
              _asString(
                docEntry.key,
                'Invalid field length document ID for "${propEntry.key}"',
              ),
            ): _asInt(
              docEntry.value,
              'Invalid field length value for "${propEntry.key}"',
            ),
        },
    };
  }

  static Map<String, QPSStats> _deserializeQpsStats(Object? raw) {
    if (raw == null) return <String, QPSStats>{};
    final rawMap = _asMap(raw, 'Invalid "index.qpsStats" payload');

    return {
      for (final entry in rawMap.entries)
        _asString(entry.key, 'Invalid indexed property name in qpsStats'):
            QPSStats.fromJson(
          _asObjectMap(entry.value, 'Invalid QPS stats for "${entry.key}"'),
        ),
    };
  }

  static TreeType _treeTypeFromJsonName(String name) {
    return switch (name) {
      'Radix' => TreeType.radix,
      'AVL' => TreeType.avl,
      'Bool' => TreeType.bool,
      'Flat' => TreeType.flat,
      'BKD' => TreeType.bkd,
      'Position' => TreeType.position,
      _ => throw SerializationException('Unknown index tree type: $name'),
    };
  }

  static String _treeTypeToJsonName(TreeType type) {
    return switch (type) {
      TreeType.radix => 'Radix',
      TreeType.avl => 'AVL',
      TreeType.bool => 'Bool',
      TreeType.flat => 'Flat',
      TreeType.bkd => 'BKD',
      TreeType.position => 'Position',
    };
  }

  static SchemaType _schemaTypeFromJsonName(
    String name, {
    required String property,
  }) {
    for (final type in SchemaType.values) {
      if (type.name == name) {
        return type;
      }
    }
    throw SerializationException(
      'Unknown schema type "$name" for indexed property "$property"',
    );
  }

  static Map<Object?, Object?> _asMap(Object? raw, String message) {
    if (raw is! Map) {
      throw SerializationException(message);
    }
    return raw.cast<Object?, Object?>();
  }

  static Map<String, Object?> _asObjectMap(Object? raw, String message) {
    return Map<String, Object?>.from(_asMap(raw, message));
  }

  static Map<String, dynamic> _asDynamicMap(Object? raw, String message) {
    return Map<String, dynamic>.from(_asMap(raw, message));
  }

  static List<Object?> _asList(Object? raw, String message) {
    if (raw is! List) {
      throw SerializationException(message);
    }
    return List<Object?>.from(raw);
  }

  static String _asString(Object? raw, String message) {
    if (raw is! String) {
      throw SerializationException(message);
    }
    return raw;
  }

  static int _asInt(Object? raw, String message) {
    if (raw is! int) {
      throw SerializationException(message);
    }
    return raw;
  }

  static num _asNum(Object? raw, String message) {
    if (raw is! num) {
      throw SerializationException(message);
    }
    return raw;
  }
}
