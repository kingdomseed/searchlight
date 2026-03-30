import 'package:searchlight/src/core/exceptions.dart';

/// Query anchoring supported by Searchlight pin conditions.
enum SearchlightPinAnchoring {
  /// Matches when the query contains the configured pattern.
  contains,
}

/// A single query-matching condition for a pinning rule.
final class SearchlightPinCondition {
  /// Creates a pin condition.
  const SearchlightPinCondition({
    required this.anchoring,
    required this.pattern,
  });

  /// Creates a contains-style query match.
  const SearchlightPinCondition.contains(this.pattern)
      : anchoring = SearchlightPinAnchoring.contains;

  /// Restores a condition from persisted JSON-compatible data.
  factory SearchlightPinCondition.fromJson(Map<String, Object?> json) {
    final anchoringName = json['anchoring'];
    final pattern = json['pattern'];
    if (anchoringName is! String || pattern is! String) {
      throw const SerializationException('Invalid pinning condition payload.');
    }

    final anchoring = SearchlightPinAnchoring.values.firstWhere(
      (value) => value.name == anchoringName,
      orElse: () => throw SerializationException(
        'Unknown pinning anchoring: $anchoringName',
      ),
    );

    return SearchlightPinCondition(
      anchoring: anchoring,
      pattern: pattern,
    );
  }

  /// The query anchoring strategy.
  final SearchlightPinAnchoring anchoring;

  /// The raw pattern evaluated against the search term.
  final String pattern;

  /// Serializes this condition to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
        'anchoring': anchoring.name,
        'pattern': pattern,
      };
}

/// A single document promotion within a pinning consequence.
final class SearchlightPinPromotion {
  /// Creates a promotion rule for [docId] at [position].
  const SearchlightPinPromotion({
    required this.docId,
    required this.position,
  });

  /// Restores a promotion from persisted JSON-compatible data.
  factory SearchlightPinPromotion.fromJson(Map<String, Object?> json) {
    final docId = json['docId'];
    final position = json['position'];
    if (docId is! String || position is! int) {
      throw const SerializationException('Invalid pinning promotion payload.');
    }

    return SearchlightPinPromotion(
      docId: docId,
      position: position,
    );
  }

  /// The external document ID to promote.
  final String docId;

  /// The zero-based target position in the result set.
  final int position;

  /// Serializes this promotion to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
        'docId': docId,
        'position': position,
      };
}

/// The effect applied when a pinning rule matches a query.
final class SearchlightPinConsequence {
  /// Creates a consequence with the provided promotions.
  const SearchlightPinConsequence({
    required this.promote,
  });

  /// Restores a consequence from persisted JSON-compatible data.
  factory SearchlightPinConsequence.fromJson(Map<String, Object?> json) {
    final promote = json['promote'];
    if (promote is! List) {
      throw const SerializationException(
        'Invalid pinning consequence payload.',
      );
    }

    return SearchlightPinConsequence(
      promote: [
        for (final item in promote)
          SearchlightPinPromotion.fromJson(_asObjectMap(item)),
      ],
    );
  }

  /// Promotions to apply when the rule matches.
  final List<SearchlightPinPromotion> promote;

  /// Serializes this consequence to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
        'promote': [
          for (final promotion in promote) promotion.toJson(),
        ],
      };
}

/// A complete result-pinning rule.
final class SearchlightPinRule {
  /// Creates a pinning rule.
  const SearchlightPinRule({
    required this.id,
    required this.conditions,
    required this.consequence,
  });

  /// Restores a rule from persisted JSON-compatible data.
  factory SearchlightPinRule.fromJson(
    String id,
    Map<String, Object?> json,
  ) {
    final conditions = json['conditions'];
    final consequence = json['consequence'];
    if (conditions is! List || consequence is! Map) {
      throw const SerializationException('Invalid pinning rule payload.');
    }

    return SearchlightPinRule(
      id: id,
      conditions: [
        for (final item in conditions)
          SearchlightPinCondition.fromJson(_asObjectMap(item)),
      ],
      consequence: SearchlightPinConsequence.fromJson(
        Map<String, Object?>.from(consequence),
      ),
    );
  }

  /// Stable rule identifier.
  final String id;

  /// Conditions that must all match for the rule to apply.
  final List<SearchlightPinCondition> conditions;

  /// Promotions to apply when the rule matches.
  final SearchlightPinConsequence consequence;

  /// Serializes this rule body to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
        'conditions': [
          for (final condition in conditions) condition.toJson(),
        ],
        'consequence': consequence.toJson(),
      };
}

/// Public contract for Searchlight pinning stores.
abstract interface class SearchlightPinningStore {
  /// Inserts a new pinning [rule].
  ///
  /// Returns `false` when a rule with the same ID already exists.
  bool insertPin(SearchlightPinRule rule);

  /// Updates an existing pinning [rule].
  ///
  /// Returns `false` when the target rule does not exist.
  bool updatePin(SearchlightPinRule rule);

  /// Deletes the rule identified by [pinId].
  bool deletePin(String pinId);

  /// Returns the rule identified by [pinId], if present.
  SearchlightPinRule? getPin(String pinId);

  /// Returns all rules in store-defined order.
  List<SearchlightPinRule> getAllPins();

  /// Serializes the store payload as `[id, rule]` tuples.
  List<Object?> save();

  /// Restores the exact persisted rule set.
  void restore(List<SearchlightPinRule> rules);
}

/// Default in-memory pinning implementation used by Searchlight.
final class InMemorySearchlightPinningStore implements SearchlightPinningStore {
  final Map<String, SearchlightPinRule> _rules = {};

  @override
  bool deletePin(String pinId) => _rules.remove(pinId) != null;

  @override
  List<SearchlightPinRule> getAllPins() =>
      _rules.values.toList(growable: false);

  @override
  SearchlightPinRule? getPin(String pinId) => _rules[pinId];

  @override
  bool insertPin(SearchlightPinRule rule) {
    if (_rules.containsKey(rule.id)) {
      return false;
    }
    _rules[rule.id] = rule;
    return true;
  }

  @override
  void restore(List<SearchlightPinRule> rules) {
    _rules
      ..clear()
      ..addEntries(rules.map((rule) => MapEntry(rule.id, rule)));
  }

  @override
  List<Object?> save() => <Object?>[
        for (final rule in _rules.values) [rule.id, rule.toJson()],
      ];

  @override
  bool updatePin(SearchlightPinRule rule) {
    if (!_rules.containsKey(rule.id)) {
      return false;
    }
    _rules[rule.id] = rule;
    return true;
  }
}

Map<String, Object?> _asObjectMap(Object? raw) {
  if (raw is! Map) {
    throw const SerializationException('Invalid pinning payload.');
  }
  return Map<String, Object?>.from(raw);
}
