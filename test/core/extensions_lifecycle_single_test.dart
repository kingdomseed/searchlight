import 'dart:async';

import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

void main() {
  group('single-record lifecycle hooks', () {
    late Searchlight db;
    late List<String> calls;

    setUp(() {
      calls = <String>[];
    });

    tearDown(() async {
      await db.dispose();
    });

    test('insert runs beforeInsert then afterInsert', () {
      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: [
          SearchlightPlugin(
            name: 'hooks',
            hooks: SearchlightHooks(
              beforeInsert: (_, id, __) => calls.add('beforeInsert:$id'),
              afterInsert: (_, id, __) => calls.add('afterInsert:$id'),
            ),
          ),
        ],
      );

      final id = db.insert({'id': 'doc-1', 'title': 'Hello'});

      expect(id, 'doc-1');
      expect(calls, <String>['beforeInsert:doc-1', 'afterInsert:doc-1']);
    });

    test('remove runs beforeRemove then afterRemove for existing documents',
        () {
      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: [
          SearchlightPlugin(
            name: 'hooks',
            hooks: SearchlightHooks(
              beforeRemove: (_, id, __) => calls.add('beforeRemove:$id'),
              afterRemove: (_, id, __) => calls.add('afterRemove:$id'),
            ),
          ),
        ],
      );

      final removed =
          (db..insert({'id': 'doc-1', 'title': 'Hello'})).remove('doc-1');

      expect(removed, isTrue);
      expect(calls, <String>['beforeRemove:doc-1', 'afterRemove:doc-1']);
    });

    test('remove does not run remove hooks when document is missing', () {
      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: [
          SearchlightPlugin(
            name: 'hooks',
            hooks: SearchlightHooks(
              beforeRemove: (_, id, __) => calls.add('beforeRemove:$id'),
              afterRemove: (_, id, __) => calls.add('afterRemove:$id'),
            ),
          ),
        ],
      );

      final removed = db.remove('missing');

      expect(removed, isFalse);
      expect(calls, isEmpty);
    });

    test('update runs update hooks and nested remove/insert hooks in order',
        () {
      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: [
          SearchlightPlugin(
            name: 'hooks',
            hooks: SearchlightHooks(
              beforeUpdate: (_, id, __) => calls.add('beforeUpdate:$id'),
              afterUpdate: (_, id, __) => calls.add('afterUpdate:$id'),
              beforeRemove: (_, id, __) => calls.add('beforeRemove:$id'),
              afterRemove: (_, id, __) => calls.add('afterRemove:$id'),
              beforeInsert: (_, id, __) => calls.add('beforeInsert:$id'),
              afterInsert: (_, id, __) => calls.add('afterInsert:$id'),
            ),
          ),
        ],
      )..insert({'id': 'old-doc', 'title': 'Old'});
      calls.clear();
      final newId = db.update('old-doc', {'id': 'new-doc', 'title': 'New'});

      expect(newId, 'new-doc');
      expect(calls, <String>[
        'beforeUpdate:old-doc',
        'beforeRemove:old-doc',
        'afterRemove:old-doc',
        'beforeInsert:new-doc',
        'afterInsert:new-doc',
        'afterUpdate:new-doc',
      ]);
    });

    test('upsert inserts missing documents and wraps nested insert hooks', () {
      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: [
          SearchlightPlugin(
            name: 'hooks',
            hooks: SearchlightHooks(
              beforeUpsert: (_, id, __) => calls.add('beforeUpsert:$id'),
              afterUpsert: (_, id, __) => calls.add('afterUpsert:$id'),
              beforeInsert: (_, id, __) => calls.add('beforeInsert:$id'),
              afterInsert: (_, id, __) => calls.add('afterInsert:$id'),
            ),
          ),
        ],
      );

      final id = db.upsert({'id': 'doc-1', 'title': 'Hello'});

      expect(id, 'doc-1');
      expect(calls, <String>[
        'beforeUpsert:doc-1',
        'beforeInsert:doc-1',
        'afterInsert:doc-1',
        'afterUpsert:doc-1',
      ]);
    });

    test('upsert updates existing documents and wraps nested update hooks', () {
      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: [
          SearchlightPlugin(
            name: 'hooks',
            hooks: SearchlightHooks(
              beforeUpsert: (_, id, __) => calls.add('beforeUpsert:$id'),
              afterUpsert: (_, id, __) => calls.add('afterUpsert:$id'),
              beforeUpdate: (_, id, __) => calls.add('beforeUpdate:$id'),
              afterUpdate: (_, id, __) => calls.add('afterUpdate:$id'),
              beforeRemove: (_, id, __) => calls.add('beforeRemove:$id'),
              afterRemove: (_, id, __) => calls.add('afterRemove:$id'),
              beforeInsert: (_, id, __) => calls.add('beforeInsert:$id'),
              afterInsert: (_, id, __) => calls.add('afterInsert:$id'),
            ),
          ),
        ],
      )..insert({'id': 'doc-1', 'title': 'Old'});
      calls.clear();

      final id = db.upsert({'id': 'doc-1', 'title': 'New'});

      expect(id, 'doc-1');
      expect(calls, <String>[
        'beforeUpsert:doc-1',
        'beforeUpdate:doc-1',
        'beforeRemove:doc-1',
        'afterRemove:doc-1',
        'beforeInsert:doc-1',
        'afterInsert:doc-1',
        'afterUpdate:doc-1',
        'afterUpsert:doc-1',
      ]);
    });

    test(
      'insert rejects async single-record hooks before any side effect runs',
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
                beforeInsert: (_, __, ___) async {
                  sideEffectRan = true;
                },
              ),
            ),
          ],
        );

        expect(
          () => db.insert({'id': 'doc-1', 'title': 'Hello'}),
          throwsA(isA<UnsupportedError>()),
        );
        expect(sideEffectRan, isFalse);
        expect(db.count, 0);
      },
    );

    test(
      'insert rejects non-async Future-returning hook before invocation',
      () {
        var sideEffectRan = false;
        Future<void> futureHook(
          Object _,
          String __,
          SearchlightRecord? ___,
        ) {
          sideEffectRan = true;
          return Future<void>.value();
        }

        db = Searchlight.create(
          schema: Schema({
            'title': const TypedField(SchemaType.string),
          }),
          plugins: [
            SearchlightPlugin(
              name: 'hooks',
              hooks: SearchlightHooks(beforeInsert: futureHook),
            ),
          ],
        );

        expect(
          () => db.insert({'id': 'doc-2', 'title': 'Hello'}),
          throwsA(isA<UnsupportedError>()),
        );
        expect(sideEffectRan, isFalse);
        expect(db.count, 0);
      },
    );

    test('insert accepts non-async void-returning top-level style hook', () {
      var sideEffectRan = false;
      void syncHook(
        Object _,
        String __,
        SearchlightRecord? ___,
      ) {
        sideEffectRan = true;
      }

      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: [
          SearchlightPlugin(
            name: 'hooks',
            hooks: SearchlightHooks(beforeInsert: syncHook),
          ),
        ],
      );

      final id = db.insert({'id': 'doc-3', 'title': 'Hello'});

      expect(id, 'doc-3');
      expect(sideEffectRan, isTrue);
      expect(db.count, 1);
    });

    test('upsert rejects async nested update hooks before any hook runs', () {
      var beforeUpsertRan = false;

      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: [
          SearchlightPlugin(
            name: 'hooks',
            hooks: SearchlightHooks(
              beforeUpsert: (_, __, ___) {
                beforeUpsertRan = true;
              },
              afterUpdate: (_, __, ___) async {},
            ),
          ),
        ],
      )..insert({'id': 'doc-1', 'title': 'Old'});

      expect(
        () => db.upsert({'id': 'doc-1', 'title': 'New'}),
        throwsA(isA<UnsupportedError>()),
      );
      expect(beforeUpsertRan, isFalse);
      expect(db.getById('doc-1')?.getString('title'), 'Old');
    });
  });
}
