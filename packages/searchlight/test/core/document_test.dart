// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/core/doc_id.dart';
import 'package:searchlight/src/core/document.dart';
import 'package:searchlight/src/core/types.dart';
import 'package:test/test.dart';

void main() {
  group('Document', () {
    test('provides typed accessors', () {
      const doc = Document({'title': 'Hello', 'price': 9.99, 'active': true});
      expect(doc.getString('title'), 'Hello');
      expect(doc.getNumber('price'), 9.99);
      expect(doc.getBool('active'), true);
    });

    test('tryGet returns null for missing fields', () {
      const doc = Document({'title': 'Hello'});
      expect(doc.tryGetString('missing'), isNull);
      expect(doc.tryGetNumber('missing'), isNull);
      expect(doc.tryGetBool('missing'), isNull);
    });

    test('getStringList returns list of strings', () {
      const doc = Document({
        'tags': ['a', 'b', 'c'],
      });
      expect(doc.getStringList('tags'), ['a', 'b', 'c']);
    });

    test('getNested returns nested Document', () {
      const doc = Document({
        'meta': {'rating': 4.5, 'author': 'Alice'},
      });
      final nested = doc.getNested('meta');
      expect(nested.getNumber('rating'), 4.5);
      expect(nested.getString('author'), 'Alice');
    });

    test('toMap returns unmodifiable copy', () {
      const doc = Document({'title': 'Hello'});
      final map = doc.toMap();
      expect(map['title'], 'Hello');
      expect(() => (map as Map)['new'] = 'value', throwsUnsupportedError);
    });

    test('getString throws on wrong type', () {
      const doc = Document({'price': 9.99});
      expect(() => doc.getString('price'), throwsA(isA<TypeError>()));
    });

    test('getString throws on missing key', () {
      const doc = Document({});
      expect(() => doc.getString('missing'), throwsA(anything));
    });
  });

  group('GeoPoint', () {
    test('holds lat and lon', () {
      const point = GeoPoint(lat: 40.7128, lon: -74.006);
      expect(point.lat, 40.7128);
      expect(point.lon, -74.006);
    });

    test('equality', () {
      const a = GeoPoint(lat: 40.7128, lon: -74.006);
      const b = GeoPoint(lat: 40.7128, lon: -74.006);
      expect(a, equals(b));
    });
  });

  group('SearchResult', () {
    test('holds hits, count, and elapsed', () {
      const result = SearchResult(
        hits: [],
        count: 0,
        elapsed: Duration.zero,
      );
      expect(result.hits, isEmpty);
      expect(result.count, 0);
      expect(result.facets, isNull);
      expect(result.groups, isNull);
    });
  });

  group('SearchHit', () {
    test('holds id, score, and document', () {
      const hit = SearchHit(
        id: DocId(1),
        score: 0.95,
        document: Document({'title': 'Test'}),
      );
      expect(hit.id, const DocId(1));
      expect(hit.score, 0.95);
      expect(hit.document.getString('title'), 'Test');
    });
  });

  group('FacetValue', () {
    test('holds value and count', () {
      const fv = FacetValue(value: 'electronics', count: 42);
      expect(fv.value, 'electronics');
      expect(fv.count, 42);
    });
  });

  group('SearchMode', () {
    test('has all three modes', () {
      expect(SearchMode.values, hasLength(3));
      expect(SearchMode.values, contains(SearchMode.matchAll));
      expect(SearchMode.values, contains(SearchMode.matchAny));
      expect(SearchMode.values, contains(SearchMode.prefix));
    });
  });

  group('SortBy', () {
    test('holds field and order', () {
      const sort = SortBy(field: 'price', order: SortOrder.asc);
      expect(sort.field, 'price');
      expect(sort.order, SortOrder.asc);
    });
  });

  group('GroupBy', () {
    test('holds field and limit', () {
      const group = GroupBy(field: 'category', limit: 3);
      expect(group.field, 'category');
      expect(group.limit, 3);
    });
  });

  group('FacetConfig', () {
    test('holds limit', () {
      const config = FacetConfig(limit: 10);
      expect(config.limit, 10);
    });
  });

  group('BatchResult', () {
    test('reports success and errors', () {
      const result = BatchResult(
        insertedIds: [DocId(1), DocId(2)],
        errors: [BatchError(index: 2, error: 'Invalid field')],
      );
      expect(result.insertedIds, hasLength(2));
      expect(result.errors, hasLength(1));
      expect(result.hasErrors, isTrue);
    });

    test('hasErrors is false when no errors', () {
      const result = BatchResult(
        insertedIds: [DocId(1)],
        errors: [],
      );
      expect(result.hasErrors, isFalse);
    });
  });
}
