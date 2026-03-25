// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/text/fuzzy.dart';
import 'package:test/test.dart';

void main() {
  group('levenshtein (unbounded)', () {
    test('returns 0 for two empty strings', () {
      expect(levenshtein('', ''), 0);
    });

    test('returns length of first string when second is empty', () {
      expect(levenshtein('abc', ''), 3);
    });

    test('returns length of second string when first is empty', () {
      expect(levenshtein('', 'abc'), 3);
    });

    test('returns 3 for kitten → sitting', () {
      expect(levenshtein('kitten', 'sitting'), 3);
    });

    test('returns 3 for saturday → sunday', () {
      expect(levenshtein('saturday', 'sunday'), 3);
    });

    test('returns 0 for identical strings', () {
      expect(levenshtein('abc', 'abc'), 0);
    });
  });

  group('boundedLevenshtein', () {
    test('returns distance 0, isBounded true for equal strings', () {
      final result = boundedLevenshtein('abc', 'abc', 0);
      expect(result.distance, 0);
      expect(result.isBounded, isTrue);
    });

    test(
        'returns distance 1, isBounded true for '
        'single substitution within tolerance', () {
      final result = boundedLevenshtein('abc', 'axc', 1);
      expect(result.distance, 1);
      expect(result.isBounded, isTrue);
    });

    test('returns distance -1, isBounded false when distance exceeds tolerance',
        () {
      final result = boundedLevenshtein('abc', 'xyz', 1);
      expect(result.distance, -1);
      expect(result.isBounded, isFalse);
    });

    test('returns distance 0 when word starts with term (prefix optimization)',
        () {
      // word "helloworld" starts with term "hello" → returns 0
      final result = boundedLevenshtein('hello', 'helloworld', 5);
      expect(result.distance, 0);
      expect(result.isBounded, isTrue);
    });

    test('returns distance 0 for equal strings with zero tolerance', () {
      final result = boundedLevenshtein('test', 'test', 0);
      expect(result.distance, 0);
      expect(result.isBounded, isTrue);
    });

    test('returns distance 3 for empty word within tolerance', () {
      final result = boundedLevenshtein('abc', '', 3);
      expect(result.distance, 3);
      expect(result.isBounded, isTrue);
    });

    test('returns distance -1 for empty word exceeding tolerance', () {
      final result = boundedLevenshtein('abc', '', 2);
      expect(result.distance, -1);
      expect(result.isBounded, isFalse);
    });

    test('returns distance -1, isBounded false for negative tolerance', () {
      final result = boundedLevenshtein('abc', 'abc', -1);
      expect(result.distance, -1);
      expect(result.isBounded, isFalse);
    });
  });
}
