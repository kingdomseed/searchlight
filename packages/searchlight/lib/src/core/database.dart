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

  final Map<DocId, Document> _documents = {};
  int _nextId = 0;

  /// Total number of indexed documents.
  int get count => _documents.length;

  /// Whether the database has no documents.
  bool get isEmpty => count == 0;

  /// Inserts a document into the database.
  ///
  /// Validates the document against the schema before storing.
  /// Returns the auto-generated [DocId] for the new document.
  ///
  /// Throws [DocumentValidationException] if the document does not conform
  /// to the schema.
  DocId insert(Map<String, Object?> data) {
    _validateDocument(data, schema.fields, '');
    final id = DocId(_nextId++);
    _documents[id] = Document(data);
    return id;
  }

  void _validateDocument(
    Map<String, Object?> data,
    Map<String, SchemaField> schemaFields,
    String prefix,
  ) {
    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;
      final path = prefix.isEmpty ? key : '$prefix.$key';
      final field = schemaFields[key];

      if (field == null) {
        throw DocumentValidationException(
          "Field '$path' is not defined in the schema",
          field: path,
        );
      }

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
      SchemaType.enumType => value is String,
      SchemaType.geopoint => value is GeoPoint,
      SchemaType.stringArray =>
        value is List && value.every((e) => e is String),
      SchemaType.numberArray => value is List && value.every((e) => e is num),
      SchemaType.booleanArray => value is List && value.every((e) => e is bool),
      SchemaType.enumArray => value is List && value.every((e) => e is String),
    };

    if (!valid) {
      throw DocumentValidationException(
        "Field '$path' has invalid type: expected $type",
        field: path,
      );
    }
  }

  /// Returns the document with the given [id], or `null` if not found.
  Document? getById(DocId id) => _documents[id];

  /// Releases resources. Flushes pending writes if applicable.
  Future<void> dispose() async {
    // Will be expanded when persistence/isolates are added
  }
}
