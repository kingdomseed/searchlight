import 'dart:async';

import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

void main() {
  group('batch and create lifecycle hooks', () {
    late Searchlight db;
    late List<String> calls;

    setUp(() {
      calls = <String>[];
    });

    tearDown(() async {
      await db.dispose();
    });

    test('create runs afterCreate once after instance creation', () {
      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: [
          SearchlightPlugin(
            name: 'hooks',
            hooks: SearchlightHooks(
              afterCreate: (_) => calls.add('afterCreate'),
            ),
          ),
        ],
      );

      expect(calls, <String>['afterCreate']);
    });

    test('create rejects async afterCreate hooks before invocation', () {
      var sideEffectRan = false;

      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
      );

      expect(
        () => Searchlight.create(
          schema: Schema({
            'title': const TypedField(SchemaType.string),
          }),
          plugins: [
            SearchlightPlugin(
              name: 'hooks',
              hooks: SearchlightHooks(
                afterCreate: (_) async {
                  sideEffectRan = true;
                },
              ),
            ),
          ],
        ),
        throwsA(isA<UnsupportedError>()),
      );
      expect(sideEffectRan, isFalse);
    });

    test(
      'insertMultiple matches Orama by dispatching only afterInsertMultiple',
      () {
        db = Searchlight.create(
          schema: Schema({
            'title': const TypedField(SchemaType.string),
          }),
          plugins: [
            SearchlightPlugin(
              name: 'hooks',
              hooks: SearchlightHooks(
                beforeInsertMultiple: (_, docs) {
                  calls.add('beforeInsertMultiple:${docs.length}');
                },
                afterInsertMultiple: (_, docs) {
                  final ids = docs.map((doc) => doc['id']).join(',');
                  calls
                    ..add('afterInsertMultiple:$ids')
                    ..add('afterInsertMultipleDocs:${docs.length}');
                },
              ),
            ),
          ],
        );

        final ids = db.insertMultiple([
          {'id': 'doc-1', 'title': 'One'},
          {'id': 'doc-2', 'title': 'Two'},
        ]);

        expect(ids, <String>['doc-1', 'doc-2']);
        expect(calls, <String>[
          'afterInsertMultiple:doc-1,doc-2',
          'afterInsertMultipleDocs:2',
        ]);
      },
    );

    test('removeMultiple runs beforeRemoveMultiple then afterRemoveMultiple',
        () {
      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: [
          SearchlightPlugin(
            name: 'hooks',
            hooks: SearchlightHooks(
              beforeRemoveMultiple: (_, ids) {
                calls.add('beforeRemoveMultiple:${ids.join(",")}');
              },
              afterRemoveMultiple: (_, ids) {
                calls.add('afterRemoveMultiple:${ids.join(",")}');
              },
            ),
          ),
        ],
      )
        ..insert({'id': 'doc-1', 'title': 'One'})
        ..insert({'id': 'doc-2', 'title': 'Two'});
      calls.clear();

      final removed = db.removeMultiple(<String>['doc-1', 'doc-2']);

      expect(removed, 2);
      expect(calls, <String>[
        'beforeRemoveMultiple:doc-1,doc-2',
        'afterRemoveMultiple:doc-1,doc-2',
      ]);
    });

    test('updateMultiple runs updateMultiple hooks and nested batch hooks', () {
      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: [
          SearchlightPlugin(
            name: 'hooks',
            hooks: SearchlightHooks(
              beforeUpdateMultiple: (_, ids) =>
                  calls.add('beforeUpdateMultiple:${ids.join(",")}'),
              afterUpdateMultiple: (_, ids) =>
                  calls.add('afterUpdateMultiple:${ids.join(",")}'),
              beforeRemoveMultiple: (_, ids) =>
                  calls.add('beforeRemoveMultiple:${ids.join(",")}'),
              afterRemoveMultiple: (_, ids) =>
                  calls.add('afterRemoveMultiple:${ids.join(",")}'),
              beforeInsertMultiple: (_, docs) =>
                  calls.add('beforeInsertMultiple:${docs.length}'),
              afterInsertMultiple: (_, docs) {
                final ids = docs.map((doc) => doc['id']).join(',');
                calls.add('afterInsertMultiple:$ids');
              },
            ),
          ),
        ],
      )
        ..insert({'id': 'old-1', 'title': 'Old 1'})
        ..insert({'id': 'old-2', 'title': 'Old 2'});
      calls.clear();

      final ids = db.updateMultiple(
        <String>['old-1', 'old-2'],
        <Map<String, Object?>>[
          {'id': 'new-1', 'title': 'New 1'},
          {'id': 'new-2', 'title': 'New 2'},
        ],
      );

      expect(ids, <String>['new-1', 'new-2']);
      expect(calls, <String>[
        'beforeUpdateMultiple:old-1,old-2',
        'beforeRemoveMultiple:old-1,old-2',
        'afterRemoveMultiple:old-1,old-2',
        'afterInsertMultiple:new-1,new-2',
        'afterUpdateMultiple:new-1,new-2',
      ]);
    });

    test('upsertMultiple runs upsertMultiple hooks around nested operations',
        () {
      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: [
          SearchlightPlugin(
            name: 'hooks',
            hooks: SearchlightHooks(
              beforeUpsertMultiple: (_, docs) =>
                  calls.add('beforeUpsertMultiple:${docs.length}'),
              afterUpsertMultiple: (_, ids) =>
                  calls.add('afterUpsertMultiple:${ids.join(",")}'),
              beforeUpdateMultiple: (_, ids) =>
                  calls.add('beforeUpdateMultiple:${ids.join(",")}'),
              afterUpdateMultiple: (_, ids) =>
                  calls.add('afterUpdateMultiple:${ids.join(",")}'),
              beforeRemoveMultiple: (_, ids) =>
                  calls.add('beforeRemoveMultiple:${ids.join(",")}'),
              afterRemoveMultiple: (_, ids) =>
                  calls.add('afterRemoveMultiple:${ids.join(",")}'),
              afterInsertMultiple: (_, docs) {
                final ids = docs.map((doc) => doc['id']).join(',');
                calls.add('afterInsertMultiple:$ids');
              },
            ),
          ),
        ],
      )..insert({'id': 'doc-1', 'title': 'Old'});
      calls.clear();

      final ids = db.upsertMultiple([
        {'id': 'doc-1', 'title': 'Updated'},
        {'id': 'doc-2', 'title': 'Inserted'},
      ]);

      expect(ids, <String>['doc-1', 'doc-2']);
      expect(calls, <String>[
        'beforeUpsertMultiple:2',
        'beforeUpdateMultiple:doc-1',
        'beforeRemoveMultiple:doc-1',
        'afterRemoveMultiple:doc-1',
        'afterInsertMultiple:doc-1',
        'afterUpdateMultiple:doc-1',
        'afterInsertMultiple:doc-2',
        'afterUpsertMultiple:doc-1,doc-2',
      ]);
    });

    test(
      'insertMultiple rejects async multiple hooks before any side effects',
      () {
        var sideEffectRan = false;

        db = Searchlight.create(
          schema: Schema({
            'title': const TypedField(SchemaType.string),
          }),
          plugins: [
            SearchlightPlugin(
              name: 'hooks',
              hooks: SearchlightHooks(
                afterInsertMultiple: (_, __) async {
                  sideEffectRan = true;
                },
              ),
            ),
          ],
        );

        expect(
          () => db.insertMultiple([
            {'id': 'doc-1', 'title': 'One'},
          ]),
          throwsA(isA<UnsupportedError>()),
        );
        expect(sideEffectRan, isFalse);
        expect(db.count, 0);
      },
    );

    test('insertMultiple rejects non-async Future-returning top-level hooks',
        () {
      Future<void> futureHook(Object _, List<SearchlightRecord> __) {
        return Future<void>.value();
      }

      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: [
          SearchlightPlugin(
            name: 'hooks',
            hooks: SearchlightHooks(afterInsertMultiple: futureHook),
          ),
        ],
      );

      expect(
        () => db.insertMultiple([
          {'id': 'doc-1', 'title': 'One'},
        ]),
        throwsA(isA<UnsupportedError>()),
      );
      expect(db.count, 0);
    });

    test(
      'insertMultiple ignores beforeInsertMultiple hooks because Orama does '
      'not dispatch them',
      () {
        var hookRan = false;

        db = Searchlight.create(
          schema: Schema({
            'title': const TypedField(SchemaType.string),
          }),
          plugins: [
            SearchlightPlugin(
              name: 'hooks',
              hooks: SearchlightHooks(
                beforeInsertMultiple: (_, __) async {
                  hookRan = true;
                },
              ),
            ),
          ],
        );

        final ids = db.insertMultiple([
          {'id': 'doc-1', 'title': 'One'},
        ]);

        expect(ids, <String>['doc-1']);
        expect(hookRan, isFalse);
        expect(db.count, 1);
      },
    );

    test(
      'upsertMultiple rejects async nested batch hooks before any hook runs',
      () {
        var beforeUpsertMultipleRan = false;

        db = Searchlight.create(
          schema: Schema({
            'title': const TypedField(SchemaType.string),
          }),
          plugins: [
            SearchlightPlugin(
              name: 'hooks',
              hooks: SearchlightHooks(
                beforeUpsertMultiple: (_, __) {
                  beforeUpsertMultipleRan = true;
                },
                afterUpdateMultiple: (_, __) async {},
              ),
            ),
          ],
        )..insert({'id': 'doc-1', 'title': 'Old'});

        expect(
          () => db.upsertMultiple([
            {'id': 'doc-1', 'title': 'Updated'},
          ]),
          throwsA(isA<UnsupportedError>()),
        );
        expect(beforeUpsertMultipleRan, isFalse);
        expect(db.getById('doc-1')?.getString('title'), 'Old');
      },
    );

    test('insert rejects async afterInsert hooks before any side effects', () {
      var sideEffectRan = false;

      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: [
          SearchlightPlugin(
            name: 'hooks',
            hooks: SearchlightHooks(
              afterInsert: (_, __, ___) async {
                sideEffectRan = true;
              },
            ),
          ),
        ],
      );

      expect(
        () => db.insert({'id': 'doc-1', 'title': 'One'}),
        throwsA(isA<UnsupportedError>()),
      );
      expect(sideEffectRan, isFalse);
      expect(db.count, 0);
    });

    test('remove rejects async afterRemove hooks before any side effects', () {
      var sideEffectRan = false;

      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: [
          SearchlightPlugin(
            name: 'hooks',
            hooks: SearchlightHooks(
              afterRemove: (_, __, ___) async {
                sideEffectRan = true;
              },
            ),
          ),
        ],
      )..insert({'id': 'doc-1', 'title': 'One'});

      expect(
        () => db.remove('doc-1'),
        throwsA(isA<UnsupportedError>()),
      );
      expect(sideEffectRan, isFalse);
      expect(db.getById('doc-1'), isNotNull);
    });

    test('update rejects async afterUpdate hooks before any side effects', () {
      var sideEffectRan = false;

      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: [
          SearchlightPlugin(
            name: 'hooks',
            hooks: SearchlightHooks(
              afterUpdate: (_, __, ___) async {
                sideEffectRan = true;
              },
            ),
          ),
        ],
      )..insert({'id': 'old-1', 'title': 'Old'});

      expect(
        () => db.update('old-1', {'id': 'new-1', 'title': 'New'}),
        throwsA(isA<UnsupportedError>()),
      );
      expect(sideEffectRan, isFalse);
      expect(db.getById('old-1'), isNotNull);
      expect(db.getById('new-1'), isNull);
    });

    test(
      'removeMultiple rejects async afterRemoveMultiple before side effects',
      () {
        var sideEffectRan = false;

        db = Searchlight.create(
          schema: Schema({
            'title': const TypedField(SchemaType.string),
          }),
          plugins: [
            SearchlightPlugin(
              name: 'hooks',
              hooks: SearchlightHooks(
                afterRemoveMultiple: (_, __) async {
                  sideEffectRan = true;
                },
              ),
            ),
          ],
        )
          ..insert({'id': 'doc-1', 'title': 'One'})
          ..insert({'id': 'doc-2', 'title': 'Two'});

        expect(
          () => db.removeMultiple(<String>['doc-1', 'doc-2']),
          throwsA(isA<UnsupportedError>()),
        );
        expect(sideEffectRan, isFalse);
        expect(db.count, 2);
      },
    );

    test(
      'updateMultiple rejects async afterUpdateMultiple before side effects',
      () {
        var sideEffectRan = false;

        db = Searchlight.create(
          schema: Schema({
            'title': const TypedField(SchemaType.string),
          }),
          plugins: [
            SearchlightPlugin(
              name: 'hooks',
              hooks: SearchlightHooks(
                afterUpdateMultiple: (_, __) async {
                  sideEffectRan = true;
                },
              ),
            ),
          ],
        )
          ..insert({'id': 'old-1', 'title': 'Old 1'})
          ..insert({'id': 'old-2', 'title': 'Old 2'});

        expect(
          () => db.updateMultiple(
            <String>['old-1', 'old-2'],
            <Map<String, Object?>>[
              {'id': 'new-1', 'title': 'New 1'},
              {'id': 'new-2', 'title': 'New 2'},
            ],
          ),
          throwsA(isA<UnsupportedError>()),
        );
        expect(sideEffectRan, isFalse);
        expect(db.getById('old-1'), isNotNull);
        expect(db.getById('old-2'), isNotNull);
        expect(db.getById('new-1'), isNull);
        expect(db.getById('new-2'), isNull);
      },
    );
  });
}
