// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;

import 'package:searchlight/src/core/types.dart';

/// Units for distance conversion.
enum DistanceUnit {
  /// Centimeters.
  cm,

  /// Meters.
  m,

  /// Kilometers.
  km,

  /// Miles.
  mi,

  /// Yards.
  yd,

  /// Feet.
  ft,
}

/// Number of dimensions for KD-tree (lon, lat).
const int _k = 2;

/// Earth radius in meters.
const _earthRadius = 6371e3;

/// A search result from a BKD tree geo-query.
class GeoSearchResult {
  /// Creates a [GeoSearchResult] with the given [point] and [docIDs].
  const GeoSearchResult({required this.point, required this.docIDs});

  /// The geographic point.
  final GeoPoint point;

  /// The document IDs at this point.
  final List<int> docIDs;
}

/// A node in a BKD tree (KD-tree for 2D geographic points).
class BKDNode {
  /// Creates a [BKDNode] with the given [point] and optional [docIDs].
  BKDNode(this.point, [List<int>? docIDs])
      : docIDs = docIDs != null ? Set<int>.of(docIDs) : <int>{};

  /// Deserializes a node and its subtree from a JSON-compatible map.
  factory BKDNode.fromJson(Map<String, dynamic> json, [BKDNode? parent]) {
    final pointMap = json['point'] as Map<String, dynamic>;
    final point = GeoPoint(
      lat: (pointMap['lat'] as num).toDouble(),
      lon: (pointMap['lon'] as num).toDouble(),
    );
    final docIDs = (json['docIDs'] as List).cast<int>();

    final node = BKDNode(point, docIDs)..parent = parent;

    if (json['left'] != null) {
      node.left = BKDNode.fromJson(
        json['left'] as Map<String, dynamic>,
        node,
      );
    }
    if (json['right'] != null) {
      node.right = BKDNode.fromJson(
        json['right'] as Map<String, dynamic>,
        node,
      );
    }

    return node;
  }

  /// The geographic point stored at this node.
  final GeoPoint point;

  /// Document IDs associated with this point.
  final Set<int> docIDs;

  /// Left child node.
  BKDNode? left;

  /// Right child node.
  BKDNode? right;

  /// Parent node.
  BKDNode? parent;

  /// Serializes this node and its subtree to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'point': {'lon': point.lon, 'lat': point.lat},
      'docIDs': docIDs.toList(),
      'left': left?.toJson(),
      'right': right?.toJson(),
    };
  }
}

/// A KD-tree specialized for 2D geographic points (lat/lon).
///
/// Matches Orama's BKDTree implementation.
class BKDTree {
  /// Creates an empty [BKDTree].
  BKDTree();

  /// Deserializes a tree from a JSON-compatible map.
  factory BKDTree.fromJson(Map<String, dynamic> json) {
    final tree = BKDTree();
    if (json['root'] != null) {
      tree
        ..root = BKDNode.fromJson(json['root'] as Map<String, dynamic>)
        .._buildNodeMap(tree.root);
    }
    return tree;
  }

  /// The root node of the tree.
  BKDNode? root;

  /// Map from point key to node for O(1) lookup.
  final Map<String, BKDNode> _nodeMap = {};

  String _getPointKey(GeoPoint point) => '${point.lon},${point.lat}';

  /// Inserts a [point] with associated [docIDs] into the tree.
  void insert(GeoPoint point, List<int> docIDs) {
    final pointKey = _getPointKey(point);
    final existingNode = _nodeMap[pointKey];
    if (existingNode != null) {
      existingNode.docIDs.addAll(docIDs);
      return;
    }

    final newNode = BKDNode(point, docIDs);
    _nodeMap[pointKey] = newNode;

    if (root == null) {
      root = newNode;
      return;
    }

    var node = root!;
    var depth = 0;

    while (true) {
      final axis = depth % _k;

      if (axis == 0) {
        if (point.lon < node.point.lon) {
          if (node.left == null) {
            node.left = newNode;
            newNode.parent = node;
            return;
          }
          node = node.left!;
        } else {
          if (node.right == null) {
            node.right = newNode;
            newNode.parent = node;
            return;
          }
          node = node.right!;
        }
      } else {
        if (point.lat < node.point.lat) {
          if (node.left == null) {
            node.left = newNode;
            newNode.parent = node;
            return;
          }
          node = node.left!;
        } else {
          if (node.right == null) {
            node.right = newNode;
            newNode.parent = node;
            return;
          }
          node = node.right!;
        }
      }

      depth++;
    }
  }

  /// Returns whether the tree contains a node at the given [point].
  bool contains(GeoPoint point) {
    final pointKey = _getPointKey(point);
    return _nodeMap.containsKey(pointKey);
  }

  /// Removes a specific [docID] from the node at [point].
  ///
  /// If the node has no remaining docIDs after removal, the node is deleted
  /// from the tree.
  void removeDocByID(GeoPoint point, int docID) {
    final pointKey = _getPointKey(point);
    final node = _nodeMap[pointKey];
    if (node != null) {
      node.docIDs.remove(docID);
      if (node.docIDs.isEmpty) {
        _nodeMap.remove(pointKey);
        _deleteNode(node);
      }
    }
  }

  void _deleteNode(BKDNode node) {
    final parent = node.parent;
    final child = node.left ?? node.right;
    if (child != null) {
      child.parent = parent;
    }

    if (parent != null) {
      if (identical(parent.left, node)) {
        parent.left = child;
      } else if (identical(parent.right, node)) {
        parent.right = child;
      }
    } else {
      root = child;
      if (root != null) {
        root!.parent = null;
      }
    }
  }

  /// Returns the document IDs for the node at [point], or null if not found.
  List<int>? getDocIDsByCoordinates(GeoPoint point) {
    final pointKey = _getPointKey(point);
    final node = _nodeMap[pointKey];
    if (node != null) {
      return node.docIDs.toList();
    }
    return null;
  }

  /// Searches for all points within [radius] meters of [center].
  ///
  /// When [inclusive] is true (default), returns points where
  /// distance <= radius.
  /// When [inclusive] is false, returns points where distance > radius.
  /// Results are sorted by [sort] ('asc' or 'desc'), or unsorted if null.
  /// When [highPrecision] is true, uses Vincenty distance instead of Haversine.
  List<GeoSearchResult> searchByRadius(
    GeoPoint center,
    double radius, {
    bool inclusive = true,
    SortOrder? sort = SortOrder.asc,
    bool highPrecision = false,
  }) {
    final distanceFn = highPrecision ? vincentyDistance : haversineDistance;
    final stack = <({BKDNode? node, int depth})>[
      (node: root, depth: 0),
    ];
    final result = <GeoSearchResult>[];

    while (stack.isNotEmpty) {
      final (:node, :depth) = stack.removeLast();
      if (node == null) continue;

      final dist = distanceFn(center, node.point);

      if (inclusive ? dist <= radius : dist > radius) {
        result.add(
          GeoSearchResult(
            point: node.point,
            docIDs: node.docIDs.toList(),
          ),
        );
      }

      if (node.left != null) {
        stack.add((node: node.left, depth: depth + 1));
      }
      if (node.right != null) {
        stack.add((node: node.right, depth: depth + 1));
      }
    }

    if (sort != null) {
      result.sort((a, b) {
        final distA = distanceFn(center, a.point);
        final distB = distanceFn(center, b.point);
        return sort == SortOrder.asc
            ? distA.compareTo(distB)
            : distB.compareTo(distA);
      });
    }

    return result;
  }

  /// Serializes the tree to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'root': root?.toJson(),
    };
  }

  void _buildNodeMap(BKDNode? node) {
    if (node == null) return;
    final pointKey = _getPointKey(node.point);
    _nodeMap[pointKey] = node;
    _buildNodeMap(node.left);
    _buildNodeMap(node.right);
  }

  /// Searches for all points inside (or outside) a [polygon].
  ///
  /// The polygon is a list of vertices defining the boundary.
  /// When [inclusive] is true (default), returns points inside the polygon.
  /// When [inclusive] is false, returns points outside the polygon.
  /// Results are sorted by [sort] relative to the polygon centroid, or unsorted
  /// if null.
  List<GeoSearchResult> searchByPolygon(
    List<GeoPoint> polygon, {
    bool inclusive = true,
    SortOrder? sort,
    bool highPrecision = false,
  }) {
    final stack = <({BKDNode? node, int depth})>[
      (node: root, depth: 0),
    ];
    final result = <GeoSearchResult>[];

    while (stack.isNotEmpty) {
      final (:node, :depth) = stack.removeLast();
      if (node == null) continue;

      if (node.left != null) {
        stack.add((node: node.left, depth: depth + 1));
      }
      if (node.right != null) {
        stack.add((node: node.right, depth: depth + 1));
      }

      final isInside = isPointInPolygon(polygon, node.point);

      if ((isInside && inclusive) || (!isInside && !inclusive)) {
        result.add(
          GeoSearchResult(
            point: node.point,
            docIDs: node.docIDs.toList(),
          ),
        );
      }
    }

    if (sort != null) {
      final centroid = calculatePolygonCentroid(polygon);
      final distanceFn = highPrecision ? vincentyDistance : haversineDistance;
      result.sort((a, b) {
        final distA = distanceFn(centroid, a.point);
        final distB = distanceFn(centroid, b.point);
        return sort == SortOrder.asc
            ? distA.compareTo(distB)
            : distB.compareTo(distA);
      });
    }

    return result;
  }

  /// Returns true if [point] is inside the [polygon] using ray casting.
  static bool isPointInPolygon(List<GeoPoint> polygon, GeoPoint point) {
    var isInside = false;
    final x = point.lon;
    final y = point.lat;
    final polygonLength = polygon.length;
    for (var i = 0, j = polygonLength - 1; i < polygonLength; j = i++) {
      final xi = polygon[i].lon;
      final yi = polygon[i].lat;
      final xj = polygon[j].lon;
      final yj = polygon[j].lat;

      final intersect =
          (yi > y) != (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi;
      if (intersect) isInside = !isInside;
    }

    return isInside;
  }

  /// Calculates the centroid of a [polygon].
  static GeoPoint calculatePolygonCentroid(List<GeoPoint> polygon) {
    var totalArea = 0.0;
    var centroidX = 0.0;
    var centroidY = 0.0;

    final polygonLength = polygon.length;
    for (var i = 0, j = polygonLength - 1; i < polygonLength; j = i++) {
      final xi = polygon[i].lon;
      final yi = polygon[i].lat;
      final xj = polygon[j].lon;
      final yj = polygon[j].lat;

      final areaSegment = xi * yj - xj * yi;
      totalArea += areaSegment;

      centroidX += (xi + xj) * areaSegment;
      centroidY += (yi + yj) * areaSegment;
    }

    totalArea /= 2;
    final centroidCoordinate = 6 * totalArea;

    centroidX /= centroidCoordinate;
    centroidY /= centroidCoordinate;

    return GeoPoint(lon: centroidX, lat: centroidY);
  }

  /// Converts a [distance] in the given [unit] to meters.
  static double convertDistanceToMeters(double distance, DistanceUnit unit) {
    switch (unit) {
      case DistanceUnit.cm:
        return distance / 100;
      case DistanceUnit.m:
        return distance;
      case DistanceUnit.km:
        return distance * 1000;
      case DistanceUnit.mi:
        return distance * 1609.344;
      case DistanceUnit.yd:
        return distance * 0.9144;
      case DistanceUnit.ft:
        return distance * 0.3048;
    }
  }

  /// Computes the Haversine (great-circle) distance between two points in
  /// meters.
  ///
  /// Uses Earth radius of 6,371,000 meters.
  static double haversineDistance(GeoPoint coord1, GeoPoint coord2) {
    const p = math.pi / 180;
    final lat1 = coord1.lat * p;
    final lat2 = coord2.lat * p;
    final deltaLat = (coord2.lat - coord1.lat) * p;
    final deltaLon = (coord2.lon - coord1.lon) * p;

    final a = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLon / 2) *
            math.sin(deltaLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return _earthRadius * c;
  }

  /// Computes the Vincenty (ellipsoidal) distance between two points in meters.
  ///
  /// Uses WGS84 ellipsoid constants:
  /// - Semi-major axis: 6,378,137 m
  /// - Flattening: 1/298.257223563
  /// - Iteration limit: 1000
  /// - Convergence threshold: 1e-12
  static double vincentyDistance(GeoPoint coord1, GeoPoint coord2) {
    const a = 6378137.0;
    const f = 1 / 298.257223563;
    const b = (1 - f) * a;

    const p = math.pi / 180;
    final lat1 = coord1.lat * p;
    final lat2 = coord2.lat * p;
    final deltaLon = (coord2.lon - coord1.lon) * p;

    final u1 = math.atan((1 - f) * math.tan(lat1));
    final u2 = math.atan((1 - f) * math.tan(lat2));

    final sinU1 = math.sin(u1);
    final cosU1 = math.cos(u1);
    final sinU2 = math.sin(u2);
    final cosU2 = math.cos(u2);

    var lambda = deltaLon;
    double prevLambda;
    var iterationLimit = 1000;
    double sinSigma = 0;
    double cosSigma = 0;
    double sigma = 0;
    double sinAlpha = 0;
    double cos2Alpha = 0;
    double cos2SigmaM = 0;

    do {
      final sinLambda = math.sin(lambda);
      final cosLambda = math.cos(lambda);

      sinSigma = math.sqrt(
        cosU2 * sinLambda * (cosU2 * sinLambda) +
            (cosU1 * sinU2 - sinU1 * cosU2 * cosLambda) *
                (cosU1 * sinU2 - sinU1 * cosU2 * cosLambda),
      );

      if (sinSigma == 0) return 0; // co-incident points

      cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLambda;
      sigma = math.atan2(sinSigma, cosSigma);

      sinAlpha = (cosU1 * cosU2 * sinLambda) / sinSigma;
      cos2Alpha = 1 - sinAlpha * sinAlpha;
      cos2SigmaM = cosSigma - (2 * sinU1 * sinU2) / cos2Alpha;

      if (cos2SigmaM.isNaN) cos2SigmaM = 0;

      final bigC = (f / 16) * cos2Alpha * (4 + f * (4 - 3 * cos2Alpha));
      prevLambda = lambda;
      lambda = deltaLon +
          (1 - bigC) *
              f *
              sinAlpha *
              (sigma +
                  bigC *
                      sinSigma *
                      (cos2SigmaM +
                          bigC *
                              cosSigma *
                              (-1 + 2 * cos2SigmaM * cos2SigmaM)));
    } while ((lambda - prevLambda).abs() > 1e-12 && --iterationLimit > 0);

    if (iterationLimit == 0) {
      return double.nan;
    }

    final uSquared = (cos2Alpha * (a * a - b * b)) / (b * b);
    final bigA = 1 +
        (uSquared / 16384) *
            (4096 + uSquared * (-768 + uSquared * (320 - 175 * uSquared)));
    final bigB = (uSquared / 1024) *
        (256 + uSquared * (-128 + uSquared * (74 - 47 * uSquared)));

    final deltaSigma = bigB *
        sinSigma *
        (cos2SigmaM +
            (bigB / 4) *
                (cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM) -
                    (bigB / 6) *
                        cos2SigmaM *
                        (-3 + 4 * sinSigma * sinSigma) *
                        (-3 + 4 * cos2SigmaM * cos2SigmaM)));

    return b * bigA * (sigma - deltaSigma);
  }
}
