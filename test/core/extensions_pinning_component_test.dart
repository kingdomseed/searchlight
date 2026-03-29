import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

final class _RecordingPinningStore implements SearchlightPinningStore {
  final Map<String, SearchlightPinRule> _rules = {};

  int getAllPinsCalls = 0;
  int saveCalls = 0;

  @override
  bool deletePin(String pinId) => _rules.remove(pinId) != null;

  @override
  List<SearchlightPinRule> getAllPins() {
    getAllPinsCalls++;
    return _rules.values.toList(growable: false);
  }

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
  List<Object?> save() {
    saveCalls++;
    return [
      for (final rule in _rules.values)
        [
          rule.id,
          {
            'conditions': [
              for (final condition in rule.conditions)
                {
                  'anchoring': condition.anchoring.name,
                  'pattern': condition.pattern,
                },
            ],
            'consequence': {
              'promote': [
                for (final promotion in rule.consequence.promote)
                  {
                    'docId': promotion.docId,
                    'position': promotion.position,
                  },
              ],
            },
          },
        ],
    ];
  }

  @override
  bool updatePin(SearchlightPinRule rule) {
    if (!_rules.containsKey(rule.id)) {
      return false;
    }
    _rules[rule.id] = rule;
    return true;
  }
}

void main() {
  group('extension pinning component', () {
    test('search applies pinning before pagination, facets, and groups', () {
      final store = _RecordingPinningStore();
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'category': const TypedField(SchemaType.string),
        }),
        components: SearchlightComponents(
          pinning: SearchlightPinningComponent(
            id: 'test.pinning.recording',
            create: () => store,
          ),
        ),
      )
        ..insert({
          'id': 'doc-1',
          'title': 'Red Shirt',
          'category': 'tops',
        })
        ..insert({
          'id': 'doc-2',
          'title': 'Blue Jeans',
          'category': 'bottoms',
        })
        ..insert({
          'id': 'doc-3',
          'title': 'Green Hat',
          'category': 'accessories',
        });
      addTearDown(db.dispose);

      expect(
        db.insertPin(
          const SearchlightPinRule(
            id: 'pin-shirt',
            conditions: [
              SearchlightPinCondition.contains('shirt'),
            ],
            consequence: SearchlightPinConsequence(
              promote: [
                SearchlightPinPromotion(docId: 'doc-3', position: 0),
              ],
            ),
          ),
        ),
        isTrue,
      );

      final results = db.search(
        term: 'shirt',
        properties: const ['title'],
        limit: 1,
        facets: {
          'category': const FacetConfig(),
        },
        groupBy: const GroupBy(field: 'category', limit: 10),
      );

      expect(results.count, 2);
      expect(results.hits.map((hit) => hit.id), ['doc-3']);
      expect(results.facets?['category']?.values, containsPair('tops', 1));
      expect(
        results.facets?['category']?.values,
        containsPair('accessories', 1),
      );
      expect(
        results.groups?.map((group) => group.values.single),
        containsAll(<Object>['tops', 'accessories']),
      );
      expect(store.getAllPinsCalls, greaterThan(0));
    });

    test('pinning is applied after sort order', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
      )
        ..insert({'id': 'doc-1', 'title': 'Alpha Guide'})
        ..insert({'id': 'doc-2', 'title': 'Beta Guide'})
        ..insert({'id': 'doc-3', 'title': 'Gamma Guide'});
      addTearDown(db.dispose);

      db.insertPin(
        const SearchlightPinRule(
          id: 'pin-a',
          conditions: [
            SearchlightPinCondition.contains('guide'),
          ],
          consequence: SearchlightPinConsequence(
            promote: [
              SearchlightPinPromotion(docId: 'doc-3', position: 0),
            ],
          ),
        ),
      );

      final results = db.search(
        term: 'guide',
        properties: const ['title'],
        sortBy: const SortBy(field: 'title', order: SortOrder.asc),
      );

      expect(
        results.hits.map((hit) => hit.id).toList(),
        ['doc-3', 'doc-1', 'doc-2'],
      );
    });

    test('pinning rules round-trip through JSON restore', () {
      final store = _RecordingPinningStore();
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        components: SearchlightComponents(
          pinning: SearchlightPinningComponent(
            id: 'test.pinning.recording',
            create: () => store,
          ),
        ),
      )
        ..insert({'id': 'doc-1', 'title': 'Red Shirt'})
        ..insert({'id': 'doc-2', 'title': 'Green Hat'});
      addTearDown(db.dispose);

      db.insertPin(
        const SearchlightPinRule(
          id: 'pin-shirt',
          conditions: [
            SearchlightPinCondition.contains('shirt'),
          ],
          consequence: SearchlightPinConsequence(
            promote: [
              SearchlightPinPromotion(docId: 'doc-2', position: 0),
            ],
          ),
        ),
      );

      final json = db.toJson();

      expect(store.saveCalls, 1);
      expect(json['pinning'], isNotEmpty);

      final restored = Searchlight.fromJson(
        json,
        components: const SearchlightComponents(
          pinning: SearchlightPinningComponent(
            id: 'test.pinning.recording',
            create: _RecordingPinningStore.new,
          ),
        ),
      );
      addTearDown(restored.dispose);

      expect(restored.getPin('pin-shirt'), isNotNull);

      final results = restored.search(
        term: 'shirt',
        properties: const ['title'],
      );

      expect(results.hits.first.id, 'doc-2');
    });

    test('restore rejects mismatched pinning component IDs', () {
      final original = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        components: const SearchlightComponents(
          pinning: SearchlightPinningComponent(
            id: 'test.pinning.original',
            create: _RecordingPinningStore.new,
          ),
        ),
      )
        ..insert({'id': 'doc-1', 'title': 'Red Shirt'})
        ..insertPin(
          const SearchlightPinRule(
            id: 'pin-shirt',
            conditions: [
              SearchlightPinCondition.contains('shirt'),
            ],
            consequence: SearchlightPinConsequence(
              promote: [
                SearchlightPinPromotion(docId: 'doc-1', position: 0),
              ],
            ),
          ),
        );
      addTearDown(original.dispose);

      expect(
        () => Searchlight.fromJson(
          original.toJson(),
          components: const SearchlightComponents(
            pinning: SearchlightPinningComponent(
              id: 'test.pinning.other',
              create: _RecordingPinningStore.new,
            ),
          ),
        ),
        throwsA(isA<SerializationException>()),
      );
    });
  });
}
