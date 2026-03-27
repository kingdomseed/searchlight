// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;

/// Parameters for the BM25 scoring algorithm.
///
/// Matches Orama's `BM25Params` from `types.ts`.
final class BM25Params {
  /// Creates [BM25Params] with the given values.
  ///
  /// Defaults match Orama: k=1.2, b=0.75, d=0.5.
  const BM25Params({this.k = 1.2, this.b = 0.75, this.d = 0.5});

  /// Term frequency saturation parameter.
  final double k;

  /// Field length normalization parameter.
  final double b;

  /// Term frequency delta (minimum score contribution).
  final double d;
}

/// Computes a BM25 relevance score for a term in a document.
///
/// Matches Orama's `BM25` function from `algorithms.ts`.
///
/// Parameters:
/// - [tf]: Term frequency (occurrences / total tokens in field).
/// - [matchingCount]: Number of documents containing the term.
/// - [docsCount]: Total number of documents in the index.
/// - [fieldLength]: Number of tokens in this document's field.
/// - [averageFieldLength]: Average number of tokens across all documents.
/// - [params]: BM25 tuning parameters (k, b, d).
double bm25({
  required double tf,
  required int matchingCount,
  required int docsCount,
  required int fieldLength,
  required double averageFieldLength,
  required BM25Params params,
}) {
  final idf = math.log(
    1 + (docsCount - matchingCount + 0.5) / (matchingCount + 0.5),
  );
  return (idf * (params.d + tf * (params.k + 1))) /
      (tf +
          params.k *
              (1 - params.b + (params.b * fieldLength) / averageFieldLength));
}
