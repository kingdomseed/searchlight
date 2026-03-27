// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;

import 'package:searchlight/src/text/tokenizer.dart';
import 'package:searchlight/src/trees/radix_tree.dart';

/// QPS (Quantum Proximity Scoring) statistics for a single property.
///
/// Stores the packed token quantum descriptors and total token counts
/// per document. Matches Orama's `QPSIndex.stats[prop]` from
/// `plugin-qps/src/algorithm.ts`.
final class QPSStats {
  /// Creates empty QPS statistics.
  QPSStats();

  /// Deserializes [QPSStats] from a JSON-compatible map.
  factory QPSStats.fromJson(Map<String, Object?> json) {
    final stats = QPSStats();

    final rawTokenQuantums = json['tokenQuantums'];
    if (rawTokenQuantums is Map) {
      for (final entry in rawTokenQuantums.entries) {
        final docId = int.parse(entry.key as String);
        final rawTokens = entry.value;
        if (rawTokens is! Map) continue;

        stats.tokenQuantums[docId] = {
          for (final tokenEntry in rawTokens.entries)
            tokenEntry.key as String: tokenEntry.value as int,
        };
      }
    }

    final rawTokensLength = json['tokensLength'];
    if (rawTokensLength is Map) {
      for (final entry in rawTokensLength.entries) {
        stats.tokensLength[int.parse(entry.key as String)] = entry.value as int;
      }
    }

    return stats;
  }

  /// Per-document token quantum descriptors.
  ///
  /// `tokenQuantums[docId][token]` stores a packed integer: upper bits =
  /// occurrence count, lower 20 bits = sentence bitmask.
  final Map<int, Map<String, int>> tokenQuantums = {};

  /// Per-document total token count.
  final Map<int, int> tokensLength = {};

  /// Serializes the QPS statistics to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return {
      'tokenQuantums': {
        for (final entry in tokenQuantums.entries)
          entry.key.toString(): Map<String, int>.from(entry.value),
      },
      'tokensLength': {
        for (final entry in tokensLength.entries)
          entry.key.toString(): entry.value,
      },
    };
  }
}

/// 20-bit mask: lower 20 bits all set.
///
/// Matches Orama's `BIT_MASK_20` from `plugin-qps/src/algorithm.ts`.
const int bitMask20Value = 0xFFFFF;

/// Packs an occurrence count and sentence bitmask into a single integer.
///
/// The upper bits (above bit 20) store the occurrence count, and the lower
/// 20 bits store a bitmask indicating which sentence (quantum) the token
/// appeared in.
///
/// Matches Orama's `calculateTokenQuantum` from `plugin-qps/src/algorithm.ts`.
int calculateTokenQuantum(int prevValue, int bit) {
  final currentCount = countFromPacked(prevValue);
  final currentSentenceMask = bitmask20(prevValue);
  final newSentenceMask = currentSentenceMask | (1 << bit);
  return ((currentCount + 1) << 20) | newSentenceMask;
}

/// Extracts the lower 20 bits (sentence bitmask) from a packed value.
///
/// Matches Orama's `bitmask_20` from `plugin-qps/src/algorithm.ts`.
int bitmask20(int n) => n & bitMask20Value;

/// Extracts the upper bits (occurrence count) from a packed value.
///
/// Matches Orama's `count` from `plugin-qps/src/algorithm.ts`.
int countFromPacked(int n) => n >> 20;

/// Counts the number of set bits (popcount) in [n].
///
/// Matches Orama's `numberOfOnes` from `plugin-qps/src/algorithm.ts`.
int numberOfOnes(int n) {
  var count = 0;
  var value = n;
  while (value != 0) {
    if (value & 1 == 1) {
      count++;
    }
    value >>= 1;
  }
  return count;
}

/// Indexes a string value using QPS sentence-based quantum scoring.
///
/// Splits [value] into sentences (on `.`, `?`, `!`), tokenizes each sentence,
/// and records which quantum (sentence index) each token appeared in via
/// bit packing. Each token is also inserted into the [radixTree].
///
/// Matches Orama's `insertString` from `plugin-qps/src/algorithm.ts`.
void qpsInsertString({
  required String value,
  required RadixTree radixTree,
  required QPSStats stats,
  required String prop,
  required int internalId,
  required Tokenizer tokenizer,
  String? language,
}) {
  final sentences = value.split(RegExp('[.?!]'));

  var quantumIndex = 0;
  var tokenNumber = 0;

  for (final sentence in sentences) {
    final tokens = tokenizer.tokenize(sentence, property: prop);

    for (final token in tokens) {
      tokenNumber++;

      // The packed descriptor reserves only the lower 20 bits for quantums.
      // Saturate overflow into the final representable bucket instead of
      // shifting into the count region and dropping the proximity signal.
      final tokenBitIndex = math.min(quantumIndex, 19);

      stats.tokenQuantums[internalId]![token] = calculateTokenQuantum(
        stats.tokenQuantums[internalId]![token] ?? 0,
        tokenBitIndex,
      );

      radixTree.insert(token, internalId);
    }

    // Don't increment the quantum index if the sentence is too short
    if (tokens.length > 1) {
      quantumIndex++;
    }
  }

  stats.tokensLength[internalId] = tokenNumber;
}

/// Searches for tokens in the radix tree and scores matching documents
/// using QPS (Quantum Proximity Scoring).
///
/// For each matching document:
/// - Base score = `((occurrence^2 / numberOfQuantums) + exactMatchBonus) * boost`
/// - Proximity bonus: when a doc already has a score from a previous token,
///   adds `numberOfOnes(existingBitMask & newBitMask) * 2` for tokens
///   appearing in the same sentence.
///
/// [resultMap] maps docId -> (accumulatedScore, combinedBitMask).
///
/// Matches Orama's `searchString` from `plugin-qps/src/algorithm.ts`.
void qpsSearchString({
  required List<String> tokens,
  required RadixNode radixNode,
  required bool exact,
  required int tolerance,
  required QPSStats stats,
  required double boostPerProp,
  required Map<int, (double, int)> resultMap,
  Set<int>? whereFiltersIDs,
}) {
  var foundWords = <String, List<int>>{};

  for (var i = 0; i < tokens.length; i++) {
    final term = tokens[i];
    final results = radixNode.find(
      term: term,
      exact: exact,
      tolerance: tolerance > 0 ? tolerance : null,
    );
    foundWords = {...foundWords, ...results};
  }

  final foundKeys = foundWords.keys.toList();
  for (var i = 0; i < foundKeys.length; i++) {
    final key = foundKeys[i];
    final matchedDocs = foundWords[key]!;
    final isExactMatch = tokens.contains(key);

    for (var j = 0; j < matchedDocs.length; j++) {
      final docId = matchedDocs[j];

      if (whereFiltersIDs != null && !whereFiltersIDs.contains(docId)) {
        continue;
      }

      final numberOfQuantums = stats.tokensLength[docId]!;
      final tokenQuantumDescriptor = stats.tokenQuantums[docId]![key]!;

      final occurrence = countFromPacked(tokenQuantumDescriptor);
      final bitMask = bitmask20(tokenQuantumDescriptor);
      final score = ((occurrence * occurrence) / numberOfQuantums +
              (isExactMatch ? 1 : 0)) *
          boostPerProp;

      if (!resultMap.containsKey(docId)) {
        resultMap[docId] = (score, bitMask);
        continue;
      }

      final current = resultMap[docId]!;
      final totalScore =
          current.$1 + numberOfOnes(current.$2 & bitMask) * 2 + score;
      resultMap[docId] = (totalScore, current.$2 | bitMask);
    }
  }
}

/// Removes a document's string data from QPS stats and the radix tree.
///
/// Tokenizes [value] to find all tokens, removes the document from each
/// token's entry in the radix tree, then clears the document's
/// tokenQuantums and tokensLength entries.
///
/// Matches Orama's `removeString` from `plugin-qps/src/algorithm.ts`.
void qpsRemoveString({
  required String value,
  required RadixTree radixTree,
  required QPSStats stats,
  required String prop,
  required int internalId,
  required Tokenizer tokenizer,
  String? language,
}) {
  final tokens = tokenizer.tokenize(value, property: prop);

  for (final token in tokens) {
    radixTree.removeDocumentByWord(token, internalId);
  }

  stats.tokensLength.remove(internalId);
  stats.tokenQuantums.remove(internalId);
}
