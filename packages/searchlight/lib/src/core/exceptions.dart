// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/core/doc_id.dart';

/// Base exception for all Searchlight errors.
sealed class SearchlightException implements Exception {
  /// Creates a [SearchlightException] with the given [message].
  const SearchlightException(this.message);

  /// Human-readable error message.
  final String message;

  @override
  String toString() => 'SearchlightException: $message';
}

/// Schema definition error (invalid types, invalid nesting).
final class SchemaValidationException extends SearchlightException {
  /// Creates a [SchemaValidationException] with the given [message].
  const SchemaValidationException(super.message);
}

/// Document does not match schema.
final class DocumentValidationException extends SearchlightException {
  /// Creates a [DocumentValidationException] with the given [message]
  /// and optional [field].
  const DocumentValidationException(super.message, {this.field});

  /// The field that failed validation, if applicable.
  final String? field;
}

/// Document not found for update/patch/remove.
final class DocumentNotFoundException extends SearchlightException {
  /// Creates a [DocumentNotFoundException] for the given [id].
  DocumentNotFoundException(this.id) : super('Document not found: ${id.id}');

  /// The ID that was not found.
  final DocId id;
}

/// Serialization or deserialization failure.
final class SerializationException extends SearchlightException {
  /// Creates a [SerializationException] with the given [message].
  const SerializationException(super.message);
}

/// Storage operation failure (file I/O, permission errors).
final class StorageException extends SearchlightException {
  /// Creates a [StorageException] with the given [message] and optional
  /// [cause].
  const StorageException(super.message, {this.cause});

  /// The underlying cause, if available.
  final Object? cause;
}

/// Search query error (invalid field, incompatible filter).
final class QueryException extends SearchlightException {
  /// Creates a [QueryException] with the given [message].
  const QueryException(super.message);
}
