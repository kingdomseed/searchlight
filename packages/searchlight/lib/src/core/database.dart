// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/core/doc_id.dart';
import 'package:searchlight/src/core/document.dart';
import 'package:searchlight/src/core/exceptions.dart';
import 'package:searchlight/src/core/schema.dart';
import 'package:searchlight/src/core/types.dart';

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
  });

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
    return Searchlight._(
      schema: schema,
      algorithm: algorithm,
      language: language,
    );
  }

  /// The schema defining this database's document structure.
  final Schema schema;

  /// The scoring algorithm in use.
  final SearchAlgorithm algorithm;

  /// The language for tokenization and stemming.
  final String language;

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

  /// Removes all documents from the database.
  void clear() {
    _documents.clear();
    _externalToInternal.clear();
    _internalToExternal.clear();
  }

  /// Releases resources. Flushes pending writes if applicable.
  Future<void> dispose() async {
    // Will be expanded when persistence/isolates are added
  }
}
