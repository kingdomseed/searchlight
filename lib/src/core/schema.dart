// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/core/exceptions.dart';

/// Supported field types in a Searchlight schema.
enum SchemaType {
  /// A text field indexed for full-text search.
  string,

  /// A numeric field (int or double).
  number,

  /// A boolean field.
  boolean,

  /// An enum field (string with a fixed set of allowed values).
  enumType,

  /// A geographic point (latitude/longitude).
  geopoint,

  /// An array of strings.
  stringArray,

  /// An array of numbers.
  numberArray,

  /// An array of booleans.
  booleanArray,

  /// An array of enum values.
  enumArray,
}

/// A field definition in a schema.
///
/// This is a sealed class with two subtypes:
/// - [TypedField]: a leaf field with a concrete [SchemaType].
/// - [NestedField]: a structural field containing child [SchemaField]s.
sealed class SchemaField {
  /// Creates a [SchemaField].
  const SchemaField();
}

/// A leaf field with a concrete type.
final class TypedField extends SchemaField {
  /// Creates a [TypedField] with the given [type].
  const TypedField(this.type);

  /// The schema type of this field.
  final SchemaType type;
}

/// A nested object containing child fields.
final class NestedField extends SchemaField {
  /// Creates a [NestedField] with the given [children].
  const NestedField(this.children);

  /// The child fields of this nested object.
  final Map<String, SchemaField> children;
}

/// A validated schema definition for a Searchlight database.
///
/// The schema defines the structure and types of all fields in documents
/// stored in the database. It is validated on construction: empty schemas
/// and empty nested fields are rejected.
final class Schema {
  /// Creates a [Schema] with the given [fields].
  ///
  /// Throws [SchemaValidationException] if:
  /// - [fields] is empty.
  /// - Any [NestedField] has an empty [NestedField.children] map.
  Schema(this.fields) {
    if (fields.isEmpty) {
      throw const SchemaValidationException(
        'Schema must have at least one field',
      );
    }
    _validateFields(fields, '');
  }

  /// The top-level field definitions.
  final Map<String, SchemaField> fields;

  /// Returns all leaf field paths in dot notation.
  ///
  /// For example, a schema with `title` (string) and `meta.rating` (number)
  /// returns `['title', 'meta.rating']`.
  List<String> get fieldPaths => _collectPaths(fields, '');

  /// Returns the [SchemaType] for the given dot-separated [path].
  ///
  /// Throws [SchemaValidationException] if:
  /// - The path does not exist in the schema.
  /// - The path points to a [NestedField] (not a leaf).
  /// - The path attempts to traverse through a [TypedField].
  SchemaType typeAt(String path) {
    final segments = path.split('.');
    var current = fields;

    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final field = current[segment];

      if (field == null) {
        throw SchemaValidationException(
          "Field '$path' not found in schema",
        );
      }

      if (i == segments.length - 1) {
        // Last segment: must be a TypedField.
        return switch (field) {
          TypedField(:final type) => type,
          NestedField() => throw SchemaValidationException(
              "Field '$path' is a nested object, not a leaf field",
            ),
        };
      }

      // Intermediate segment: must be a NestedField.
      switch (field) {
        case NestedField(:final children):
          current = children;
        case TypedField():
          throw SchemaValidationException(
            "Field '${segments.sublist(0, i + 1).join('.')}' is not a nested "
            "object; cannot traverse into '$path'",
          );
      }
    }

    // Should be unreachable, but satisfies the analyzer.
    throw SchemaValidationException("Field '$path' not found in schema");
  }

  /// Returns all leaf field paths that have the given [type].
  ///
  /// This is a convenience for finding, e.g., all string fields to use as
  /// default search properties.
  List<String> fieldPathsOfType(SchemaType type) {
    return fieldPaths
        .where((path) => typeAt(path) == type)
        .toList(growable: false);
  }

  /// Recursively validates that no [NestedField] has empty children.
  void _validateFields(Map<String, SchemaField> fieldMap, String prefix) {
    for (final entry in fieldMap.entries) {
      final path = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
      switch (entry.value) {
        case TypedField():
          break;
        case NestedField(:final children):
          if (children.isEmpty) {
            throw SchemaValidationException(
              "Nested field '$path' must have at least one child field",
            );
          }
          _validateFields(children, path);
      }
    }
  }

  /// Recursively collects all leaf field paths in dot notation.
  static List<String> _collectPaths(
    Map<String, SchemaField> fieldMap,
    String prefix,
  ) {
    final paths = <String>[];
    for (final entry in fieldMap.entries) {
      final path = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
      switch (entry.value) {
        case TypedField():
          paths.add(path);
        case NestedField(:final children):
          paths.addAll(_collectPaths(children, path));
      }
    }
    return paths;
  }
}
