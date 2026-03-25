// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/scoring/qps.dart';
import 'package:searchlight/src/text/tokenizer.dart';
import 'package:searchlight/src/trees/radix_tree.dart';
import 'package:test/test.dart';

void main() {
  group('QPS bit-packing helpers', () {
    test('calculateTokenQuantum packs count and bitmask correctly', () {
      // First call: prevValue=0, bit=0
      // count(0)=0, bitmask_20(0)=0
      // newSentenceMask = 0 | (1 << 0) = 1
      // result = ((0 + 1) << 20) | 1 = 1048576 | 1 = 1048577
      final first = calculateTokenQuantum(0, 0);
      expect(first, 1048577); // (1 << 20) | 1

      // Second call on same token: prevValue=first, bit=0
      // count(1048577) = 1048577 >> 20 = 1
      // bitmask_20(1048577) = 1048577 & 0xFFFFF = 1
      // newSentenceMask = 1 | (1 << 0) = 1
      // result = ((1 + 1) << 20) | 1 = 2097152 | 1 = 2097153
      final second = calculateTokenQuantum(first, 0);
      expect(second, 2097153); // (2 << 20) | 1

      // Third call with different bit: prevValue=second, bit=3
      // count(2097153) = 2097153 >> 20 = 2
      // bitmask_20(2097153) = 2097153 & 0xFFFFF = 1
      // newSentenceMask = 1 | (1 << 3) = 1 | 8 = 9
      // result = ((2 + 1) << 20) | 9 = 3145728 | 9 = 3145737
      final third = calculateTokenQuantum(second, 3);
      expect(third, 3145737); // (3 << 20) | 9
    });

    test('bitmask20 extracts lower 20 bits', () {
      // Value with bits in both upper and lower regions
      // (5 << 20) | 0b10101 = 5242880 | 21 = 5242901
      expect(bitmask20(5242901), 21); // 0b10101
      expect(bitmask20(0), 0);
      expect(bitmask20(0xFFFFF), 0xFFFFF); // all 20 bits set
      // Upper bits should be stripped
      expect(bitmask20(0x100000), 0); // bit 21 only -> lower 20 = 0
      expect(bitmask20(0x1FFFFF), 0xFFFFF); // bits 0-20 set
    });

    test('countFromPacked extracts upper bits (occurrence count)', () {
      // (3 << 20) | 0b101 = 3145728 | 5 = 3145733
      expect(countFromPacked(3145733), 3);
      expect(countFromPacked(0), 0);
      // (1 << 20) | 0 = 1048576
      expect(countFromPacked(1048576), 1);
      // Round-trip: pack then extract
      final packed = calculateTokenQuantum(0, 5);
      expect(countFromPacked(packed), 1);
      expect(bitmask20(packed), 1 << 5);
    });

    test('numberOfOnes counts set bits correctly', () {
      expect(numberOfOnes(0), 0);
      expect(numberOfOnes(1), 1);
      expect(numberOfOnes(10), 2); // 0b1010 = 10
      expect(numberOfOnes(15), 4); // 0b1111 = 15
      expect(numberOfOnes(0xFFFFF), 20); // all 20 bits set
      expect(numberOfOnes(341), 5); // 0b101010101 = 341
    });
  });

  group('QPS insertString', () {
    late Tokenizer tokenizer;
    late RadixTree radixTree;
    late QPSStats stats;

    setUp(() {
      tokenizer = Tokenizer();
      radixTree = RadixTree();
      stats = QPSStats();
    });

    test('populates tokenQuantums and tokensLength for a simple document', () {
      // "hello world" is one sentence with two tokens
      stats.tokenQuantums[1] = {};

      qpsInsertString(
        value: 'hello world',
        radixTree: radixTree,
        stats: stats,
        prop: 'title',
        internalId: 1,
        tokenizer: tokenizer,
      );

      // tokensLength should be 2
      expect(stats.tokensLength[1], 2);

      // Both tokens should be in tokenQuantums for doc 1
      final docQuantums = stats.tokenQuantums[1]!;
      expect(docQuantums.containsKey('hello'), isTrue);
      expect(docQuantums.containsKey('world'), isTrue);

      // Both in sentence 0 with count 1: ((1) << 20) | (1 << 0) = 1048577
      expect(countFromPacked(docQuantums['hello']!), 1);
      expect(bitmask20(docQuantums['hello']!), 1); // bit 0 set
      expect(countFromPacked(docQuantums['world']!), 1);
      expect(bitmask20(docQuantums['world']!), 1); // bit 0 set

      // Radix tree should contain both tokens
      final helloResult = radixTree.find(term: 'hello', exact: true);
      expect(helloResult['hello'], contains(1));
      final worldResult = radixTree.find(term: 'world', exact: true);
      expect(worldResult['world'], contains(1));
    });
  });

  group('QPS searchString', () {
    late Tokenizer tokenizer;
    late RadixTree radixTree;
    late QPSStats stats;

    /// Helper: insert a document, handling tokenQuantums initialization.
    void insertDoc(int docId, String value, {String prop = 'title'}) {
      stats.tokenQuantums[docId] = {};
      qpsInsertString(
        value: value,
        radixTree: radixTree,
        stats: stats,
        prop: prop,
        internalId: docId,
        tokenizer: tokenizer,
      );
    }

    setUp(() {
      tokenizer = Tokenizer();
      radixTree = RadixTree();
      stats = QPSStats();
    });

    test('returns scored results for a matching term', () {
      insertDoc(1, 'hello world');
      insertDoc(2, 'hello dart');

      final resultMap = <int, (double, int)>{};
      qpsSearchString(
        tokens: ['hello'],
        radixNode: radixTree,
        exact: false,
        tolerance: 0,
        stats: stats,
        boostPerProp: 1,
        resultMap: resultMap,
      );

      // Both docs should match
      expect(resultMap.containsKey(1), isTrue);
      expect(resultMap.containsKey(2), isTrue);
      // Scores should be positive
      expect(resultMap[1]!.$1, greaterThan(0));
      expect(resultMap[2]!.$1, greaterThan(0));
    });

    test('scores proximity higher when tokens share a sentence', () {
      // Doc 1: "quick brown" in same sentence
      insertDoc(1, 'quick brown fox');
      // Doc 2: "quick" in one sentence, "brown" in another
      insertDoc(2, 'quick fox. brown dog');

      final resultMap = <int, (double, int)>{};
      qpsSearchString(
        tokens: ['quick', 'brown'],
        radixNode: radixTree,
        exact: false,
        tolerance: 0,
        stats: stats,
        boostPerProp: 1,
        resultMap: resultMap,
      );

      // Both docs should match
      expect(resultMap.containsKey(1), isTrue);
      expect(resultMap.containsKey(2), isTrue);

      // Doc 1 should score higher because "quick" and "brown" share
      // sentence 0, giving a proximity bonus.
      expect(resultMap[1]!.$1, greaterThan(resultMap[2]!.$1));
    });

    test('gives exact match bonus (+1) over prefix match', () {
      // Insert "test" and "testing" so searching for "test" gives both
      insertDoc(1, 'test');
      insertDoc(2, 'testing');

      // Search for "test" with exact=false so prefix matches too
      final resultMap = <int, (double, int)>{};
      qpsSearchString(
        tokens: ['test'],
        radixNode: radixTree,
        exact: false,
        tolerance: 0,
        stats: stats,
        boostPerProp: 1,
        resultMap: resultMap,
      );

      // Both should match (prefix matching)
      expect(resultMap.containsKey(1), isTrue);
      expect(resultMap.containsKey(2), isTrue);

      // Doc 1 has the exact token "test" so gets +1 bonus.
      // Doc 2 has "testing" which is not an exact match to the search token.
      // Both have occurrence=1, but doc 1 has numberOfQuantums=1 and doc 2
      // also has numberOfQuantums=1.
      // Doc 1: (1*1/1 + 1) * 1 = 2.0
      // Doc 2: (1*1/1 + 0) * 1 = 1.0
      expect(resultMap[1]!.$1, greaterThan(resultMap[2]!.$1));
    });

    test('respects whereFiltersIDs', () {
      insertDoc(1, 'hello world');
      insertDoc(2, 'hello dart');
      insertDoc(3, 'hello flutter');

      final resultMap = <int, (double, int)>{};
      qpsSearchString(
        tokens: ['hello'],
        radixNode: radixTree,
        exact: false,
        tolerance: 0,
        stats: stats,
        boostPerProp: 1,
        resultMap: resultMap,
        whereFiltersIDs: {1, 3}, // Only docs 1 and 3
      );

      expect(resultMap.containsKey(1), isTrue);
      expect(resultMap.containsKey(2), isFalse); // filtered out
      expect(resultMap.containsKey(3), isTrue);
    });

    test('applies boost per property', () {
      insertDoc(1, 'hello world');

      // Search with boost = 1.0
      final resultMap1 = <int, (double, int)>{};
      qpsSearchString(
        tokens: ['hello'],
        radixNode: radixTree,
        exact: false,
        tolerance: 0,
        stats: stats,
        boostPerProp: 1,
        resultMap: resultMap1,
      );

      // Search with boost = 3.0
      final resultMap3 = <int, (double, int)>{};
      qpsSearchString(
        tokens: ['hello'],
        radixNode: radixTree,
        exact: false,
        tolerance: 0,
        stats: stats,
        boostPerProp: 3,
        resultMap: resultMap3,
      );

      // Score with 3x boost should be 3x the score with 1x boost
      expect(resultMap3[1]!.$1, closeTo(resultMap1[1]!.$1 * 3, 1e-10));
    });
  });

  group('QPS removeString', () {
    late Tokenizer tokenizer;
    late RadixTree radixTree;
    late QPSStats stats;

    setUp(() {
      tokenizer = Tokenizer();
      radixTree = RadixTree();
      stats = QPSStats();
    });

    test('cleans up tokenQuantums and tokensLength', () {
      // Insert a doc
      stats.tokenQuantums[1] = {};
      qpsInsertString(
        value: 'hello world',
        radixTree: radixTree,
        stats: stats,
        prop: 'title',
        internalId: 1,
        tokenizer: tokenizer,
      );

      // Verify it's there
      expect(stats.tokensLength.containsKey(1), isTrue);
      expect(stats.tokenQuantums.containsKey(1), isTrue);
      expect(radixTree.find(term: 'hello', exact: true)['hello'], contains(1));

      // Remove it
      qpsRemoveString(
        value: 'hello world',
        radixTree: radixTree,
        stats: stats,
        prop: 'title',
        internalId: 1,
        tokenizer: tokenizer,
      );

      // Stats should be cleaned up
      expect(stats.tokensLength.containsKey(1), isFalse);
      expect(stats.tokenQuantums.containsKey(1), isFalse);

      // Radix tree should no longer have doc 1 for these tokens
      final result = radixTree.find(term: 'hello', exact: true);
      expect(
        result['hello'] == null || !result['hello']!.contains(1),
        isTrue,
      );
    });
  });
}
