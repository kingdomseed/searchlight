// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// The current serialization format version.
///
/// Increment this when the serialized structure changes in a
/// backwards-incompatible way. The `Searchlight.fromJson` factory checks
/// this value and throws `SerializationException` for unknown versions.
const int currentFormatVersion = 1;
