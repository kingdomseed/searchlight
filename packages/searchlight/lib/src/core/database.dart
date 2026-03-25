// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/core/doc_id.dart';
import 'package:searchlight/src/core/document.dart';
import 'package:searchlight/src/core/schema.dart';

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
  /// Returns the auto-generated [DocId] for the new document.
  DocId insert(Map<String, Object?> data) {
    final id = DocId(_nextId++);
    _documents[id] = Document(data);
    return id;
  }

  /// Releases resources. Flushes pending writes if applicable.
  Future<void> dispose() async {
    // Will be expanded when persistence/isolates are added
  }
}
