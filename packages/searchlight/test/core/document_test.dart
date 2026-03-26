// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

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

    test('toMap is only shallowly unmodifiable', () {
      final nestedData = <String, Object?>{'rating': 4.5};
      final doc = Document({'meta': nestedData});

      final map = doc.toMap();
      final nested = map['meta']! as Map<String, Object?>;
      nested['rating'] = 5.0;

      expect((doc.toMap()['meta']! as Map<String, Object?>)['rating'], 5.0);
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
    test('holds String id, score, and document', () {
      const hit = SearchHit(
        id: 'doc-1',
        score: 0.95,
        document: Document({'title': 'Test'}),
      );
      expect(hit.id, 'doc-1');
      expect(hit.score, 0.95);
      expect(hit.document.getString('title'), 'Test');
    });
  });

  group('FacetResult', () {
    test('holds count and values', () {
      const fr = FacetResult(
        count: 3,
        values: {'electronics': 42, 'books': 10, 'toys': 5},
      );
      expect(fr.count, 3);
      expect(fr.values['electronics'], 42);
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
      expect(group.effectiveProperties, ['category']);
      expect(group.limit, 3);
    });

    test('multi-property constructor holds properties', () {
      const group = GroupBy.properties(
        properties: ['category', 'status'],
        limit: 5,
      );
      expect(group.effectiveProperties, ['category', 'status']);
      expect(group.limit, 5);
    });
  });

  group('FacetConfig', () {
    test('holds limit', () {
      const config = FacetConfig();
      expect(config.limit, 10);
    });
  });
}
