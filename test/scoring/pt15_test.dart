import 'package:searchlight/searchlight.dart';
import 'package:searchlight/src/scoring/pt15.dart';
import 'package:test/test.dart';

import '../helpers/extensions/test_index_plugin.dart';

void main() {
  group('PT15', () {
    group('getPosition', () {
      test('returns token index for short documents (< 15 tokens)', () {
        // For totalLength < 15, getPosition returns n directly
        expect(getPosition(0, 5), 0);
        expect(getPosition(1, 5), 1);
        expect(getPosition(4, 5), 4);
        expect(getPosition(0, 14), 0);
        expect(getPosition(13, 14), 13);
        expect(getPosition(7, 10), 7);
      });

      test('scales correctly for long documents (>= 15 tokens)', () {
        // For totalLength >= 15: floor((n * 15) / totalLength)
        // 30 tokens: each bucket spans 2 tokens
        expect(getPosition(0, 30), 0); // floor(0*15/30) = 0
        expect(getPosition(1, 30), 0); // floor(1*15/30) = 0
        expect(getPosition(2, 30), 1); // floor(2*15/30) = 1
        expect(getPosition(14, 30), 7); // floor(14*15/30) = 7
        expect(getPosition(29, 30), 14); // floor(29*15/30) = 14

        // 15 tokens: each bucket is exactly 1 token
        expect(getPosition(0, 15), 0);
        expect(getPosition(7, 15), 7);
        expect(getPosition(14, 15), 14);

        // 100 tokens
        expect(getPosition(0, 100), 0); // floor(0*15/100) = 0
        expect(getPosition(50, 100), 7); // floor(50*15/100) = 7
        expect(getPosition(99, 100), 14); // floor(99*15/100) = 14
      });
    });

    group('insertString', () {
      test('stores all prefixes in correct position bucket', () {
        final storage = createPositionsStorage();
        final tokenizer = Tokenizer(allowDuplicates: true);

        // Insert "hello" as a single-token document (docId=1)
        // Single token -> totalLength=1 -> position = 14 - 0 - 1 = ... wait
        // get_position(0, 1) = 0 (since 1 < 15)
        // bucket = 15 - 0 - 1 = 14
        insertString(
          value: 'hello',
          positionsStorage: storage,
          prop: 'title',
          internalId: 1,
          language: null,
          tokenizer: tokenizer,
        );

        // Bucket 14 should contain all prefixes of "hello"
        final bucket14 = storage[14];
        expect(bucket14['hello'], contains(1));
        expect(bucket14['hell'], contains(1));
        expect(bucket14['hel'], contains(1));
        expect(bucket14['he'], contains(1));
        expect(bucket14['h'], contains(1));

        // Other buckets should be empty
        for (var i = 0; i < 14; i++) {
          expect(storage[i], isEmpty, reason: 'Bucket $i should be empty');
        }
      });

      test(
          'puts first token in highest bucket (14), last in lowest '
          'for short docs', () {
        final storage = createPositionsStorage();
        final tokenizer = Tokenizer(
          allowDuplicates: true,
          useDefaultStopWords: false,
        );

        // "the quick brown" -> 3 tokens (< 15)
        // Token 0 ("the"): bucket = 15 - 0 - 1 = 14
        // Token 1 ("quick"): bucket = 15 - 1 - 1 = 13
        // Token 2 ("brown"): bucket = 15 - 2 - 1 = 12
        insertString(
          value: 'the quick brown',
          positionsStorage: storage,
          prop: 'title',
          internalId: 42,
          language: null,
          tokenizer: tokenizer,
        );

        // First token "the" should be in bucket 14 (highest score)
        expect(storage[14]['the'], contains(42));

        // Second token "quick" should be in bucket 13
        expect(storage[13]['quick'], contains(42));

        // Third token "brown" should be in bucket 12
        expect(storage[12]['brown'], contains(42));

        // Buckets 0-11 should be empty
        for (var i = 0; i <= 11; i++) {
          expect(storage[i], isEmpty, reason: 'Bucket $i should be empty');
        }
      });
    });

    group('searchString', () {
      test('returns scored results', () {
        final storage = createPositionsStorage();
        final tokenizer = Tokenizer(allowDuplicates: true);

        // Insert "hello world" for doc 1
        insertString(
          value: 'hello world',
          positionsStorage: storage,
          prop: 'title',
          internalId: 1,
          language: null,
          tokenizer: tokenizer,
        );

        final results = searchString(
          tokenizer: tokenizer,
          term: 'hello',
          positionsStorage: storage,
          boostPerProp: 1,
        );

        expect(results, isNotEmpty);
        expect(results.containsKey(1), isTrue);
        expect(results[1], isNotNull);
        // "hello" is at position 0, bucket = 14, score = 14 * 1.0 = 14
        expect(results[1], equals(14.0));
      });

      test('scores tokens at document start higher than end', () {
        final storage = createPositionsStorage();
        final tokenizer = Tokenizer(allowDuplicates: true);

        // Insert "alpha beta" for doc 1 (alpha=first, beta=last)
        insertString(
          value: 'alpha beta',
          positionsStorage: storage,
          prop: 'title',
          internalId: 1,
          language: null,
          tokenizer: tokenizer,
        );

        // Search for "alpha" (first token -> bucket 14 -> score = 14)
        final alphaResults = searchString(
          tokenizer: tokenizer,
          term: 'alpha',
          positionsStorage: storage,
          boostPerProp: 1,
        );

        // Search for "beta" (second token -> bucket 13 -> score = 13)
        final betaResults = searchString(
          tokenizer: tokenizer,
          term: 'beta',
          positionsStorage: storage,
          boostPerProp: 1,
        );

        expect(alphaResults[1], greaterThan(betaResults[1]!));
      });

      test('finds partial matches via prefix storage', () {
        final storage = createPositionsStorage();
        final tokenizer = Tokenizer(allowDuplicates: true);

        // Insert "developer" for doc 1
        insertString(
          value: 'developer',
          positionsStorage: storage,
          prop: 'title',
          internalId: 1,
          language: null,
          tokenizer: tokenizer,
        );

        // Search for "dev" - should match via prefix
        final results = searchString(
          tokenizer: tokenizer,
          term: 'dev',
          positionsStorage: storage,
          boostPerProp: 1,
        );

        expect(results.containsKey(1), isTrue);
        expect(results[1], greaterThan(0));

        // Search for "d" - single char prefix should also match
        final singleCharResults = searchString(
          tokenizer: tokenizer,
          term: 'd',
          positionsStorage: storage,
          boostPerProp: 1,
        );

        expect(singleCharResults.containsKey(1), isTrue);
      });

      test('respects whereFiltersIDs', () {
        final storage = createPositionsStorage();
        final tokenizer = Tokenizer(allowDuplicates: true);

        // Insert same text for docs 1, 2, and 3
        for (final id in [1, 2, 3]) {
          insertString(
            value: 'hello',
            positionsStorage: storage,
            prop: 'title',
            internalId: id,
            language: null,
            tokenizer: tokenizer,
          );
        }

        // Search with filter allowing only docs 1 and 3
        final results = searchString(
          tokenizer: tokenizer,
          term: 'hello',
          positionsStorage: storage,
          boostPerProp: 1,
          whereFiltersIDs: {1, 3},
        );

        expect(results.containsKey(1), isTrue);
        expect(results.containsKey(2), isFalse);
        expect(results.containsKey(3), isTrue);
      });

      test('applies boost per property', () {
        final storage = createPositionsStorage();
        final tokenizer = Tokenizer(allowDuplicates: true);

        // Insert "hello" for doc 1 (single token, bucket 14)
        insertString(
          value: 'hello',
          positionsStorage: storage,
          prop: 'title',
          internalId: 1,
          language: null,
          tokenizer: tokenizer,
        );

        // With boost 1.0: score = 14 * 1.0 = 14
        final normalResults = searchString(
          tokenizer: tokenizer,
          term: 'hello',
          positionsStorage: storage,
          boostPerProp: 1,
        );

        // With boost 2.5: score = 14 * 2.5 = 35
        final boostedResults = searchString(
          tokenizer: tokenizer,
          term: 'hello',
          positionsStorage: storage,
          boostPerProp: 2.5,
        );

        expect(normalResults[1], equals(14.0));
        expect(boostedResults[1], equals(35.0));
        expect(boostedResults[1], greaterThan(normalResults[1]!));
      });
    });

    group('removeString', () {
      test('cleans up position storage', () {
        final storage = createPositionsStorage();
        final tokenizer = Tokenizer(allowDuplicates: true);

        // Insert "hello world" for docs 1 and 2
        insertString(
          value: 'hello world',
          positionsStorage: storage,
          prop: 'title',
          internalId: 1,
          language: null,
          tokenizer: tokenizer,
        );
        insertString(
          value: 'hello world',
          positionsStorage: storage,
          prop: 'title',
          internalId: 2,
          language: null,
          tokenizer: tokenizer,
        );

        // Verify both are found
        var results = searchString(
          tokenizer: tokenizer,
          term: 'hello',
          positionsStorage: storage,
          boostPerProp: 1,
        );
        expect(results.containsKey(1), isTrue);
        expect(results.containsKey(2), isTrue);

        // Remove doc 1
        removeString(
          value: 'hello world',
          positionsStorage: storage,
          prop: 'title',
          internalId: 1,
          tokenizer: tokenizer,
          language: null,
        );

        // Doc 1 should no longer appear; doc 2 still present
        results = searchString(
          tokenizer: tokenizer,
          term: 'hello',
          positionsStorage: storage,
          boostPerProp: 1,
        );
        expect(results.containsKey(1), isFalse);
        expect(results.containsKey(2), isTrue);
      });
    });

    group('searchProperties', () {
      test('multi-property search merges scores from largest result set', () {
        final tokenizer = Tokenizer(allowDuplicates: true);

        // Create two properties with their own storage
        final titleStorage = createPositionsStorage();
        final bodyStorage = createPositionsStorage();

        // Doc 1: title="hello", body="hello world"
        insertString(
          value: 'hello',
          positionsStorage: titleStorage,
          prop: 'title',
          internalId: 1,
          language: null,
          tokenizer: tokenizer,
        );
        insertString(
          value: 'hello world',
          positionsStorage: bodyStorage,
          prop: 'body',
          internalId: 1,
          language: null,
          tokenizer: tokenizer,
        );

        // Doc 2: body="hello earth" only
        insertString(
          value: 'hello earth',
          positionsStorage: bodyStorage,
          prop: 'body',
          internalId: 2,
          language: null,
          tokenizer: tokenizer,
        );

        // Search across both properties
        final propertyStorages = {
          'title': titleStorage,
          'body': bodyStorage,
        };
        final boost = <String, double>{'title': 1.0, 'body': 1.0};

        final results = searchProperties(
          tokenizer: tokenizer,
          term: 'hello',
          propertyStorages: propertyStorages,
          boost: boost,
        );

        // Both docs should be in results
        expect(results.length, greaterThanOrEqualTo(2));

        // Doc 1 should score higher (matched in both title and body)
        final doc1Score = results.firstWhere((r) => r.$1 == 1).$2;
        final doc2Score = results.firstWhere((r) => r.$1 == 2).$2;
        expect(doc1Score, greaterThan(doc2Score));
      });
    });

    group('component plugin', () {
      test('forced PT15 index preserves prefix matching through plugins', () {
        final db = Searchlight.create(
          schema: Schema({
            'title': const TypedField(SchemaType.string),
          }),
          plugins: [
            testIndexPlugin(
              name: 'pt15-plugin',
              componentId: 'test.index.pt15',
              forcedAlgorithm: SearchAlgorithm.pt15,
            ),
          ],
        )..insert({'id': 'doc-1', 'title': 'hello world'});
        addTearDown(db.dispose);

        final result = db.search(term: 'hel');

        expect(db.indexAlgorithm, SearchAlgorithm.pt15);
        expect(result.count, 1);
        expect(result.hits.first.id, 'doc-1');
      });
    });
  });
}
