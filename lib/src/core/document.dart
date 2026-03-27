// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/core/types.dart';

/// A type-safe document wrapper with typed field accessors.
///
/// Wraps a raw `Map<String, Object?>` and provides strongly-typed methods
/// for accessing field values. Throws [TypeError] on type mismatches and
/// [NoSuchMethodError] or [TypeError] on missing keys (via the `!` null
/// assertion).
final class Document {
  /// Creates a [Document] wrapping the given [_data] map.
  const Document(this._data);

  final Map<String, Object?> _data;

  // ---------------------------------------------------------------------------
  // Typed accessors (throw on type mismatch or missing key)
  // ---------------------------------------------------------------------------

  /// Returns the [String] value for [field].
  ///
  /// Throws if the field is missing or not a [String].
  String getString(String field) => _data[field]! as String;

  /// Returns the [num] value for [field].
  ///
  /// Throws if the field is missing or not a [num].
  num getNumber(String field) => _data[field]! as num;

  /// Returns the [bool] value for [field].
  ///
  /// Throws if the field is missing or not a [bool].
  bool getBool(String field) => _data[field]! as bool;

  /// Returns the value for [field] as a `List<String>`.
  ///
  /// Throws if the field is missing or not a [List].
  List<String> getStringList(String field) =>
      (_data[field]! as List<Object?>).cast<String>();

  /// Returns the value for [field] as a `List<num>`.
  ///
  /// Throws if the field is missing or not a [List].
  List<num> getNumberList(String field) =>
      (_data[field]! as List<Object?>).cast<num>();

  /// Returns the [GeoPoint] value for [field].
  ///
  /// Throws if the field is missing or not a [GeoPoint].
  GeoPoint getGeoPoint(String field) => _data[field]! as GeoPoint;

  /// Returns a nested [Document] for [field].
  ///
  /// The value must be a `Map<String, Object?>`.
  /// Throws if the field is missing or not a [Map].
  Document getNested(String field) =>
      Document(_data[field]! as Map<String, Object?>);

  // ---------------------------------------------------------------------------
  // Nullable variants
  // ---------------------------------------------------------------------------

  /// Returns the [String] value for [field], or `null` if the field is missing.
  String? tryGetString(String field) => _data[field] as String?;

  /// Returns the [num] value for [field], or `null` if the field is missing.
  num? tryGetNumber(String field) => _data[field] as num?;

  /// Returns the [bool] value for [field], or `null` if the field is missing.
  bool? tryGetBool(String field) => _data[field] as bool?;

  // ---------------------------------------------------------------------------
  // Raw map access
  // ---------------------------------------------------------------------------

  /// Returns a shallowly unmodifiable copy of the underlying data map.
  ///
  /// Nested maps and lists are shared with the wrapped document data and may
  /// still be mutated through their own references.
  Map<String, Object?> toMap() => Map<String, Object?>.unmodifiable(_data);
}
