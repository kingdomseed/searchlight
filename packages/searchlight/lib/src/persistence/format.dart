// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// The current serialization format version.
///
/// Increment this when the serialized structure changes in a
/// backwards-incompatible way. The `Searchlight.fromJson` factory checks
/// this value and throws `SerializationException` for future versions.
/// Past versions are accepted to allow migration (see E2 in the Phase 7
/// audit). When bumping this value, add migration logic in
/// `Searchlight.fromJson` for older versions.
const int currentFormatVersion = 1;

/// The encoding format used for `Searchlight.persist` and
/// `Searchlight.restore`.
///
/// H4 fix: allows callers to choose between compact binary (CBOR) and
/// human-readable JSON for persistence.
enum PersistenceFormat {
  /// JSON encoding. Useful for debugging, interoperability, and human
  /// readability. Produces larger output than [cbor].
  json,

  /// CBOR (Concise Binary Object Representation) encoding. The default.
  /// Produces compact binary output.
  cbor,
}
