// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/searchlight.dart';
import 'package:searchlight/src/indexing/index_manager.dart' show TokenScore;
import 'package:searchlight/src/search/facets.dart';
import 'package:test/test.dart';

void main() {
  group('getFacets', () {
    test('string facet returns value counts sorted by count descending', () {
      // Set up a schema with a string category field
      final schema = Schema({
        'title': const TypedField(SchemaType.string),
        'category': const TypedField(SchemaType.string),
      });

      final db = Searchlight.create(schema: schema);
      db
        ..insert({'id': 'doc1', 'title': 'A', 'category': 'electronics'})
        ..insert({'id': 'doc2', 'title': 'B', 'category': 'electronics'})
        ..insert({'id': 'doc3', 'title': 'C', 'category': 'electronics'})
        ..insert({'id': 'doc4', 'title': 'D', 'category': 'books'})
        ..insert({'id': 'doc5', 'title': 'E', 'category': 'books'})
        ..insert({'id': 'doc6', 'title': 'F', 'category': 'toys'});

      // Simulate search results — all 6 docs matched
      final results = <TokenScore>[
        (1, 1.0),
        (2, 0.9),
        (3, 0.8),
        (4, 0.7),
        (5, 0.6),
        (6, 0.5),
      ];

      final facets = getFacets(
        documents: db.documentsForFacets,
        results: results,
        facetsConfig: {
          'category': const FacetConfig(),
        },
        propertiesWithTypes: db.propertiesWithTypes,
      );

      expect(facets, contains('category'));

      final categoryFacet = facets['category']!;
      // 3 distinct values
      expect(categoryFacet.count, 3);

      // Values should be sorted by count descending (default)
      final entries = categoryFacet.values.entries.toList();
      expect(entries[0].key, 'electronics');
      expect(entries[0].value, 3);
      expect(entries[1].key, 'books');
      expect(entries[1].value, 2);
      expect(entries[2].key, 'toys');
      expect(entries[2].value, 1);
    });

    test('string facet with limit returns only top N values', () {
      final schema = Schema({
        'title': const TypedField(SchemaType.string),
        'category': const TypedField(SchemaType.string),
      });

      final db = Searchlight.create(schema: schema);
      db
        ..insert({'id': 'doc1', 'title': 'A', 'category': 'electronics'})
        ..insert({'id': 'doc2', 'title': 'B', 'category': 'electronics'})
        ..insert({'id': 'doc3', 'title': 'C', 'category': 'electronics'})
        ..insert({'id': 'doc4', 'title': 'D', 'category': 'books'})
        ..insert({'id': 'doc5', 'title': 'E', 'category': 'books'})
        ..insert({'id': 'doc6', 'title': 'F', 'category': 'toys'});

      final results = <TokenScore>[
        (1, 1.0),
        (2, 0.9),
        (3, 0.8),
        (4, 0.7),
        (5, 0.6),
        (6, 0.5),
      ];

      final facets = getFacets(
        documents: db.documentsForFacets,
        results: results,
        facetsConfig: {
          'category': const FacetConfig(limit: 2),
        },
        propertiesWithTypes: db.propertiesWithTypes,
      );

      final categoryFacet = facets['category']!;
      // count reflects total distinct values (3), not limited set
      expect(categoryFacet.count, 3);
      // But values map only has top 2
      expect(categoryFacet.values.length, 2);
      expect(categoryFacet.values.containsKey('electronics'), isTrue);
      expect(categoryFacet.values.containsKey('books'), isTrue);
      expect(categoryFacet.values.containsKey('toys'), isFalse);
    });

    test('number facet with ranges counts docs in each range', () {
      final schema = Schema({
        'title': const TypedField(SchemaType.string),
        'price': const TypedField(SchemaType.number),
      });

      final db = Searchlight.create(schema: schema);
      db
        ..insert({'id': 'doc1', 'title': 'A', 'price': 5})
        ..insert({'id': 'doc2', 'title': 'B', 'price': 15})
        ..insert({'id': 'doc3', 'title': 'C', 'price': 25})
        ..insert({'id': 'doc4', 'title': 'D', 'price': 50})
        ..insert({'id': 'doc5', 'title': 'E', 'price': 75});

      final results = <TokenScore>[
        (1, 1.0),
        (2, 0.9),
        (3, 0.8),
        (4, 0.7),
        (5, 0.6),
      ];

      final facets = getFacets(
        documents: db.documentsForFacets,
        results: results,
        facetsConfig: {
          'price': FacetConfig(
            ranges: [
              const NumberFacetRange(from: 0, to: 10),
              const NumberFacetRange(from: 10, to: 30),
              const NumberFacetRange(from: 30, to: 100),
            ],
          ),
        },
        propertiesWithTypes: db.propertiesWithTypes,
      );

      final priceFacet = facets['price']!;
      expect(priceFacet.count, 3); // 3 ranges
      expect(priceFacet.values['0-10'], 1); // doc1 (price=5)
      expect(priceFacet.values['10-30'], 2); // doc2 (15), doc3 (25)
      expect(priceFacet.values['30-100'], 2); // doc4 (50), doc5 (75)
    });

    test('boolean facet counts true vs false', () {
      final schema = Schema({
        'title': const TypedField(SchemaType.string),
        'inStock': const TypedField(SchemaType.boolean),
      });

      final db = Searchlight.create(schema: schema);
      db
        ..insert({'id': 'doc1', 'title': 'A', 'inStock': true})
        ..insert({'id': 'doc2', 'title': 'B', 'inStock': true})
        ..insert({'id': 'doc3', 'title': 'C', 'inStock': true})
        ..insert({'id': 'doc4', 'title': 'D', 'inStock': false})
        ..insert({'id': 'doc5', 'title': 'E', 'inStock': false});

      final results = <TokenScore>[
        (1, 1.0),
        (2, 0.9),
        (3, 0.8),
        (4, 0.7),
        (5, 0.6),
      ];

      final facets = getFacets(
        documents: db.documentsForFacets,
        results: results,
        facetsConfig: {
          'inStock': const FacetConfig(),
        },
        propertiesWithTypes: db.propertiesWithTypes,
      );

      final boolFacet = facets['inStock']!;
      expect(boolFacet.count, 2); // true and false
      expect(boolFacet.values['true'], 3);
      expect(boolFacet.values['false'], 2);
    });
  });

  group('Searchlight.search() with facets', () {
    test('search with facets config returns facets in SearchResult', () {
      final schema = Schema({
        'title': const TypedField(SchemaType.string),
        'category': const TypedField(SchemaType.string),
      });

      final db = Searchlight.create(schema: schema);
      db
        ..insert({'id': 'doc1', 'title': 'hello world', 'category': 'tech'})
        ..insert({'id': 'doc2', 'title': 'hello dart', 'category': 'tech'})
        ..insert(
          {'id': 'doc3', 'title': 'hello flutter', 'category': 'mobile'},
        );

      final result = db.search(
        term: 'hello',
        facets: {'category': const FacetConfig(limit: 10)},
      );

      expect(result.count, 3);
      expect(result.facets, isNotNull);
      expect(result.facets!.containsKey('category'), isTrue);

      final categoryFacet = result.facets!['category']!;
      expect(categoryFacet.count, 2); // tech and mobile
      expect(categoryFacet.values['tech'], 2);
      expect(categoryFacet.values['mobile'], 1);
    });
  });
}
