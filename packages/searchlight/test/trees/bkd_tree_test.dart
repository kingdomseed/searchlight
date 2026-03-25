// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/core/types.dart';
import 'package:searchlight/src/trees/bkd_tree.dart';
import 'package:test/test.dart';

void main() {
  group('BKDTree', () {
    test('insert single point with docID, tree is not empty', () {
      final tree = BKDTree();
      final point = GeoPoint(lat: 40.7128, lon: -74.0060);
      tree.insert(point, [1]);
      expect(tree.root, isNotNull);
      expect(tree.contains(point), isTrue);
    });

    test('insert multiple points, all findable', () {
      final tree = BKDTree();
      final nyc = GeoPoint(lat: 40.7128, lon: -74.0060);
      final la = GeoPoint(lat: 34.0522, lon: -118.2437);
      final chicago = GeoPoint(lat: 41.8781, lon: -87.6298);

      tree.insert(nyc, [1]);
      tree.insert(la, [2]);
      tree.insert(chicago, [3]);

      expect(tree.contains(nyc), isTrue);
      expect(tree.contains(la), isTrue);
      expect(tree.contains(chicago), isTrue);

      expect(tree.getDocIDsByCoordinates(nyc), [1]);
      expect(tree.getDocIDsByCoordinates(la), [2]);
      expect(tree.getDocIDsByCoordinates(chicago), [3]);
    });

    test('searchByRadius finds points within radius', () {
      final tree = BKDTree();
      final nyc = GeoPoint(lat: 40.7128, lon: -74.0060);
      final la = GeoPoint(lat: 34.0522, lon: -118.2437);

      tree.insert(nyc, [1]);
      tree.insert(la, [2]);

      // Search 100km around NYC — should find only NYC
      final results = tree.searchByRadius(nyc, 100000);
      expect(results.length, 1);
      expect(results.first.point, nyc);
      expect(results.first.docIDs, [1]);
    });

    test('searchByRadius with inclusive=true includes boundary points', () {
      final tree = BKDTree();
      final origin = GeoPoint(lat: 0.0, lon: 0.0);
      final target = GeoPoint(lat: 1.0, lon: 0.0);

      tree.insert(origin, [1]);
      tree.insert(target, [2]);

      // Compute exact distance so target is on the boundary
      final exactDist = BKDTree.haversineDistance(origin, target);

      // inclusive=true (default): boundary point IS included
      final inclusive = tree.searchByRadius(origin, exactDist);
      expect(inclusive.any((r) => r.point == target), isTrue);

      // inclusive=false: boundary point is NOT included (only outside)
      final exclusive =
          tree.searchByRadius(origin, exactDist, inclusive: false);
      expect(exclusive.any((r) => r.point == target), isFalse);
    });

    test('searchByRadius returns empty for no matches', () {
      final tree = BKDTree();
      final nyc = GeoPoint(lat: 40.7128, lon: -74.0060);
      final tokyo = GeoPoint(lat: 35.6762, lon: 139.6503);

      tree.insert(tokyo, [1]);

      // Search 100km around NYC — Tokyo is ~10,800km away
      final results = tree.searchByRadius(nyc, 100000);
      expect(results, isEmpty);
    });

    test('haversineDistance between known coordinates matches expected', () {
      final nyc = GeoPoint(lat: 40.7128, lon: -74.0060);
      final la = GeoPoint(lat: 34.0522, lon: -118.2437);

      final distance = BKDTree.haversineDistance(nyc, la);

      // NYC to LA is approximately 3,944 km
      // Allow 1% tolerance
      expect(distance, closeTo(3944000, 40000));
    });

    test('vincentyDistance between known coordinates matches expected', () {
      final nyc = GeoPoint(lat: 40.7128, lon: -74.0060);
      final la = GeoPoint(lat: 34.0522, lon: -118.2437);

      final distance = BKDTree.vincentyDistance(nyc, la);

      // Vincenty should also be ~3,944 km for NYC-LA, slightly different
      // from Haversine due to ellipsoidal model. Allow 1% tolerance.
      expect(distance, closeTo(3944000, 40000));

      // Vincenty for co-incident points should be 0
      final same = BKDTree.vincentyDistance(nyc, nyc);
      expect(same, 0.0);
    });

    test('searchByPolygon finds points inside polygon', () {
      final tree = BKDTree();

      // Points
      final nyc = GeoPoint(lat: 40.7128, lon: -74.0060);
      final philly = GeoPoint(lat: 39.9526, lon: -75.1652);

      tree.insert(nyc, [1]);
      tree.insert(philly, [2]);

      // Polygon around the US Northeast that includes NYC and Philly
      final polygon = [
        GeoPoint(lat: 42.0, lon: -80.0),
        GeoPoint(lat: 42.0, lon: -70.0),
        GeoPoint(lat: 38.0, lon: -70.0),
        GeoPoint(lat: 38.0, lon: -80.0),
      ];

      final results = tree.searchByPolygon(polygon);
      expect(results.length, 2);
      final points = results.map((r) => r.point).toSet();
      expect(points.contains(nyc), isTrue);
      expect(points.contains(philly), isTrue);
    });

    test('searchByPolygon excludes points outside polygon', () {
      final tree = BKDTree();

      final nyc = GeoPoint(lat: 40.7128, lon: -74.0060);
      final la = GeoPoint(lat: 34.0522, lon: -118.2437);

      tree.insert(nyc, [1]);
      tree.insert(la, [2]);

      // Polygon around the US Northeast — LA is far outside
      final polygon = [
        GeoPoint(lat: 42.0, lon: -80.0),
        GeoPoint(lat: 42.0, lon: -70.0),
        GeoPoint(lat: 38.0, lon: -70.0),
        GeoPoint(lat: 38.0, lon: -80.0),
      ];

      final results = tree.searchByPolygon(polygon);
      expect(results.length, 1);
      expect(results.first.point, nyc);

      // With inclusive=false, only LA (outside) should be returned
      final outside = tree.searchByPolygon(polygon, inclusive: false);
      expect(outside.length, 1);
      expect(outside.first.point, la);
    });

    test('removeDocByID removes specific docID from point', () {
      final tree = BKDTree();
      final point = GeoPoint(lat: 40.7128, lon: -74.0060);

      tree.insert(point, [1, 2, 3]);

      // Remove one docID
      tree.removeDocByID(point, 2);
      expect(tree.getDocIDsByCoordinates(point), unorderedEquals([1, 3]));

      // Remove remaining docIDs — node should be removed
      tree.removeDocByID(point, 1);
      tree.removeDocByID(point, 3);
      expect(tree.contains(point), isFalse);
      expect(tree.getDocIDsByCoordinates(point), isNull);
    });

    test('convertDistanceToMeters converts km, mi, etc correctly', () {
      // cm -> meters
      expect(BKDTree.convertDistanceToMeters(100, DistanceUnit.cm), 1.0);

      // m -> meters (identity)
      expect(BKDTree.convertDistanceToMeters(1, DistanceUnit.m), 1.0);

      // km -> meters
      expect(BKDTree.convertDistanceToMeters(1, DistanceUnit.km), 1000.0);

      // mi -> meters
      expect(
        BKDTree.convertDistanceToMeters(1, DistanceUnit.mi),
        closeTo(1609.344, 0.001),
      );

      // yd -> meters
      expect(
        BKDTree.convertDistanceToMeters(1, DistanceUnit.yd),
        closeTo(0.9144, 0.0001),
      );

      // ft -> meters
      expect(
        BKDTree.convertDistanceToMeters(1, DistanceUnit.ft),
        closeTo(0.3048, 0.0001),
      );
    });

    test('toJson/fromJson round-trip preserves tree structure', () {
      final tree = BKDTree();
      final nyc = GeoPoint(lat: 40.7128, lon: -74.0060);
      final la = GeoPoint(lat: 34.0522, lon: -118.2437);
      final chicago = GeoPoint(lat: 41.8781, lon: -87.6298);

      tree.insert(nyc, [1]);
      tree.insert(la, [2]);
      tree.insert(chicago, [3, 4]);

      final json = tree.toJson();
      final restored = BKDTree.fromJson(json);

      expect(restored.contains(nyc), isTrue);
      expect(restored.contains(la), isTrue);
      expect(restored.contains(chicago), isTrue);

      expect(restored.getDocIDsByCoordinates(nyc), [1]);
      expect(restored.getDocIDsByCoordinates(la), [2]);
      expect(
        restored.getDocIDsByCoordinates(chicago),
        unorderedEquals([3, 4]),
      );

      // Search should still work after round-trip
      final results = restored.searchByRadius(nyc, 100000);
      expect(results.length, 1);
      expect(results.first.point, nyc);
    });
  });
}
