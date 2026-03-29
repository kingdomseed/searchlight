import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

final class _RecordingDocumentsStore implements SearchlightDocumentsStore {
  final Map<DocId, Document> _documents = {};
  final Map<String, DocId> _externalToInternal = {};
  final Map<DocId, String> _internalToExternal = {};

  int storeCalls = 0;
  int saveCalls = 0;
  int removeCalls = 0;
  int getByExternalIdCalls = 0;
  int getByInternalIdCalls = 0;

  @override
  int get count => _documents.length;

  @override
  bool containsExternalId(String externalId) =>
      _externalToInternal.containsKey(externalId);

  @override
  Iterable<DocId> get internalIds => _documents.keys;

  @override
  String? getExternalId(DocId internalId) => _internalToExternal[internalId];

  @override
  Document? getByExternalId(String externalId) {
    getByExternalIdCalls++;
    final internalId = _externalToInternal[externalId];
    if (internalId == null) {
      return null;
    }
    return _documents[internalId];
  }

  @override
  Document? getByInternalId(DocId internalId) {
    getByInternalIdCalls++;
    return _documents[internalId];
  }

  @override
  bool removeByExternalId(String externalId) {
    removeCalls++;
    final internalId = _externalToInternal.remove(externalId);
    if (internalId == null) {
      return false;
    }
    _internalToExternal.remove(internalId);
    return _documents.remove(internalId) != null;
  }

  @override
  Map<String, Object?> save() {
    saveCalls++;
    return {
      for (final entry in _documents.entries)
        entry.key.id.toString(): Map<String, Object?>.from(entry.value.toMap()),
    };
  }

  @override
  bool store({
    required DocId internalId,
    required String externalId,
    required Document document,
  }) {
    storeCalls++;
    if (_externalToInternal.containsKey(externalId)) {
      return false;
    }
    final storedData = Map<String, Object?>.from(document.toMap());
    if (storedData.containsKey('title')) {
      storedData['title'] = '${storedData['title']} [stored]';
    }
    if (storedData.containsKey('category')) {
      storedData['category'] = 'stored-category';
    }
    _externalToInternal[externalId] = internalId;
    _internalToExternal[internalId] = externalId;
    _documents[internalId] = Document(storedData);
    return true;
  }

  @override
  void restore({
    required DocId internalId,
    required String externalId,
    required Document document,
  }) {
    _externalToInternal[externalId] = internalId;
    _internalToExternal[internalId] = externalId;
    _documents[internalId] = document;
  }
}

final class _TransformingDocumentsStore implements SearchlightDocumentsStore {
  _TransformingDocumentsStore(this._transform);

  final Map<String, Object?> Function(Map<String, Object?> source) _transform;
  final Map<DocId, Document> _documents = {};
  final Map<String, DocId> _externalToInternal = {};
  final Map<DocId, String> _internalToExternal = {};

  @override
  int get count => _documents.length;

  @override
  bool containsExternalId(String externalId) =>
      _externalToInternal.containsKey(externalId);

  @override
  Iterable<DocId> get internalIds => _documents.keys;

  @override
  String? getExternalId(DocId internalId) => _internalToExternal[internalId];

  @override
  Document? getByExternalId(String externalId) {
    final internalId = _externalToInternal[externalId];
    if (internalId == null) {
      return null;
    }
    return _documents[internalId];
  }

  @override
  Document? getByInternalId(DocId internalId) => _documents[internalId];

  @override
  bool removeByExternalId(String externalId) {
    final internalId = _externalToInternal.remove(externalId);
    if (internalId == null) {
      return false;
    }
    _internalToExternal.remove(internalId);
    return _documents.remove(internalId) != null;
  }

  @override
  Map<String, Object?> save() => {
        for (final entry in _documents.entries)
          entry.key.id.toString(): Map<String, Object?>.from(entry.value.toMap()),
      };

  @override
  bool store({
    required DocId internalId,
    required String externalId,
    required Document document,
  }) {
    if (_externalToInternal.containsKey(externalId)) {
      return false;
    }
    _externalToInternal[externalId] = internalId;
    _internalToExternal[internalId] = externalId;
    _documents[internalId] = Document(_transform(document.toMap()));
    return true;
  }

  @override
  void restore({
    required DocId internalId,
    required String externalId,
    required Document document,
  }) {
    _externalToInternal[externalId] = internalId;
    _internalToExternal[internalId] = externalId;
    _documents[internalId] = document;
  }
}

void main() {
  group('extension documentsStore component', () {
    test('database uses the resolved documentsStore for reads and hydration', () {
      final store = _RecordingDocumentsStore();
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        components: SearchlightComponents(
          documentsStore: SearchlightDocumentsStoreComponent(
            id: 'test.documents.recording',
            create: () => store,
          ),
        ),
      )..insert({
          'id': 'doc-1',
          'title': 'Ember Lance',
        });
      addTearDown(db.dispose);

      expect(store.storeCalls, 1);
      expect(
        db.getById('doc-1')?.getString('title'),
        'Ember Lance [stored]',
      );

      final results = db.search(
        term: 'ember',
        properties: const ['title'],
      );

      expect(results.count, 1);
      expect(results.hits.single.id, 'doc-1');
      expect(
        results.hits.single.document.getString('title'),
        'Ember Lance [stored]',
      );
      expect(store.getByExternalIdCalls, greaterThan(0));
      expect(store.getByInternalIdCalls, greaterThan(0));
    });

    test('remove hooks receive the store-backed document and remove via store',
        () {
      final store = _RecordingDocumentsStore();
      final removedTitles = <String?>[];
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'category': const TypedField(SchemaType.string),
        }),
        plugins: [
          SearchlightPlugin(
            name: 'remove-hooks',
            hooks: SearchlightHooks(
              beforeRemove: (_, __, doc) =>
                  removedTitles.add(doc?['title'] as String?),
            ),
          ),
        ],
        components: SearchlightComponents(
          documentsStore: SearchlightDocumentsStoreComponent(
            id: 'test.documents.recording',
            create: () => store,
          ),
        ),
      )..insert({
          'id': 'doc-1',
          'title': 'Ember Lance',
          'category': 'original-category',
        });
      addTearDown(db.dispose);

      expect(db.remove('doc-1'), isTrue);

      expect(removedTitles, ['Ember Lance [stored]']);
      expect(store.removeCalls, 1);
      expect(db.getById('doc-1'), isNull);
    });

    test('facets and groups use store-backed documents', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'category': const TypedField(SchemaType.string),
        }),
        components: SearchlightComponents(
          documentsStore: SearchlightDocumentsStoreComponent(
            id: 'test.documents.recording',
            create: _RecordingDocumentsStore.new,
          ),
        ),
      )..insert({
          'id': 'doc-1',
          'title': 'Ember Lance',
          'category': 'original-category',
        });
      addTearDown(db.dispose);

      final results = db.search(
        term: 'ember',
        properties: const ['title'],
        facets: {
          'category': const FacetConfig(),
        },
        groupBy: const GroupBy(field: 'category', limit: 10),
      );

      expect(results.facets?['category']?.values, {'stored-category': 1});
      expect(results.groups, hasLength(1));
      expect(results.groups?.single.values, ['stored-category']);
      expect(
        results.groups?.single.result.single.document.getString('category'),
        'stored-category',
      );
    });

    test('toJson serializes the store-backed document payload', () {
      final store = _RecordingDocumentsStore();
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'category': const TypedField(SchemaType.string),
        }),
        components: SearchlightComponents(
          documentsStore: SearchlightDocumentsStoreComponent(
            id: 'test.documents.recording',
            create: () => store,
          ),
        ),
      )..insert({
          'id': 'doc-1',
          'title': 'Ember Lance',
          'category': 'original-category',
        });
      addTearDown(db.dispose);

      final json = db.toJson();
      final documents = json['documents']! as Map<String, Object?>;
      final doc = documents['1']! as Map<String, Object?>;

      expect(store.saveCalls, 1);
      expect(doc['title'], 'Ember Lance [stored]');
      expect(doc['category'], 'stored-category');

      final restored = Searchlight.fromJson(
        json,
        components: SearchlightComponents(
          documentsStore: SearchlightDocumentsStoreComponent(
            id: 'test.documents.recording',
            create: _RecordingDocumentsStore.new,
          ),
        ),
      );
      addTearDown(restored.dispose);

      expect(
        restored.getById('doc-1')?.getString('title'),
        'Ember Lance [stored]',
      );
      expect(
        restored.getById('doc-1')?.getString('category'),
        'stored-category',
      );
    });

    test('restore rejects mismatched documentsStore component IDs', () {
      final original = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        components: SearchlightComponents(
          documentsStore: SearchlightDocumentsStoreComponent(
            id: 'test.documents.original',
            create: _RecordingDocumentsStore.new,
          ),
        ),
      )..insert({
          'id': 'doc-1',
          'title': 'Ember Lance',
        });
      addTearDown(original.dispose);

      expect(
        () => Searchlight.fromJson(
          original.toJson(),
          components: SearchlightComponents(
            documentsStore: SearchlightDocumentsStoreComponent(
              id: 'test.documents.other',
              create: _RecordingDocumentsStore.new,
            ),
          ),
        ),
        throwsA(isA<SerializationException>()),
      );
    });

    test('facets and grouping read documents from the documentsStore', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'category': const TypedField(SchemaType.string),
        }),
        components: SearchlightComponents(
          documentsStore: SearchlightDocumentsStoreComponent(
            id: 'test.documents.transform.facets',
            create: () => _TransformingDocumentsStore(
              (source) => <String, Object?>{
                ...source,
                'category': 'stored',
              },
            ),
          ),
        ),
      )..insert({
          'id': 'doc-1',
          'title': 'Ember Lance',
          'category': 'raw',
        });
      addTearDown(db.dispose);

      final results = db.search(
        term: 'ember',
        properties: const ['title'],
        facets: {
          'category': const FacetConfig(),
        },
        groupBy: const GroupBy(field: 'category', limit: 10),
      );

      expect(results.facets?['category']?.values, containsPair('stored', 1));
      expect(results.groups, isNotNull);
      expect(results.groups!.single.values, contains('stored'));
    });

    test('serialization and reindex use documents from the documentsStore', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'category': const TypedField(SchemaType.string),
        }),
        components: SearchlightComponents(
          documentsStore: SearchlightDocumentsStoreComponent(
            id: 'test.documents.transform.serialize',
            create: () => _TransformingDocumentsStore(
              (source) => <String, Object?>{
                ...source,
                'category': 'stored',
              },
            ),
          ),
        ),
      )..insert({
          'id': 'doc-1',
          'title': 'Ember Lance',
          'category': 'raw',
        });
      addTearDown(db.dispose);

      final json = db.toJson();
      final documents = json['documents']! as Map<String, Object?>;
      final storedDoc = documents['1']! as Map<String, Object?>;

      expect(storedDoc['category'], 'stored');

      final reindexed = db.reindex(algorithm: SearchAlgorithm.qps);
      addTearDown(reindexed.dispose);
      expect(reindexed.getById('doc-1')?.getString('category'), 'stored');
    });
  });
}
