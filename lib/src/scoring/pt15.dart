// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/indexing/index_manager.dart' show TokenScore;
import 'package:searchlight/src/text/tokenizer.dart';

/// Maximum number of position buckets in the PT15 algorithm.
///
/// Matches Orama's `MAX_POSITION` constant from `plugin-pt15/algorithm.ts`.
const maxPosition = 15;

/// A single position bucket mapping token prefixes to lists of document IDs.
///
/// Matches Orama's `PositionStorage` type: `Record<string, number[]>`.
typedef PositionStorage = Map<String, List<int>>;

/// An array of 15 [PositionStorage] buckets.
///
/// Matches Orama's `PositionsStorage` type from `plugin-pt15/algorithm.ts`.
typedef PositionsStorage = List<PositionStorage>;

/// Creates an empty [PositionsStorage] with 15 empty buckets.
PositionsStorage createPositionsStorage() {
  return List.generate(maxPosition, (_) => <String, List<int>>{});
}

/// Calculates which position bucket a token at index [n] occupies within a
/// document of [totalLength] tokens.
///
/// For short documents (< 15 tokens), returns [n] directly.
/// For longer documents, scales to fit within 0..14 range.
///
/// Matches Orama's `get_position` from `plugin-pt15/algorithm.ts:157-163`.
int getPosition(int n, int totalLength) {
  if (totalLength < maxPosition) {
    return n;
  }
  return (n * maxPosition) ~/ totalLength;
}

/// Inserts a string value into positional storage, storing all prefixes of
/// each token in the appropriate position bucket.
///
/// Matches Orama's `insertString` from `plugin-pt15/algorithm.ts:132-155`.
void insertString({
  required String value,
  required PositionsStorage positionsStorage,
  required String prop,
  required int internalId,
  required String? language,
  required Tokenizer tokenizer,
}) {
  final tokens = tokenizer.tokenize(value, property: prop);
  final tokensLength = tokens.length;

  for (var i = 0; i < tokensLength; i++) {
    final token = tokens[i];
    final position = maxPosition - getPosition(i, tokensLength) - 1;
    final positionStorage = positionsStorage[position];

    final tokenLength = token.length;
    for (var j = tokenLength; j > 0; j--) {
      final tokenPart = token.substring(0, j);
      (positionStorage[tokenPart] ??= []).add(internalId);
    }
  }
}

/// Searches positional storage for a term and returns a map of
/// document IDs to positional scores.
///
/// Score accumulation: for each token found in bucket `i`, the score
/// contribution is `i * boostPerProp`. Bucket 14 (first token position)
/// yields the highest score; bucket 0 (last token position) yields 0.
///
/// Matches Orama's `searchString` from `plugin-pt15/algorithm.ts:165-199`.
Map<int, double> searchString({
  required Tokenizer tokenizer,
  required String term,
  required PositionsStorage positionsStorage,
  required double boostPerProp,
  Set<int>? whereFiltersIDs,
}) {
  final tokens = tokenizer.tokenize(term);
  final ret = <int, double>{};

  for (final token in tokens) {
    for (var i = 0; i < maxPosition; i++) {
      final positionStorage = positionsStorage[i];
      final docIds = positionStorage[token];
      if (docIds != null) {
        for (final id in docIds) {
          if (whereFiltersIDs != null && !whereFiltersIDs.contains(id)) {
            continue;
          }
          ret[id] = (ret[id] ?? 0) + i * boostPerProp;
        }
      }
    }
  }

  return ret;
}

/// Removes a document from positional storage by splicing its ID out of
/// every prefix entry in the appropriate position buckets.
///
/// Matches Orama's `removeString` from `plugin-pt15/algorithm.ts:201-229`.
void removeString({
  required String value,
  required PositionsStorage positionsStorage,
  required String prop,
  required int internalId,
  required Tokenizer tokenizer,
  required String? language,
}) {
  final tokens = tokenizer.tokenize(value, property: prop);
  final tokensLength = tokens.length;

  for (var i = 0; i < tokensLength; i++) {
    final token = tokens[i];
    final position = maxPosition - getPosition(i, tokensLength) - 1;
    final positionStorage = positionsStorage[position];

    final tokenLength = token.length;
    for (var j = tokenLength; j > 0; j--) {
      final tokenPart = token.substring(0, j);
      final docIds = positionStorage[tokenPart];
      if (docIds != null) {
        final index = docIds.indexOf(internalId);
        if (index != -1) {
          docIds.removeAt(index);
        }
      }
    }
  }
}

/// Searches across multiple properties, merging scores from the largest
/// result set (by number of matched documents).
///
/// Matches the multi-property search logic in Orama's
/// `plugin-pt15/index.ts:147-208`.
///
/// For a single property, returns results directly. For multiple properties,
/// finds the map with the most entries (largest result set) and merges all
/// other maps into it by summing scores.
List<TokenScore> searchProperties({
  required Tokenizer tokenizer,
  required String term,
  required Map<String, PositionsStorage> propertyStorages,
  required Map<String, double> boost,
  Set<int>? whereFiltersIDs,
}) {
  final maps = <Map<int, double>>[];
  var maxSize = -1;
  var maxIndex = -1;

  var i = 0;
  for (final entry in propertyStorages.entries) {
    final property = entry.key;
    final storage = entry.value;
    final boostPerProp = boost[property] ?? 1.0;

    final map = searchString(
      tokenizer: tokenizer,
      term: term,
      positionsStorage: storage,
      boostPerProp: boostPerProp,
      whereFiltersIDs: whereFiltersIDs,
    );

    if (map.length > maxSize) {
      maxSize = map.length;
      maxIndex = i;
    }
    maps.add(map);
    i++;
  }

  if (maps.isEmpty) return [];

  if (maps.length == 1) {
    return maps[0].entries.map<TokenScore>((e) => (e.key, e.value)).toList();
  }

  // Merge all maps into the largest one
  final base = maps[maxIndex];
  for (var j = 0; j < maps.length; j++) {
    if (j == maxIndex) continue;
    final map = maps[j];
    for (final entry in map.entries) {
      base[entry.key] = (base[entry.key] ?? 0) + entry.value;
    }
  }

  return base.entries.map<TokenScore>((e) => (e.key, e.value)).toList();
}
