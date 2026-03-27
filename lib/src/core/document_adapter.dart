// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

/// Interface for extracting searchable content from any source format.
///
/// Implementations convert source data (PDF bytes, HTML, CSV, etc.)
/// into record maps that can be indexed by Searchlight.
///
/// This is intentionally not exported from `package:searchlight/searchlight.dart`
/// because Orama has no equivalent core API surface. Extension packages can
/// define their own extraction contracts or opt into this internal interface.
@internal
// This remains an interface on purpose so extension packages can standardize
// their own extraction contracts without making the core barrel export it.
// ignore: one_member_abstracts
abstract class DocumentAdapter<T> {
  /// Convert a source object into one or more indexable documents.
  ///
  /// Returns a list because one source (e.g., a PDF) may produce
  /// multiple documents (one per page/section).
  List<Map<String, Object?>> toDocuments(T source);
}
