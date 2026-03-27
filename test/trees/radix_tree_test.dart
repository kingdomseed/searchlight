// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/trees/radix_tree.dart';
import 'package:test/test.dart';

void main() {
  group('RadixTree', () {
    test('insert single word and find returns it with docId', () {
      final tree = RadixTree()..insert('hello', 1);
      final result = tree.find(term: 'hello');
      expect(result, {
        'hello': [1],
      });
    });

    test('insert two words with common prefix — edge splitting works', () {
      final tree = RadixTree()
        ..insert('test', 1)
        ..insert('team', 2);
      // Both should be findable.
      expect(tree.find(term: 'test'), {
        'test': [1],
      });
      expect(tree.find(term: 'team'), {
        'team': [2],
      });
    });

    test('insert word that is prefix of existing word', () {
      final tree = RadixTree()
        ..insert('testing', 1)
        ..insert('test', 2);
      // Prefix search for 'test' returns both 'test' and 'testing'.
      expect(tree.find(term: 'test'), {
        'test': [2],
        'testing': [1],
      });
      // Exact search for 'test' returns only 'test'.
      expect(tree.find(term: 'test', exact: true), {
        'test': [2],
      });
      expect(tree.find(term: 'testing'), {
        'testing': [1],
      });
    });

    test('insert word where existing word is prefix', () {
      final tree = RadixTree()
        ..insert('test', 1)
        ..insert('testing', 2);
      expect(tree.find(term: 'test'), {
        'test': [1],
        'testing': [2],
      });
      expect(tree.find(term: 'testing'), {
        'testing': [2],
      });
    });

    test('find with prefix returns all words starting with prefix', () {
      final tree = RadixTree()
        ..insert('phone', 1)
        ..insert('photo', 2)
        ..insert('phrase', 3)
        ..insert('phonetic', 4);
      // 'ph' is a partial prefix that ends in the middle of an edge label.
      final result = tree.find(term: 'ph');
      expect(
        result.keys,
        unorderedEquals(['phone', 'photo', 'phrase', 'phonetic']),
      );
      // 'pho' prefix matches phone, photo, phonetic.
      final result2 = tree.find(term: 'pho');
      expect(
        result2.keys,
        unorderedEquals(['phone', 'photo', 'phonetic']),
      );
    });

    test('find with exact=true returns only exact match', () {
      final tree = RadixTree()
        ..insert('test', 1)
        ..insert('testing', 2)
        ..insert('team', 3);
      // exact for 'test' should only return 'test', not 'testing'.
      expect(tree.find(term: 'test', exact: true), {
        'test': [1],
      });
      // exact for 'te' returns empty since 'te' is not a complete word.
      expect(tree.find(term: 'te', exact: true), isEmpty);
      // exact for a non-existent word returns empty.
      expect(tree.find(term: 'toast', exact: true), isEmpty);
    });

    test('find with tolerance=1 returns fuzzy matches', () {
      final tree = RadixTree()
        ..insert('hello', 1)
        ..insert('hallo', 2)
        ..insert('world', 3);
      // 'helo' is 1 edit away from 'hello'.
      final result = tree.find(term: 'helo', tolerance: 1);
      expect(result.containsKey('hello'), isTrue);
      expect(result['hello'], [1]);
      // 'hallo' is 1 edit from 'hello' but 2 from 'helo'.
      // So 'hallo' should NOT appear for tolerance=1 from 'helo'.
      // 'world' is far away, should not appear.
      expect(result.containsKey('world'), isFalse);
    });

    test('find with tolerance=0 returns only exact prefix matches', () {
      final tree = RadixTree()
        ..insert('hello', 1)
        ..insert('hallo', 2);
      // tolerance=0 means no fuzzy matching; behaves like prefix search.
      final result = tree.find(term: 'hello', tolerance: 0);
      expect(result, {
        'hello': [1],
      });
      // tolerance=0 for 'helo' should return nothing (no prefix match).
      final result2 = tree.find(term: 'helo', tolerance: 0);
      expect(result2, isEmpty);
    });

    test('contains returns true for existing prefix', () {
      final tree = RadixTree()
        ..insert('hello', 1)
        ..insert('help', 2);
      // 'hel' matches full edge label in the tree (after splitting).
      expect(tree.contains('hel'), isTrue);
      expect(tree.contains('hello'), isTrue);
      expect(tree.contains('help'), isTrue);
    });

    test('contains returns false for missing prefix', () {
      final tree = RadixTree()..insert('hello', 1);
      expect(tree.contains('world'), isFalse);
      expect(tree.contains('hex'), isFalse);
      // 'he' ends mid-edge (edge is 'hello'), so contains returns false.
      expect(tree.contains('he'), isFalse);
    });

    test('removeDocumentByWord removes docId from specific word', () {
      final tree = RadixTree()
        ..insert('hello', 1)
        ..insert('hello', 2);
      // Remove doc 1 from 'hello'.
      expect(tree.removeDocumentByWord('hello', 1), isTrue);
      final result = tree.find(term: 'hello');
      expect(result, {
        'hello': [2],
      });
      // Removing from a non-existent word returns false.
      expect(tree.removeDocumentByWord('world', 1), isFalse);
    });

    test('removeWord removes entire word and cleans up nodes', () {
      final tree = RadixTree()
        ..insert('hello', 1)
        ..insert('help', 2);
      // Remove 'hello'.
      expect(tree.removeWord('hello'), isTrue);
      expect(tree.find(term: 'hello'), isEmpty);
      // 'help' should still be there.
      expect(tree.find(term: 'help'), {
        'help': [2],
      });
      // Removing non-existent word returns false.
      expect(tree.removeWord('world'), isFalse);
      // Removing empty string returns false.
      expect(tree.removeWord(''), isFalse);
    });

    test('multiple documents per word', () {
      final tree = RadixTree()
        ..insert('hello', 1)
        ..insert('hello', 2)
        ..insert('hello', 3);
      final result = tree.find(term: 'hello');
      expect(result['hello'], unorderedEquals([1, 2, 3]));
      // Duplicate insert is idempotent (Set semantics).
      tree.insert('hello', 1);
      final result2 = tree.find(term: 'hello');
      expect(result2['hello'], unorderedEquals([1, 2, 3]));
    });

    test('findAllWords DFS collects all words in subtree', () {
      final tree = RadixTree()
        ..insert('apple', 1)
        ..insert('app', 2)
        ..insert('application', 3)
        ..insert('banana', 4);
      // findAllWords from root collects all words in the tree.
      final output = <String, List<int>>{};
      tree.findAllWords(output, '');
      expect(
        output.keys,
        unorderedEquals(['apple', 'app', 'application', 'banana']),
      );
      expect(output['apple'], [1]);
      expect(output['app'], [2]);
      expect(output['application'], [3]);
      expect(output['banana'], [4]);
    });

    test('toJson/fromJson round-trip preserves data', () {
      final tree = RadixTree()
        ..insert('hello', 1)
        ..insert('help', 2)
        ..insert('world', 3)
        ..insert('hello', 4);

      final json = tree.toJson();
      final restored = RadixTree.fromJson(json);

      // All words and docIds are preserved.
      expect(restored.find(term: 'hello'), {
        'hello': unorderedEquals([1, 4]),
      });
      expect(restored.find(term: 'help'), {
        'help': [2],
      });
      expect(restored.find(term: 'world'), {
        'world': [3],
      });
      // Missing words still return empty.
      expect(restored.find(term: 'missing'), isEmpty);
    });
  });
}
