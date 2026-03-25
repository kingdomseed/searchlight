// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert' show jsonDecode, jsonEncode, utf8;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:searchlight/src/core/doc_id.dart';
import 'package:searchlight/src/core/document.dart';
import 'package:searchlight/src/core/exceptions.dart';
import 'package:searchlight/src/core/schema.dart';
import 'package:searchlight/src/core/types.dart';
import 'package:searchlight/src/indexing/index_manager.dart';
import 'package:searchlight/src/indexing/sort_index.dart';
import 'package:searchlight/src/persistence/cbor_serializer.dart';
import 'package:searchlight/src/persistence/format.dart';
import 'package:searchlight/src/persistence/json_serializer.dart';
import 'package:searchlight/src/persistence/storage.dart';
import 'package:searchlight/src/scoring/bm25.dart';
import 'package:searchlight/src/search/facets.dart' as facets_lib;
import 'package:searchlight/src/search/filters.dart';
import 'package:searchlight/src/search/grouping.dart' as grouping_lib;
import 'package:searchlight/src/text/tokenizer.dart';
import 'package:searchlight/src/trees/bkd_tree.dart';

/// The search algorithm used for scoring.
enum SearchAlgorithm {
  /// Best Match 25 — the default probabilistic ranking function.
  bm25,

  /// Query-per-second optimized scoring.
  qps,

  /// PT-15 scoring algorithm.
  pt15,
}

/// A full-text search engine instance.
final class Searchlight {
  Searchlight._({
    required this.schema,
    required this.algorithm,
    required this.language,
    required SearchIndex index,
    required Tokenizer tokenizer,
    required SortIndex sortIndex,
  })  : _index = index,
        _tokenizer = tokenizer,
        _sortIndex = sortIndex;

  /// Creates a new Searchlight database.
  ///
  /// The [schema] defines the structure and types of documents that will be
  /// stored. The optional [algorithm] (default [SearchAlgorithm.bm25]) sets
  /// the scoring strategy. The optional [language] (default `'en'`) controls
  /// tokenization and stemming.
  factory Searchlight.create({
    required Schema schema,
    SearchAlgorithm algorithm = SearchAlgorithm.bm25,
    String language = 'en',
  }) {
    // Map short language codes to full names for the tokenizer
    const languageMap = <String, String>{
      'en': 'english',
      'de': 'german',
      'fi': 'finnish',
      'fr': 'french',
      'it': 'italian',
      'nl': 'dutch',
      'no': 'norwegian',
      'pt': 'portuguese',
      'ru': 'russian',
      'es': 'spanish',
      'sv': 'swedish',
    };
    final tokenizerLanguage = languageMap[language] ?? language;

    final tokenizer = Tokenizer(
      language: tokenizerLanguage,
      stemming: tokenizerLanguage == 'english',
    );
    final index = SearchIndex.create(schema: schema, algorithm: algorithm);

    return Searchlight._(
      schema: schema,
      algorithm: algorithm,
      language: language,
      index: index,
      tokenizer: tokenizer,
      sortIndex: SortIndex(language: tokenizerLanguage),
    );
  }

  /// Deserializes a [Searchlight] instance from a JSON-compatible map
  /// produced by [toJson].
  ///
  /// Matches Orama's `load(orama, raw)` pattern: checks the format version,
  /// then restores each component from the raw data.
  ///
  /// **Design note (A1/A2/B6):** Rather than directly deserializing index
  /// trees and sort indexes, this method creates a fresh database and
  /// re-inserts all documents in internal ID order. This re-insertion
  /// approach is simpler and produces functionally identical search results.
  /// The trade-off is O(n*m) restore time (n = documents, m = fields)
  /// compared to O(data_size) for direct tree restoration. For most use
  /// cases (< 50k documents) this is acceptable. Direct tree serialization
  /// can be added as a future optimization.
  ///
  /// Throws [SerializationException] if the format version is incompatible
  /// or the data is corrupt/missing.
  factory Searchlight.fromJson(Map<String, Object?> json) {
    // 1. Check format version.
    // E2 fix: reject future versions but accept current and past versions.
    // When a future version bump adds structural changes, add migration logic
    // here (e.g., `if (version == 1) json = _migrateFromV1(json);`).
    final version = json['formatVersion'];
    if (version is! int || version > currentFormatVersion) {
      throw SerializationException(
        'Incompatible format version: $version '
        '(max supported: $currentFormatVersion)',
      );
    }

    // 2. Restore algorithm
    final algorithmName = json['algorithm'] as String?;
    if (algorithmName == null) {
      throw const SerializationException('Missing "algorithm" in JSON');
    }
    final algorithm = SearchAlgorithm.values.firstWhere(
      (a) => a.name == algorithmName,
      orElse: () => throw SerializationException(
        'Unknown algorithm: $algorithmName',
      ),
    );

    // 3. Restore language
    final language = json['language'] as String?;
    if (language == null) {
      throw const SerializationException('Missing "language" in JSON');
    }

    // 4. Restore schema
    final schemaJson = json['schema'];
    if (schemaJson is! Map<String, Object?>) {
      throw const SerializationException(
        'Missing or invalid "schema" in JSON',
      );
    }
    final schema = schemaFromJson(schemaJson);

    // 5. Create the database with restored config
    final db = Searchlight.create(
      schema: schema,
      algorithm: algorithm,
      language: language,
    );

    // Collect geopoint field paths for deserialization (I4 fix)
    final geoFields = schema.fieldPathsOfType(SchemaType.geopoint);

    // 6. Restore documents by re-inserting
    // I3c fix: throw when documents data is missing instead of silently
    // returning an empty database, which could mask data corruption.
    final docsJson = json['documents'];
    if (docsJson is! Map<String, Object?>) {
      throw const SerializationException('Missing documents data');
    }
    final idStoreJson = json['internalDocumentIDStore'];
    if (idStoreJson is Map<String, Object?>) {
      final internalToIdJson =
          idStoreJson['internalIdToId'] as Map<String, Object?>?;
      final nextId = idStoreJson['nextId'] as int?;
      final nextGeneratedId = idStoreJson['nextGeneratedId'] as int?;

      if (internalToIdJson != null) {
        // Re-insert documents in internal ID order to preserve IDs
        // Sort by internal ID to maintain insertion order
        final sortedEntries = docsJson.entries.toList()
          ..sort((a, b) => int.parse(a.key).compareTo(int.parse(b.key)));

        for (final entry in sortedEntries) {
          final internalIdStr = entry.key;
          final docData = entry.value;
          if (docData is! Map<String, Object?>) continue;

          final externalId = internalToIdJson[internalIdStr] as String?;
          if (externalId == null) continue;

          // Ensure the document data includes the external ID so insert()
          // uses it rather than generating a new one
          final dataWithId = <String, Object?>{
            ...docData,
            'id': externalId,
          };

          // Convert serialized {'lat': ..., 'lon': ...} maps back to
          // GeoPoint objects (I4 fix).
          for (final geoPath in geoFields) {
            _convertMapToGeoPoint(dataWithId, geoPath);
          }

          db.insert(dataWithId);
        }
      }

      // Restore counters.
      // C3 defensive check: ensure _nextInternalId is at least
      // (number of restored documents + 1) to prevent duplicate internal IDs
      // from corrupted save data.
      final minNextId = db._documents.length + 1;
      if (nextId != null) {
        db._nextInternalId = nextId < minNextId ? minNextId : nextId;
      }
      if (nextGeneratedId != null) db._nextGeneratedId = nextGeneratedId;
    }

    return db;
  }

  /// The schema defining this database's document structure.
  final Schema schema;

  /// The scoring algorithm in use.
  final SearchAlgorithm algorithm;

  /// The language for tokenization and stemming.
  final String language;

  /// The search index managing per-field trees and scoring data.
  final SearchIndex _index;

  /// The algorithm the underlying [SearchIndex] was created with.
  ///
  /// Exposed for testing/verification. Should match [algorithm].
  SearchAlgorithm get indexAlgorithm => _index.algorithm;

  /// The tokenizer for splitting text into normalized tokens.
  final Tokenizer _tokenizer;

  /// The sort index for efficient field-based sorting at search time.
  ///
  /// Populated during insert/remove, used during search when sortBy is
  /// provided. Matches Orama's `Sorter`.
  final SortIndex _sortIndex;

  // ---------------------------------------------------------------------------
  // Internal document storage
  // ---------------------------------------------------------------------------

  /// Internal document store keyed by internal DocId.
  final Map<DocId, Document> _documents = {};

  /// External string ID -> internal DocId mapping.
  final Map<String, DocId> _externalToInternal = {};

  /// Internal DocId -> external string ID mapping.
  final Map<DocId, String> _internalToExternal = {};

  /// Auto-increment counter for internal IDs.
  int _nextInternalId = 1;

  /// Auto-increment counter for generating external IDs.
  int _nextGeneratedId = 0;

  /// Total number of indexed documents.
  int get count => _documents.length;

  /// Whether the database has no documents.
  bool get isEmpty => count == 0;

  /// Internal documents keyed by raw integer ID — for facet/group computation.
  Map<int, Document> get documentsForFacets {
    return _documents.map((docId, doc) => MapEntry(docId.id, doc));
  }

  /// Field path -> SchemaType mapping — for facet/group type resolution.
  Map<String, SchemaType> get propertiesWithTypes =>
      _index.searchablePropertiesWithTypes;

  /// Internal doc ID -> external string ID mapping — for group computation.
  Map<int, String> get externalIdsMap {
    return _internalToExternal.map((docId, extId) => MapEntry(docId.id, extId));
  }

  // ---------------------------------------------------------------------------
  // Insert
  // ---------------------------------------------------------------------------

  /// Inserts a document into the database.
  ///
  /// If `data['id']` is a [String], it is used as the external document ID.
  /// If not provided, a unique string ID is auto-generated.
  ///
  /// Validates schema-defined fields against the schema before storing.
  /// Extra document properties (like `id`) are silently ignored.
  ///
  /// Returns the external [String] ID for the new document.
  ///
  /// Throws [DocumentValidationException] if the document does not conform
  /// to the schema, or if a document with the same external ID already exists.
  String insert(Map<String, Object?> data) {
    _validateDocument(data, schema.fields, '');

    // Determine external ID (Fix 1)
    final externalId = _getDocumentIndexId(data);

    // Check for duplicate (Fix 1)
    if (_externalToInternal.containsKey(externalId)) {
      throw DocumentValidationException(
        'Document already exists: $externalId',
        field: 'id',
      );
    }

    // Map external -> internal
    final internalId = DocId(_nextInternalId++);
    _externalToInternal[externalId] = internalId;
    _internalToExternal[internalId] = externalId;

    _documents[internalId] = Document(data);

    // Index the document for search
    _index.insertDocument(
      docId: internalId.id,
      data: data,
      tokenizer: _tokenizer,
      language: language,
    );

    // Populate sort index for sortable fields (string, number, boolean)
    _insertSortableValues(internalId.id, data);

    return externalId;
  }

  /// Gets the external document ID from the document data.
  ///
  /// If `doc['id']` is a [String], use it. Otherwise, auto-generate.
  /// Matches Orama's `getDocumentIndexId` behavior.
  String _getDocumentIndexId(Map<String, Object?> data) {
    final id = data['id'];
    if (id != null) {
      if (id is! String) {
        throw DocumentValidationException(
          'Document ID must be a string, got ${id.runtimeType}',
          field: 'id',
        );
      }
      return id;
    }
    return _generateUniqueId();
  }

  /// Generates a unique string ID.
  String _generateUniqueId() {
    return '${_nextGeneratedId++}';
  }

  // ---------------------------------------------------------------------------
  // Validation (Fix 2: iterate schema keys, not document keys)
  // ---------------------------------------------------------------------------

  void _validateDocument(
    Map<String, Object?> data,
    Map<String, SchemaField> schemaFields,
    String prefix,
  ) {
    for (final entry in schemaFields.entries) {
      final key = entry.key;
      final field = entry.value;
      final path = prefix.isEmpty ? key : '$prefix.$key';
      final value = data[key];

      if (value == null) continue;

      switch (field) {
        case TypedField(:final type):
          _validateFieldType(value, type, path);
        case NestedField(:final children):
          if (value is! Map<String, Object?>) {
            throw DocumentValidationException(
              "Field '$path' must be a Map<String, Object?>",
              field: path,
            );
          }
          _validateDocument(value, children, path);
      }
    }
  }

  void _validateFieldType(Object value, SchemaType type, String path) {
    final valid = switch (type) {
      SchemaType.string => value is String,
      SchemaType.number => value is num,
      SchemaType.boolean => value is bool,
      // Fix 3: enum accepts String or num
      SchemaType.enumType => value is String || value is num,
      SchemaType.geopoint => value is GeoPoint,
      SchemaType.stringArray =>
        value is List && value.every((e) => e is String),
      SchemaType.numberArray => value is List && value.every((e) => e is num),
      SchemaType.booleanArray => value is List && value.every((e) => e is bool),
      // Fix 3: enumArray accepts String or num elements
      SchemaType.enumArray =>
        value is List && value.every((e) => e is String || e is num),
    };

    if (!valid) {
      throw DocumentValidationException(
        "Field '$path' has invalid type: expected $type",
        field: path,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Sort index helpers
  // ---------------------------------------------------------------------------

  /// Sortable types: string, number, boolean (not arrays, enums, geopoints).
  static const Set<SchemaType> _sortableTypes = {
    SchemaType.string,
    SchemaType.number,
    SchemaType.boolean,
  };

  /// Inserts sortable field values into the sort index for a document.
  void _insertSortableValues(int docId, Map<String, Object?> data) {
    for (final entry in _index.searchablePropertiesWithTypes.entries) {
      final prop = entry.key;
      final type = entry.value;
      if (!_sortableTypes.contains(type)) continue;

      final value = SearchIndex.resolveValue(data, prop);
      if (value == null) continue;

      _sortIndex.insert(property: prop, docId: docId, value: value);
    }
  }

  /// Removes a document from the sort index for all sortable properties.
  void _removeSortableValues(int docId) {
    for (final entry in _index.searchablePropertiesWithTypes.entries) {
      final prop = entry.key;
      final type = entry.value;
      if (!_sortableTypes.contains(type)) continue;

      _sortIndex.remove(property: prop, docId: docId);
    }
  }

  // ---------------------------------------------------------------------------
  // Batch insert (Fix 4: abort on failure, return List<String>)
  // ---------------------------------------------------------------------------

  /// Inserts multiple documents into the database.
  ///
  /// Calls [insert] for each document. If any insert throws, the error
  /// propagates and the batch is aborted (matching Orama's behavior).
  ///
  /// Returns a [List<String>] of external IDs for all successfully inserted
  /// documents.
  ///
  /// The [batchSize] parameter is accepted for API compatibility but does not
  /// change behavior in v1. Default is 1000 (matching Orama).
  List<String> insertMultiple(
    List<Map<String, Object?>> documents, {
    int batchSize = 1000,
  }) {
    final ids = <String>[];

    for (final doc in documents) {
      final id = insert(doc);
      ids.add(id);
    }

    return ids;
  }

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  /// Returns the document with the given external [id], or `null` if not found.
  Document? getById(String id) {
    final internalId = _externalToInternal[id];
    if (internalId == null) return null;
    return _documents[internalId];
  }

  // ---------------------------------------------------------------------------
  // Remove (Fix 5: return bool / int)
  // ---------------------------------------------------------------------------

  /// Removes the document with the given external [id].
  ///
  /// Returns `true` if the document was found and removed,
  /// `false` if the [id] was not found.
  bool remove(String id) {
    final internalId = _externalToInternal[id];
    if (internalId == null) return false;

    final doc = _documents[internalId];
    if (doc != null) {
      // Un-index the document before removing
      _index.removeDocument(
        docId: internalId.id,
        data: doc.toMap(),
        tokenizer: _tokenizer,
        language: language,
      );

      // Remove from sort index
      _removeSortableValues(internalId.id);
    }

    _documents.remove(internalId);
    _externalToInternal.remove(id);
    _internalToExternal.remove(internalId);
    return true;
  }

  /// Removes all documents with the given external [ids].
  ///
  /// Returns the count of documents actually removed. Silently ignores IDs
  /// that are not found.
  int removeMultiple(List<String> ids) {
    var count = 0;
    for (final id in ids) {
      if (remove(id)) count++;
    }
    return count;
  }

  // ---------------------------------------------------------------------------
  // Update
  // ---------------------------------------------------------------------------

  /// Replaces a document by removing the old one and inserting the new one.
  ///
  /// Matching Orama's `updateSync`: removes the document with the given
  /// external [id], then inserts [newDoc] as a fresh document. The remove
  /// may silently fail if [id] doesn't exist — the insert always proceeds.
  ///
  /// Returns the new external [String] ID of the inserted document.
  ///
  /// Throws [DocumentValidationException] if [newDoc] does not conform
  /// to the schema.
  String update(String id, Map<String, Object?> newDoc) {
    remove(id);
    return insert(newDoc);
  }

  /// Replaces multiple documents by removing the old ones and inserting
  /// new ones.
  ///
  /// Matching Orama's `updateMultipleSync`:
  /// 1. Validates ALL [newDocs] against the schema first. If any fail,
  ///    throws immediately — no removes happen.
  /// 2. Calls [removeMultiple] with [ids].
  /// 3. Calls [insertMultiple] with [newDocs].
  /// 4. Returns the new external IDs.
  ///
  /// The validate-all-first pattern prevents partial state corruption.
  ///
  /// The [batchSize] parameter is accepted for API compatibility.
  List<String> updateMultiple(
    List<String> ids,
    List<Map<String, Object?>> newDocs, {
    int batchSize = 1000,
  }) {
    // Step 1: Validate ALL docs against schema FIRST (before any removes)
    for (final doc in newDocs) {
      _validateDocument(doc, schema.fields, '');
    }

    // Step 2: Remove all old documents
    removeMultiple(ids);

    // Step 3: Insert all new documents
    return insertMultiple(newDocs, batchSize: batchSize);
  }

  // ---------------------------------------------------------------------------
  // Patch (Searchlight addition)
  // ---------------------------------------------------------------------------

  /// Patches (partially updates) a document by merging [fields] into the
  /// existing document.
  ///
  /// **Note:** This is a Searchlight-specific addition. Orama does not have
  /// a patch/merge operation — only full replacement via [update].
  ///
  /// Behavior:
  /// 1. Looks up the existing document by external [id].
  /// 2. Performs a shallow merge of [fields] into the existing data.
  /// 3. Validates the merged result against the schema.
  /// 4. Removes the old document and inserts the merged document.
  ///
  /// Returns the external [String] ID.
  ///
  /// Throws [DocumentNotFoundException] if [id] does not exist.
  /// Throws [DocumentValidationException] if the merged document does not
  /// conform to the schema.
  String patch(String id, Map<String, Object?> fields) {
    final existing = getById(id);
    if (existing == null) {
      throw DocumentNotFoundException(id);
    }

    // Shallow merge: existing data + new fields (new fields overwrite)
    final merged = <String, Object?>{
      ...existing.toMap(),
      ...fields,
      'id': id,
    };

    // Validate merged result BEFORE modifying state
    _validateDocument(merged, schema.fields, '');

    // Remove old, insert merged
    remove(id);
    return insert(merged);
  }

  // ---------------------------------------------------------------------------
  // Search (matching Orama's fullTextSearch flow)
  // ---------------------------------------------------------------------------

  /// Searches the database for documents matching [term] and/or [where]
  /// filters.
  ///
  /// Matches Orama's `fullTextSearch` from `search-fulltext.ts` and
  /// `innerFullTextSearch` filter integration.
  ///
  /// Parameters:
  /// - [term]: The search query string. Empty returns all documents.
  /// - [where]: Property-level filters applied before or instead of text
  ///   search. Multiple properties are ANDed. Pass `null` for no filtering.
  /// - [properties]: Which string fields to search
  ///   (default: all string fields).
  /// - [exact]: If true, only exact word matches are returned.
  /// - [tolerance]: Levenshtein distance for fuzzy matching.
  /// - [boost]: Per-property score multipliers.
  /// - [threshold]: 1.0 = any term (OR), 0.0 = all terms (AND).
  /// - [limit]: Maximum number of hits to return per page.
  /// - [offset]: Number of results to skip (pagination).
  ///
  /// Throws [QueryException] if a requested property is not a string field
  /// or if a filter references an unknown field.
  SearchResult search({
    String term = '',
    Map<String, Filter>? where,
    List<String>? properties,
    bool exact = false,
    int tolerance = 0,
    Map<String, double>? boost,
    double threshold = 1.0,
    int limit = 10,
    int offset = 0,
    Map<String, FacetConfig>? facets,
    GroupBy? groupBy,
    SortBy? sortBy,
  }) {
    final stopwatch = Stopwatch()..start();

    // 1. Resolve properties: default = all string fields in the schema
    final stringFields = schema.fieldPathsOfType(SchemaType.string);
    List<String> propertiesToSearch;

    if (properties != null) {
      // Validate that requested properties are string type
      for (final prop in properties) {
        if (!stringFields.contains(prop)) {
          throw QueryException(
            "Property '$prop' is not a searchable string field. "
            'Available: ${stringFields.join(', ')}',
          );
        }
      }
      propertiesToSearch = properties;
    } else {
      propertiesToSearch = stringFields;
    }

    // 2. Evaluate where filters (matching Orama's innerFullTextSearch)
    final hasFilters = where != null && where.isNotEmpty;
    Set<int>? whereFiltersIDs;
    if (hasFilters) {
      whereFiltersIDs = searchByWhereClause(
        _index,
        where,
        totalDocs: _nextInternalId - 1,
        tokenizer: _tokenizer,
        language: language,
      );
    }

    // 3. Search or return all/filtered docs
    // Item 6: Orama checks `if (term || properties)` — when properties
    // is specified (even without a term), the search path is taken.
    List<TokenScore> uniqueDocsArray;

    if (term.isNotEmpty || properties != null) {
      // Call SearchIndex.search matching Orama's innerFullTextSearch
      uniqueDocsArray = _index.search(
        term: term,
        tokenizer: _tokenizer,
        propertiesToSearch: propertiesToSearch,
        relevance: const BM25Params(),
        exact: exact,
        tolerance: tolerance,
        boost: boost ?? const {},
        threshold: threshold,
        language: language,
        whereFiltersIDs: whereFiltersIDs,
      );
      // Item 19: Exact-term post-filtering. Orama checks
      // `if (params.exact && term)` after scoring, filtering to docs where
      // the original text contains the exact search terms as whole words.
      if (exact && term.isNotEmpty) {
        final searchTerms = term.trim().split(RegExp(r'\s+'));
        uniqueDocsArray = uniqueDocsArray.where((tokenScore) {
          final internalId = DocId(tokenScore.$1);
          final doc = _documents[internalId];
          if (doc == null) return false;

          for (final prop in propertiesToSearch) {
            final propValue = SearchIndex.resolveValue(doc.toMap(), prop);
            if (propValue is String) {
              final hasAllTerms = searchTerms.every((searchTerm) {
                final regex = RegExp(
                  '\\b${RegExp.escape(searchTerm)}\\b',
                );
                return regex.hasMatch(propValue);
              });
              if (hasAllTerms) return true;
            }
          }
          return false;
        }).toList();
      }
    } else {
      // No term and no properties — matching Orama: if filters, check for
      // geo-only query first, else return filtered IDs with score 0.
      if (hasFilters) {
        // Item 18: Check if this is a geo-only query for distance scoring
        final geoResults = _searchByGeoWhereClause(where);
        if (geoResults != null) {
          uniqueDocsArray = geoResults;
        } else {
          final docIds = whereFiltersIDs ?? <int>{};
          uniqueDocsArray = docIds.map<TokenScore>((id) => (id, 0.0)).toList();
        }
      } else {
        uniqueDocsArray = _documents.keys
            .map<TokenScore>((docId) => (docId.id, 0.0))
            .toList();
      }
    }

    // 4. Sort: by field (sortBy) or by score descending
    if (sortBy != null) {
      // Sort by field value using the sort index (overrides score order)
      uniqueDocsArray = _sortIndex.sortBy(
        results: uniqueDocsArray,
        property: sortBy.field,
        order: sortBy.order,
      );
    } else if (term.isEmpty) {
      // For no-term case, sort by score descending for consistency
      uniqueDocsArray.sort((a, b) => b.$2.compareTo(a.$2));
    }

    // 5. Total count before pagination
    final totalCount = uniqueDocsArray.length;

    // 6. Paginate
    final end = (offset + limit).clamp(0, uniqueDocsArray.length);
    final start = offset.clamp(0, uniqueDocsArray.length);
    final page = uniqueDocsArray.sublist(start, end);

    // 7. Fetch documents for the result page
    final hits = <SearchHit>[];
    for (final (docId, score) in page) {
      final internalId = DocId(docId);
      final externalId = _internalToExternal[internalId];
      if (externalId == null) continue;
      final doc = _documents[internalId];
      if (doc == null) continue;

      hits.add(SearchHit(id: externalId, score: score, document: doc));
    }

    // 8. Compute facets on the FULL result set (before pagination)
    Map<String, FacetResult>? facetResults;
    final shouldCalculateFacets = facets != null && facets.isNotEmpty;
    if (shouldCalculateFacets) {
      facetResults = facets_lib.getFacets(
        documents: documentsForFacets,
        results: uniqueDocsArray,
        facetsConfig: facets,
        propertiesWithTypes: propertiesWithTypes,
      );
    }

    // 9. Compute groups on the FULL result set (before pagination)
    List<GroupResult>? groupResults;
    if (groupBy != null) {
      groupResults = grouping_lib.getGroups(
        documents: documentsForFacets,
        externalIds: externalIdsMap,
        results: uniqueDocsArray,
        groupBy: groupBy,
        schemaProperties: propertiesWithTypes,
      );
    }

    stopwatch.stop();

    return SearchResult(
      hits: hits,
      count: totalCount,
      elapsed: stopwatch.elapsed,
      facets: facetResults,
      groups: groupResults,
    );
  }

  // ---------------------------------------------------------------------------
  // Item 18: Geo-only distance scoring
  // Matches Orama's searchByGeoWhereClause + isGeosearchOnlyQuery
  // ---------------------------------------------------------------------------

  /// Checks if the where clause is a geo-only query (single BKD filter)
  /// and returns distance-scored results if so.
  List<TokenScore>? _searchByGeoWhereClause(Map<String, Filter> filters) {
    if (filters.length != 1) return null;

    final param = filters.keys.first;
    final operation = filters.values.first;

    final indexTree = _index.indexes[param];
    if (indexTree == null || indexTree.type != TreeType.bkd) return null;

    if (operation is! GeoRadiusFilter && operation is! GeoPolygonFilter) {
      return null;
    }

    final bkdNode = indexTree.node as BKDTree;

    if (operation is GeoRadiusFilter) {
      final center = GeoPoint(lat: operation.lat, lon: operation.lon);
      final distanceInMeters =
          BKDTree.convertDistanceToMeters(operation.radius, operation.unit);
      final results = bkdNode.searchByRadius(
        center,
        distanceInMeters,
        inclusive: operation.inside,
        highPrecision: operation.highPrecision,
      );
      return _createGeoTokenScores(results, center, operation.highPrecision);
    }

    if (operation is GeoPolygonFilter) {
      final polygon = operation.coordinates
          .map((c) => GeoPoint(lat: c.lat, lon: c.lon))
          .toList();
      final results = bkdNode.searchByPolygon(
        polygon,
        inclusive: operation.inside,
        sort: SortOrder.asc,
        highPrecision: operation.highPrecision,
      );
      final centroid = BKDTree.calculatePolygonCentroid(polygon);
      return _createGeoTokenScores(results, centroid, operation.highPrecision);
    }

    return null;
  }

  /// Creates scored results from geo results using inverse distance scoring.
  ///
  /// Matches Orama's `createGeoTokenScores`.
  static List<TokenScore> _createGeoTokenScores(
    List<GeoSearchResult> results,
    GeoPoint centerPoint,
    bool highPrecision,
  ) {
    final distanceFn =
        highPrecision ? BKDTree.vincentyDistance : BKDTree.haversineDistance;

    final distances = <double>[];
    for (final r in results) {
      distances.add(distanceFn(centerPoint, r.point));
    }
    final maxDistance = distances.isEmpty ? 0.0 : distances.reduce(math.max);

    final scored = <TokenScore>[];
    for (var i = 0; i < results.length; i++) {
      final distance = distances[i];
      // Inverse score: closer points get higher scores
      final score = maxDistance - distance + 1;
      for (final docID in results[i].docIDs) {
        scored.add((docID, score));
      }
    }

    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored;
  }

  // ---------------------------------------------------------------------------
  // Reindex
  // ---------------------------------------------------------------------------

  /// Creates a new [Searchlight] instance with a different [algorithm],
  /// re-inserting all current documents into the new index.
  ///
  /// This matches Orama's plugin architecture: QPS and PT15 are plugins that
  /// REPLACE the index component. Reindexing creates a fresh instance with
  /// the new algorithm and copies all documents over.
  ///
  /// Returns the new [Searchlight] instance. The original instance is
  /// unmodified.
  Searchlight reindex({required SearchAlgorithm algorithm}) {
    final newDb = Searchlight.create(
      schema: schema,
      algorithm: algorithm,
      language: language,
    );

    // Re-insert all documents from the current instance
    for (final entry in _internalToExternal.entries) {
      final internalId = entry.key;
      final doc = _documents[internalId];
      if (doc == null) continue;

      // Preserve the original external ID by including it in the data
      final data = <String, Object?>{
        ...doc.toMap(),
        'id': entry.value,
      };
      newDb.insert(data);
    }

    return newDb;
  }

  /// Removes all documents from the database.
  void clear() {
    _documents.clear();
    _externalToInternal.clear();
    _internalToExternal.clear();
  }

  // ---------------------------------------------------------------------------
  // Serialization (matching Orama's save/load pattern)
  // ---------------------------------------------------------------------------

  /// Serializes the entire database state to a JSON-compatible map.
  ///
  /// Matches Orama's `save(orama)` which returns a `RawData` object
  /// containing all component states. Adds `formatVersion` for forward
  /// compatibility.
  ///
  /// **Design note (A1/A2/B6):** The index trees and sort index are NOT
  /// serialized. Instead, [Searchlight.fromJson] rebuilds them by
  /// re-inserting all documents. This is simpler and more robust than
  /// serializing each tree
  /// type, and produces functionally identical results because insertion
  /// order is preserved (documents are sorted by internal ID before
  /// re-insertion). The trade-off is O(n*m) restore time vs O(data_size)
  /// for direct tree restoration. For databases with tens of thousands of
  /// documents this may be measurably slower. A future optimization could
  /// add per-tree `toJson`/`fromJson` to enable direct restoration.
  Map<String, Object?> toJson() {
    // Collect geopoint field paths from the schema so we can convert
    // GeoPoint objects to serializable maps (I4 fix).
    final geoFields = schema.fieldPathsOfType(SchemaType.geopoint);

    // Serialize documents: internalId -> document data map
    final docsJson = <String, Object?>{};
    for (final entry in _documents.entries) {
      final docMap = Map<String, Object?>.from(entry.value.toMap());
      // Convert GeoPoint objects to JSON-serializable maps
      for (final geoPath in geoFields) {
        _convertGeoPointToMap(docMap, geoPath);
      }
      docsJson[entry.key.id.toString()] = docMap;
    }

    // Serialize ID store (matching Orama's internalDocumentIDStore.save)
    final idToInternalJson = <String, int>{};
    for (final entry in _externalToInternal.entries) {
      idToInternalJson[entry.key] = entry.value.id;
    }
    final internalToIdJson = <String, String>{};
    for (final entry in _internalToExternal.entries) {
      internalToIdJson[entry.key.id.toString()] = entry.value;
    }

    return {
      'formatVersion': currentFormatVersion,
      'algorithm': algorithm.name,
      'language': language,
      'schema': schemaToJson(schema),
      'internalDocumentIDStore': {
        'idToInternalId': idToInternalJson,
        'internalIdToId': internalToIdJson,
        'nextId': _nextInternalId,
        'nextGeneratedId': _nextGeneratedId,
      },
      'documents': docsJson,
    };
  }

  // ---------------------------------------------------------------------------
  // GeoPoint serialization helpers (I4 fix)
  // ---------------------------------------------------------------------------

  /// Converts a [GeoPoint] at [path] in [data] to a `{'lat': ..., 'lon': ...}`
  /// map for JSON/CBOR serialization.
  static void _convertGeoPointToMap(Map<String, Object?> data, String path) {
    final segments = path.split('.');
    var current = data;
    for (var i = 0; i < segments.length - 1; i++) {
      final value = current[segments[i]];
      if (value is! Map<String, Object?>) return;
      // Make a mutable copy of nested maps
      final mutable = Map<String, Object?>.from(value);
      current[segments[i]] = mutable;
      current = mutable;
    }
    final leafKey = segments.last;
    final value = current[leafKey];
    if (value is GeoPoint) {
      current[leafKey] = <String, Object?>{'lat': value.lat, 'lon': value.lon};
    }
  }

  /// Converts a `{'lat': ..., 'lon': ...}` map at [path] in [data] back to a
  /// [GeoPoint] object during deserialization.
  static void _convertMapToGeoPoint(Map<String, Object?> data, String path) {
    final segments = path.split('.');
    var current = data;
    for (var i = 0; i < segments.length - 1; i++) {
      final value = current[segments[i]];
      if (value is! Map<String, Object?>) return;
      current = value;
    }
    final leafKey = segments.last;
    final value = current[leafKey];
    if (value is Map<String, Object?> &&
        value.containsKey('lat') &&
        value.containsKey('lon')) {
      final lat = value['lat'];
      final lon = value['lon'];
      if (lat is num && lon is num) {
        current[leafKey] = GeoPoint(
          lat: lat.toDouble(),
          lon: lon.toDouble(),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // CBOR binary serialization
  // ---------------------------------------------------------------------------

  /// Serializes the entire database state to CBOR binary format.
  ///
  /// Calls [toJson] to get the JSON-compatible map, then encodes it with
  /// CBOR. This is Searchlight's binary format, analogous to Orama's
  /// msgpack encoding.
  Uint8List serialize() {
    return cborEncode(toJson());
  }

  /// Deserializes a [Searchlight] instance from CBOR bytes produced by
  /// [serialize].
  ///
  /// Decodes the CBOR bytes to a JSON-compatible map, then delegates to
  /// [Searchlight.fromJson].
  ///
  /// Throws [SerializationException] if the bytes are not valid CBOR or
  /// the decoded data is incompatible.
  static Searchlight deserialize(Uint8List bytes) {
    try {
      final map = cborDecode(bytes);
      return Searchlight.fromJson(map);
    } on FormatException catch (e) {
      throw SerializationException('Invalid CBOR data: ${e.message}');
    }
  }

  // ---------------------------------------------------------------------------
  // Persist / Restore (convenience wrappers around serialize + storage)
  // ---------------------------------------------------------------------------

  /// Persists the database to the given [storage].
  ///
  /// The [format] parameter selects the encoding: [PersistenceFormat.cbor]
  /// (default, compact binary) or [PersistenceFormat.json] (human-readable).
  /// Both formats use the same logical structure produced by [toJson].
  Future<void> persist({
    required SearchlightStorage storage,
    PersistenceFormat format = PersistenceFormat.cbor,
  }) async {
    final Uint8List bytes;
    switch (format) {
      case PersistenceFormat.cbor:
        bytes = serialize();
      case PersistenceFormat.json:
        final jsonString = jsonEncode(toJson());
        bytes = Uint8List.fromList(utf8.encode(jsonString));
    }
    await storage.save(bytes);
  }

  /// Restores a [Searchlight] instance from the given [storage].
  ///
  /// The [format] must match the format used when [persist] was called.
  /// Throws [StorageException] if no data is found.
  static Future<Searchlight> restore({
    required SearchlightStorage storage,
    PersistenceFormat format = PersistenceFormat.cbor,
  }) async {
    final bytes = await storage.load();
    if (bytes == null) {
      throw const StorageException('No data found');
    }
    switch (format) {
      case PersistenceFormat.cbor:
        return deserialize(bytes);
      case PersistenceFormat.json:
        final jsonString = utf8.decode(bytes);
        final map = jsonDecode(jsonString) as Map<String, Object?>;
        return Searchlight.fromJson(map);
    }
  }

  /// Releases resources. Flushes pending writes if applicable.
  Future<void> dispose() async {
    // Will be expanded when persistence/isolates are added
  }
}
