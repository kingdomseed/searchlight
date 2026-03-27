// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Interface for extracting searchable content from any source format.
///
/// Implementations convert source data (PDF bytes, HTML, CSV, etc.)
/// into record maps that can be indexed by Searchlight.
///
/// **Note:** This is part of Searchlight's adapter pattern. Orama does not
/// have a built-in document adapter system -- this is a Searchlight addition.
// ignore: one_member_abstracts
abstract class DocumentAdapter<T> {
  /// Convert a source object into one or more indexable documents.
  ///
  /// Returns a list because one source (e.g., a PDF) may produce
  /// multiple documents (one per page/section).
  List<Map<String, Object?>> toDocuments(T source);
}
