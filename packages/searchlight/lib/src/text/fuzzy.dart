// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;

/// Result of a bounded Levenshtein computation.
final class BoundedMetric {
  /// Creates a [BoundedMetric].
  const BoundedMetric({required this.distance, required this.isBounded});

  /// The edit distance, or -1 if the distance exceeds the tolerance.
  final int distance;

  /// Whether the distance is within the tolerance bound.
  final bool isBounded;
}

/// Bounded Levenshtein: returns the edit distance if within [tolerance],
/// or distance -1 if it exceeds the tolerance.
///
/// Matches Orama's `boundedLevenshtein` implementation.
BoundedMetric boundedLevenshtein(String term, String word, int tolerance) {
  final distance = _boundedLevenshtein(term, word, tolerance);
  return BoundedMetric(distance: distance, isBounded: distance >= 0);
}

/// Internal bounded Levenshtein with early termination.
///
/// Returns the edit distance if within [tolerance], or -1 if it exceeds.
/// Matches Orama's `_boundedLevenshtein` implementation.
int _boundedLevenshtein(String term, String word, int tolerance) {
  // Handle base cases.
  if (tolerance < 0) return -1;
  if (term == word) return 0;

  final m = term.length;
  final n = word.length;

  // Special case for empty strings.
  if (m == 0) return n <= tolerance ? n : -1;
  if (n == 0) return m <= tolerance ? m : -1;

  final diff = (m - n).abs();

  // Special case for prefixes.
  // If the searching word starts with the indexed word, return early.
  if (term.startsWith(word)) {
    return diff <= tolerance ? diff : -1;
  }
  // If the indexed word starts with the searching word, return early.
  if (word.startsWith(term)) {
    return 0;
  }

  // If the length difference is greater than the tolerance, return early.
  if (diff > tolerance) return -1;

  // Initialize the matrix.
  final matrix = List<List<int>>.generate(m + 1, (i) {
    return List<int>.generate(n + 1, (j) {
      if (j == 0) return i;
      if (i == 0) return j;
      return 0;
    });
  });

  // Fill the matrix.
  for (var i = 1; i <= m; i++) {
    var rowMin = double.maxFinite.toInt();
    for (var j = 1; j <= n; j++) {
      if (term[i - 1] == word[j - 1]) {
        matrix[i][j] = matrix[i - 1][j - 1];
      } else {
        matrix[i][j] = _min3(
          matrix[i - 1][j] + 1, // deletion
          matrix[i][j - 1] + 1, // insertion
          matrix[i - 1][j - 1] + 1, // substitution
        );
      }
      rowMin = math.min(rowMin, matrix[i][j]);
    }

    // Early termination if all values in this row exceed tolerance.
    if (rowMin > tolerance) {
      return -1;
    }
  }

  return matrix[m][n] <= tolerance ? matrix[m][n] : -1;
}

/// Returns the edit distance between two strings.
///
/// Uses single-row Wagner-Fischer with space optimization.
/// Matches Orama's `levenshtein` implementation.
int levenshtein(String a, String b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  // Swap so that shorter string is used as columns (optimization).
  var short = a;
  var long = b;
  if (a.length > b.length) {
    short = b;
    long = a;
  }

  final row = List<int>.generate(short.length + 1, (i) => i);
  var val = 0;

  for (var i = 1; i <= long.length; i++) {
    var prev = i;

    for (var j = 1; j <= short.length; j++) {
      if (long[i - 1] == short[j - 1]) {
        val = row[j - 1];
      } else {
        val = _min3(row[j - 1] + 1, prev + 1, row[j] + 1);
      }

      row[j - 1] = prev;
      prev = val;
    }
    row[short.length] = prev;
  }

  return row[short.length];
}

int _min3(int x, int y, int z) {
  if (x < y) return x < z ? x : z;
  return y < z ? y : z;
}
