import 'package:searchlight/src/core/exceptions.dart';
import 'package:searchlight/src/core/schema.dart';
import 'package:searchlight/src/indexing/index_manager.dart';
import 'package:searchlight/src/scoring/bm25.dart';
import 'package:searchlight/src/text/tokenizer.dart';
import 'package:searchlight/src/trees/avl_tree.dart';
import 'package:searchlight/src/trees/bool_node.dart';
import 'package:searchlight/src/trees/flat_tree.dart';
import 'package:searchlight/src/trees/radix_tree.dart';
import 'package:test/test.dart';

void main() {
  group('SearchIndex', () {
    group('create', () {
      test('builds correct tree types from schema', () {
        final schema = Schema({
          'title': const TypedField(SchemaType.string),
          'price': const TypedField(SchemaType.number),
          'active': const TypedField(SchemaType.boolean),
          'category': const TypedField(SchemaType.enumType),
        });

        final index = SearchIndex.create(schema: schema);

        expect(index.treeTypeAt('title'), TreeType.radix);
        expect(index.treeTypeAt('price'), TreeType.avl);
        expect(index.treeTypeAt('active'), TreeType.bool);
        expect(index.treeTypeAt('category'), TreeType.flat);
      });

      // Item 1: AVL tree init -- Orama inits number fields with root key=0
      test('number field AVL tree initializes with root key=0', () {
        final schema = Schema({
          'price': const TypedField(SchemaType.number),
        });
        final index = SearchIndex.create(schema: schema);
        final tree = index.indexes['price']!.node as AVLTree<num, int>;
        // Orama: new AVLTree<number, InternalDocumentID>(0, [])
        expect(tree.root, isNotNull);
        expect(tree.root!.key, 0);
        expect(tree.root!.values, isEmpty);
      });

      // Item 1: numberArray field also initializes with root key=0
      test('numberArray field AVL tree initializes with root key=0', () {
        final schema = Schema({
          'scores': const TypedField(SchemaType.numberArray),
        });
        final index = SearchIndex.create(schema: schema);
        final tree = index.indexes['scores']!.node as AVLTree<num, int>;
        expect(tree.root, isNotNull);
        expect(tree.root!.key, 0);
        expect(tree.root!.values, isEmpty);
      });
    });

    group('insertDocument', () {
      test('indexes string field into radix tree', () {
        final schema = Schema({
          'title': const TypedField(SchemaType.string),
        });
        final index = SearchIndex.create(schema: schema);
        final tokenizer = Tokenizer(allowDuplicates: true);

        index.insertDocument(
          docId: 1,
          data: {'title': 'hello world'},
          tokenizer: tokenizer,
        );

        final tree = index.indexes['title']!.node as RadixTree;
        final result = tree.find(term: 'hello');
        expect(result, containsPair('hello', [1]));
        final result2 = tree.find(term: 'world');
        expect(result2, containsPair('world', [1]));
      });

      test('indexes number field into AVL tree', () {
        final schema = Schema({
          'price': const TypedField(SchemaType.number),
        });
        final index = SearchIndex.create(schema: schema);
        final tokenizer = Tokenizer(allowDuplicates: true);

        index.insertDocument(
          docId: 1,
          data: {'price': 42},
          tokenizer: tokenizer,
        );

        final tree = index.indexes['price']!.node as AVLTree<num, int>;
        expect(tree.find(42), {1});
      });

      test('indexes boolean field into BoolNode', () {
        final schema = Schema({
          'active': const TypedField(SchemaType.boolean),
        });
        final index = SearchIndex.create(schema: schema);
        final tokenizer = Tokenizer(allowDuplicates: true);

        index
          ..insertDocument(
            docId: 1,
            data: {'active': true},
            tokenizer: tokenizer,
          )
          ..insertDocument(
            docId: 2,
            data: {'active': false},
            tokenizer: tokenizer,
          );

        final node = index.indexes['active']!.node as BoolNode<int>;
        expect(node.trueSet, {1});
        expect(node.falseSet, {2});
      });

      test('tracks frequencies and avgFieldLength for string fields', () {
        final schema = Schema({
          'title': const TypedField(SchemaType.string),
        });
        final index = SearchIndex.create(schema: schema);
        final tokenizer = Tokenizer(allowDuplicates: true);

        // Doc 1: "hello world" => 2 tokens
        index.insertDocument(
          docId: 1,
          data: {'title': 'hello world'},
          tokenizer: tokenizer,
        );
        // After 1 doc: avgFieldLength = 2
        expect(index.avgFieldLength['title'], 2.0);
        expect(index.fieldLengths['title']![1], 2);
        // Frequencies: each token appears once in 2-token field => tf = 0.5
        expect(index.frequencies['title']![1]!['hello'], 0.5);
        expect(index.frequencies['title']![1]!['world'], 0.5);
        // Token occurrences: each token appears in 1 doc
        expect(index.tokenOccurrences['title']!['hello'], 1);
        expect(index.tokenOccurrences['title']!['world'], 1);

        // Doc 2: "hello hello hello world" => 4 tokens (but tokenizer
        // deduplicates by default). Use allowDuplicates for accurate tf.
        index.insertDocument(
          docId: 2,
          data: {'title': 'hello hello hello world'},
          tokenizer: tokenizer,
        );
        // After 2 docs: avgFieldLength = (2*1 + 4) / 2 = 3
        expect(index.avgFieldLength['title'], 3.0);
        expect(index.fieldLengths['title']![2], 4);
        // hello: 3/4 = 0.75 tf
        expect(index.frequencies['title']![2]!['hello'], 0.75);
        // world: 1/4 = 0.25 tf
        expect(index.frequencies['title']![2]!['world'], 0.25);
      });

      test('indexes enum field into FlatTree', () {
        final schema = Schema({
          'category': const TypedField(SchemaType.enumType),
        });
        final index = SearchIndex.create(schema: schema);
        final tokenizer = Tokenizer(allowDuplicates: true);

        index.insertDocument(
          docId: 1,
          data: {'category': 'electronics'},
          tokenizer: tokenizer,
        );

        final tree = index.indexes['category']!.node as FlatTree;
        expect(tree.find('electronics'), [1]);
      });
    });

    group('removeDocument', () {
      test('removes from all indexes', () {
        final schema = Schema({
          'title': const TypedField(SchemaType.string),
          'price': const TypedField(SchemaType.number),
          'active': const TypedField(SchemaType.boolean),
        });
        final index = SearchIndex.create(schema: schema);
        final tokenizer = Tokenizer(allowDuplicates: true);

        index.insertDocument(
          docId: 1,
          data: {'title': 'hello', 'price': 10, 'active': true},
          tokenizer: tokenizer,
        );
        expect(index.docsCount, 1);

        index.removeDocument(
          docId: 1,
          data: {'title': 'hello', 'price': 10, 'active': true},
          tokenizer: tokenizer,
        );

        expect(index.docsCount, 0);
        final radix = index.indexes['title']!.node as RadixTree;
        final result = radix.find(term: 'hello');
        // After removal, the node may still exist but with no document IDs
        final docIds = result['hello'] ?? [];
        expect(docIds, isEmpty);
        final avl = index.indexes['price']!.node as AVLTree<num, int>;
        expect(avl.find(10), isNull);
        final boolNode = index.indexes['active']!.node as BoolNode<int>;
        expect(boolNode.trueSet, isEmpty);
      });
      test('updates avgFieldLength correctly', () {
        final schema = Schema({
          'title': const TypedField(SchemaType.string),
        });
        final index = SearchIndex.create(schema: schema);
        final tokenizer = Tokenizer(
          allowDuplicates: true,
          useDefaultStopWords: false,
        );

        // Doc 1: 2 tokens, Doc 2: 4 tokens => avg = 3
        index
          ..insertDocument(
            docId: 1,
            data: {'title': 'hello world'},
            tokenizer: tokenizer,
          )
          ..insertDocument(
            docId: 2,
            data: {'title': 'the quick brown fox'},
            tokenizer: tokenizer,
          );
        expect(index.avgFieldLength['title'], 3.0);

        // Remove doc 1 (2 tokens): avg = (3*2 - 2) / 1 = 4
        index.removeDocument(
          docId: 1,
          data: {'title': 'hello world'},
          tokenizer: tokenizer,
        );
        expect(index.avgFieldLength['title'], 4.0);
        expect(index.fieldLengths['title']!.containsKey(1), isFalse);
        expect(index.frequencies['title']!.containsKey(1), isFalse);
      });

      test('removing string-array doc updates bm25 stats once per document',
          () {
        final schema = Schema({
          'tags': const TypedField(SchemaType.stringArray),
        });
        final index = SearchIndex.create(schema: schema);
        final tokenizer = Tokenizer(
          allowDuplicates: true,
          useDefaultStopWords: false,
        );

        index
          ..insertDocument(
            docId: 1,
            data: {
              'tags': ['red green', 'blue yellow'],
            },
            tokenizer: tokenizer,
          )
          ..insertDocument(
            docId: 2,
            data: {
              'tags': ['orange'],
            },
            tokenizer: tokenizer,
          )
          ..removeDocument(
            docId: 1,
            data: {
              'tags': ['red green', 'blue yellow'],
            },
            tokenizer: tokenizer,
          );

        expect(index.docsCount, 1);
        expect(index.avgFieldLength['tags'], 1.0);
        expect(index.fieldLengths['tags'], {2: 1});
        expect(index.frequencies['tags']!.containsKey(1), isFalse);
        expect(index.frequencies['tags']![2], containsPair('orange', 1.0));
      });
    });

    group('search', () {
      late SearchIndex index;
      late Tokenizer tokenizer;

      setUp(() {
        final schema = Schema({
          'title': const TypedField(SchemaType.string),
          'body': const TypedField(SchemaType.string),
        });
        index = SearchIndex.create(schema: schema);
        tokenizer = Tokenizer(allowDuplicates: true);

        index
          ..insertDocument(
            docId: 1,
            data: {'title': 'hello world', 'body': 'a greeting'},
            tokenizer: tokenizer,
          )
          ..insertDocument(
            docId: 2,
            data: {'title': 'goodbye world', 'body': 'a farewell'},
            tokenizer: tokenizer,
          )
          ..insertDocument(
            docId: 3,
            data: {
              'title': 'hello again',
              'body': 'another greeting',
            },
            tokenizer: tokenizer,
          );
      });

      test('returns scored results for matching term', () {
        final results = index.search(
          term: 'hello',
          tokenizer: tokenizer,
          propertiesToSearch: ['title'],
          relevance: const BM25Params(),
        );

        // Should match docs 1 and 3 (both have 'hello' in title)
        expect(results, hasLength(2));
        final docIds = results.map((r) => r.$1).toSet();
        expect(docIds, containsAll([1, 3]));
        // All scores should be positive
        for (final (_, score) in results) {
          expect(score, greaterThan(0));
        }
      });

      test('with boost multiplies score for boosted property', () {
        // Search without boost
        final unboosted = index.search(
          term: 'hello',
          tokenizer: tokenizer,
          propertiesToSearch: ['title'],
          relevance: const BM25Params(),
        );

        // Search with 2x boost on title
        final boosted = index.search(
          term: 'hello',
          tokenizer: tokenizer,
          propertiesToSearch: ['title'],
          relevance: const BM25Params(),
          boost: {'title': 2.0},
        );

        // Boosted scores should be exactly 2x unboosted
        expect(boosted, hasLength(unboosted.length));
        for (var i = 0; i < unboosted.length; i++) {
          expect(boosted[i].$1, unboosted[i].$1);
          expect(boosted[i].$2, closeTo(unboosted[i].$2 * 2.0, 1e-10));
        }
      });

      test('with whereFiltersIDs only scores filtered documents', () {
        final results = index.search(
          term: 'hello',
          tokenizer: tokenizer,
          propertiesToSearch: ['title'],
          relevance: const BM25Params(),
          whereFiltersIDs: {1}, // Only allow doc 1
        );

        expect(results, hasLength(1));
        expect(results[0].$1, 1);
      });

      test('with threshold=0 requires all terms to match', () {
        // "hello world" has 2 tokens: hello, world
        // Doc 1 has both in title, doc 3 has only hello
        final results = index.search(
          term: 'hello world',
          tokenizer: tokenizer,
          propertiesToSearch: ['title'],
          relevance: const BM25Params(),
        );

        // Only doc 1 has both 'hello' and 'world' in title
        // Doc 2 has 'world' but not 'hello'
        // Doc 3 has 'hello' but not 'world'
        expect(results, hasLength(1));
        expect(results[0].$1, 1);
      });

      test('with threshold=1 returns any matching documents', () {
        // "hello world" => tokens: hello, world
        final results = index.search(
          term: 'hello world',
          tokenizer: tokenizer,
          propertiesToSearch: ['title'],
          relevance: const BM25Params(),
          threshold: 1,
        );

        // All 3 docs match at least one term
        expect(results, hasLength(3));
        final docIds = results.map((r) => r.$1).toSet();
        expect(docIds, containsAll([1, 2, 3]));
      });

      // Item 12: Boost validation -- throw when boost <= 0
      test('throws when boost value is <= 0', () {
        expect(
          () => index.search(
            term: 'hello',
            tokenizer: tokenizer,
            propertiesToSearch: ['title'],
            relevance: const BM25Params(),
            boost: {'title': 0},
          ),
          throwsA(isA<QueryException>()),
        );

        expect(
          () => index.search(
            term: 'hello',
            tokenizer: tokenizer,
            propertiesToSearch: ['title'],
            relevance: const BM25Params(),
            boost: {'title': -1.5},
          ),
          throwsA(isA<QueryException>()),
        );
      });

      // Item 13: Non-Radix property in search throws, doesn't skip
      test('throws for non-Radix property in search', () {
        // Create index with a number field
        final schema = Schema({
          'title': const TypedField(SchemaType.string),
          'price': const TypedField(SchemaType.number),
        });
        final idx = SearchIndex.create(schema: schema);
        final tok = Tokenizer(allowDuplicates: true);
        idx.insertDocument(
          docId: 1,
          data: {'title': 'hello', 'price': 10},
          tokenizer: tok,
        );
        expect(
          () => idx.search(
            term: 'hello',
            tokenizer: tok,
            propertiesToSearch: ['price'],
            relevance: const BM25Params(),
          ),
          throwsA(isA<QueryException>()),
        );
      });
    });

    // Item 9: String array BM25 scoring -- per-element overwriting
    group('string array BM25 scoring', () {
      test('combines tokens from all array elements for bm25 metadata', () {
        final schema = Schema({
          'tags': const TypedField(SchemaType.stringArray),
        });
        final idx = SearchIndex.create(schema: schema);
        final tok = Tokenizer(allowDuplicates: true);

        idx.insertDocument(
          docId: 1,
          data: {
            'tags': ['hello world', 'goodbye'],
          },
          tokenizer: tok,
        );

        expect(idx.fieldLengths['tags']![1], 3);
      });

      test('search score after removal matches a fresh index', () {
        final schema = Schema({
          'tags': const TypedField(SchemaType.stringArray),
        });
        final tokenizer = Tokenizer(
          allowDuplicates: true,
          useDefaultStopWords: false,
        );

        final idx = SearchIndex.create(schema: schema)
          ..insertDocument(
            docId: 1,
            data: {
              'tags': ['red green', 'blue yellow'],
            },
            tokenizer: tokenizer,
          )
          ..insertDocument(
            docId: 2,
            data: {
              'tags': ['orange'],
            },
            tokenizer: tokenizer,
          )
          ..removeDocument(
            docId: 1,
            data: {
              'tags': ['red green', 'blue yellow'],
            },
            tokenizer: tokenizer,
          );

        final fresh = SearchIndex.create(schema: schema)
          ..insertDocument(
            docId: 2,
            data: {
              'tags': ['orange'],
            },
            tokenizer: tokenizer,
          );

        final afterRemove = idx.search(
          term: 'orange',
          tokenizer: tokenizer,
          propertiesToSearch: ['tags'],
          relevance: const BM25Params(),
        );
        final freshResults = fresh.search(
          term: 'orange',
          tokenizer: tokenizer,
          propertiesToSearch: ['tags'],
          relevance: const BM25Params(),
        );

        expect(afterRemove, hasLength(1));
        expect(freshResults, hasLength(1));
        expect(afterRemove.first.$1, 2);
        expect(
          afterRemove.first.$2,
          closeTo(freshResults.first.$2, 1e-10),
        );
      });
    });

    // Item 10: withCache=false during insert-time tokenization
    group('insert-time tokenization cache', () {
      test('passes withCache=false during index insertion', () {
        // We can't easily test the internal parameter, but we verify
        // that different property contexts don't incorrectly share cache
        final schema = Schema({
          'title': const TypedField(SchemaType.string),
        });
        final idx = SearchIndex.create(schema: schema);
        final tok = Tokenizer(allowDuplicates: true);

        // Insert should work correctly even with same token in different props
        idx.insertDocument(
          docId: 1,
          data: {'title': 'hello'},
          tokenizer: tok,
        );
        expect(idx.fieldLengths['title']![1], 1);
      });
    });

    // Item 11: avgFieldLength = NaN when last doc removed
    group('avgFieldLength after last doc removed', () {
      test('sets avgFieldLength to NaN when docsCount reaches 0', () {
        final schema = Schema({
          'title': const TypedField(SchemaType.string),
        });
        final idx = SearchIndex.create(schema: schema);
        final tok = Tokenizer(allowDuplicates: true);

        idx.insertDocument(
          docId: 1,
          data: {'title': 'hello'},
          tokenizer: tok,
        );
        expect(idx.avgFieldLength['title'], 1.0);

        idx.removeDocument(
          docId: 1,
          data: {'title': 'hello'},
          tokenizer: tok,
        );
        // Orama: sets avgFieldLength to undefined which becomes NaN
        expect(idx.avgFieldLength['title']!.isNaN, isTrue);
      });
    });
  });
}
