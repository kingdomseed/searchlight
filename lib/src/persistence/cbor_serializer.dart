// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';

import 'package:cbor/simple.dart' as cbor_simple;

/// Encodes a JSON-compatible map to CBOR bytes.
///
/// Uses the `cbor` package's simple codec to convert Dart maps, lists,
/// strings, numbers, booleans, and nulls into CBOR binary format.
/// This is Searchlight's binary serialization format, analogous to
/// Orama's msgpack encoding.
Uint8List cborEncode(Map<String, Object?> map) {
  final bytes = cbor_simple.cbor.encode(map);
  return Uint8List.fromList(bytes);
}

/// Decodes CBOR bytes to a JSON-compatible map.
///
/// Throws [FormatException] if the bytes are not valid CBOR.
/// The caller should catch this and wrap in a `SerializationException`.
Map<String, Object?> cborDecode(Uint8List bytes) {
  final decoded = cbor_simple.cbor.decode(bytes);
  return _deepCastMap(decoded);
}

/// Recursively casts a decoded CBOR map to `Map<String, Object?>`.
///
/// The cbor package decodes maps as `Map<dynamic, dynamic>`. This utility
/// converts them to the `Map<String, Object?>` type expected by
/// `Searchlight.fromJson`.
Map<String, Object?> _deepCastMap(Object? value) {
  if (value is! Map) {
    throw const FormatException('Expected a Map at CBOR root level');
  }
  return _castMap(value);
}

Map<String, Object?> _castMap(Map<dynamic, dynamic> map) {
  final result = <String, Object?>{};
  for (final entry in map.entries) {
    final key = entry.key.toString();
    result[key] = _castValue(entry.value);
  }
  return result;
}

Object? _castValue(Object? value) {
  if (value is Map) {
    return _castMap(value);
  }
  if (value is List) {
    return value.map(_castValue).toList();
  }
  return value;
}
