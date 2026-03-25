// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/core/exceptions.dart';
import 'package:searchlight/src/core/schema.dart';

/// Serializes a [Schema] to a JSON-compatible map.
///
/// Each [TypedField] becomes `{'type': 'string'}` etc.
/// Each [NestedField] becomes `{'nested': { ... children ... }}`.
Map<String, Object?> schemaToJson(Schema schema) {
  return _fieldsToJson(schema.fields);
}

Map<String, Object?> _fieldsToJson(Map<String, SchemaField> fields) {
  final result = <String, Object?>{};
  for (final entry in fields.entries) {
    switch (entry.value) {
      case TypedField(:final type):
        result[entry.key] = {'type': type.name};
      case NestedField(:final children):
        result[entry.key] = {'nested': _fieldsToJson(children)};
    }
  }
  return result;
}

/// Deserializes a [Schema] from a JSON-compatible map produced by
/// [schemaToJson].
///
/// Throws [SerializationException] if the JSON structure is invalid.
Schema schemaFromJson(Map<String, Object?> json) {
  final fields = _fieldsFromJson(json);
  return Schema(fields);
}

Map<String, SchemaField> _fieldsFromJson(Map<String, Object?> json) {
  final fields = <String, SchemaField>{};
  for (final entry in json.entries) {
    final value = entry.value;
    if (value is! Map<String, Object?>) {
      throw SerializationException(
        'Invalid schema field "${entry.key}": expected Map',
      );
    }
    if (value.containsKey('nested')) {
      final nested = value['nested'];
      if (nested is! Map<String, Object?>) {
        throw SerializationException(
          'Invalid nested field "${entry.key}": expected Map',
        );
      }
      fields[entry.key] = NestedField(_fieldsFromJson(nested));
    } else if (value.containsKey('type')) {
      final typeValue = value['type'];
      if (typeValue is! String) {
        throw SerializationException(
          'Invalid type value for field "${entry.key}": expected String',
        );
      }
      final typeName = typeValue;
      final type = _schemaTypeFromName(typeName);
      if (type == null) {
        throw SerializationException(
          'Unknown schema type "$typeName" for field "${entry.key}"',
        );
      }
      fields[entry.key] = TypedField(type);
    } else {
      throw SerializationException(
        'Schema field "${entry.key}" must have "type" or "nested" key',
      );
    }
  }
  return fields;
}

SchemaType? _schemaTypeFromName(String name) {
  for (final type in SchemaType.values) {
    if (type.name == name) return type;
  }
  return null;
}
