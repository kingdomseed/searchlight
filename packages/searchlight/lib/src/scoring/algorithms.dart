// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/indexing/index_manager.dart';

/// Merges and prioritizes token scores from multiple properties/tokens.
///
/// Matches Orama's `prioritizeTokenScores` from `algorithms.ts:5-114`.
///
/// - [arrays]: Lists of (docId, score) pairs from different search contexts.
/// - [boost]: Global boost multiplier applied to all scores.
/// - [threshold]: 0 = exact (all keywords), 1 = fuzzy (any keyword),
///   between = percentage of required keywords.
/// - [keywordsCount]: Total number of search keywords.
///
/// Multi-match multiplier: when a doc appears in multiple arrays, its
/// accumulated score is multiplied by 1.5 before adding the new score.
List<TokenScore> prioritizeTokenScores(
  List<List<TokenScore>> arrays, {
  required double boost,
  required int keywordsCount,
  double threshold = 0,
}) {
  if (boost == 0) {
    throw ArgumentError('Boost value must not be zero');
  }

  // Map: docId -> (accumulatedScore, matchCount)
  final tokenScoresMap = <int, (double score, int count)>{};

  for (final arr in arrays) {
    for (final (token, score) in arr) {
      final boostScore = score * boost;
      final existing = tokenScoresMap[token];

      if (existing != null) {
        // Multi-match: multiply existing score by 1.5 and add new score
        tokenScoresMap[token] = (
          existing.$1 * 1.5 + boostScore,
          existing.$2 + 1,
        );
      } else {
        tokenScoresMap[token] = (boostScore, 1);
      }
    }
  }

  final tokenScores = tokenScoresMap.entries
      .map<TokenScore>((e) => (e.key, e.value.$1))
      .toList()
    ..sort((a, b) => b.$2.compareTo(a.$2));

  // threshold = 1: return all results (fuzzy match)
  if (threshold == 1) return tokenScores;

  // threshold = 0, single keyword: return all matches
  if (threshold == 0 && keywordsCount == 1) return tokenScores;

  // Build keyword count tracking
  final allResults = tokenScores.length;
  final tokenScoreWithKeywordsCount = tokenScoresMap.entries
      .map((e) => (e.key, e.value.$1, e.value.$2))
      .toList()
    ..sort((a, b) {
      // Sort by match count descending, then score descending
      if (a.$3 != b.$3) return b.$3.compareTo(a.$3);
      return b.$2.compareTo(a.$2);
    });

  // Find the last result with all keywords
  int? lastTokenWithAllKeywords;
  for (var i = 0; i < allResults; i++) {
    if (tokenScoreWithKeywordsCount[i].$3 == keywordsCount) {
      lastTokenWithAllKeywords = i;
    } else {
      break;
    }
  }

  // If no results had all the keywords
  if (lastTokenWithAllKeywords == null) {
    if (threshold == 0) return [];
    lastTokenWithAllKeywords = 0;
  }

  final resultsWithIdAndScore =
      tokenScoreWithKeywordsCount.map<TokenScore>((e) => (e.$1, e.$2)).toList();

  // threshold = 0: exact match only
  if (threshold == 0) {
    return resultsWithIdAndScore.sublist(0, lastTokenWithAllKeywords + 1);
  }

  // Partial threshold: full matches + percentage of remaining
  final thresholdLength = lastTokenWithAllKeywords +
      (threshold * 100 * (allResults - lastTokenWithAllKeywords) / 100).ceil();

  return resultsWithIdAndScore.sublist(
    0,
    thresholdLength < allResults ? thresholdLength : allResults,
  );
}
