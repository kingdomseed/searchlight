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

    test('insertMultiple runs beforeInsertMultiple then afterInsertMultiple',
        () {
      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: [
          SearchlightPlugin(
            name: 'hooks',
            hooks: SearchlightHooks(
              beforeInsertMultiple: (_, ids, docs) {
                calls.add('beforeInsertMultiple:${ids.join(",")}');
                calls.add('beforeInsertMultipleDocs:${docs?.length ?? -1}');
              },
              afterInsertMultiple: (_, ids, docs) {
                calls.add('afterInsertMultiple:${ids.join(",")}');
                calls.add('afterInsertMultipleDocs:${docs?.length ?? -1}');
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
        'beforeInsertMultiple:doc-1,doc-2',
        'beforeInsertMultipleDocs:2',
        'afterInsertMultiple:doc-1,doc-2',
        'afterInsertMultipleDocs:2',
      ]);
    });

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
              beforeRemoveMultiple: (_, ids, docs) {
                calls.add('beforeRemoveMultiple:${ids.join(",")}');
                calls.add('beforeRemoveMultipleDocs:${docs?.length ?? -1}');
              },
              afterRemoveMultiple: (_, ids, docs) {
                calls.add('afterRemoveMultiple:${ids.join(",")}');
                calls.add('afterRemoveMultipleDocs:${docs?.length ?? -1}');
              },
            ),
          ),
        ],
      );

      db
        ..insert({'id': 'doc-1', 'title': 'One'})
        ..insert({'id': 'doc-2', 'title': 'Two'});
      calls.clear();

      final removed = db.removeMultiple(<String>['doc-1', 'doc-2']);

      expect(removed, 2);
      expect(calls, <String>[
        'beforeRemoveMultiple:doc-1,doc-2',
        'beforeRemoveMultipleDocs:-1',
        'afterRemoveMultiple:doc-1,doc-2',
        'afterRemoveMultipleDocs:-1',
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
              beforeUpdateMultiple: (_, ids, __) =>
                  calls.add('beforeUpdateMultiple:${ids.join(",")}'),
              afterUpdateMultiple: (_, ids, __) =>
                  calls.add('afterUpdateMultiple:${ids.join(",")}'),
              beforeRemoveMultiple: (_, ids, __) =>
                  calls.add('beforeRemoveMultiple:${ids.join(",")}'),
              afterRemoveMultiple: (_, ids, __) =>
                  calls.add('afterRemoveMultiple:${ids.join(",")}'),
              beforeInsertMultiple: (_, ids, __) =>
                  calls.add('beforeInsertMultiple:${ids.join(",")}'),
              afterInsertMultiple: (_, ids, __) =>
                  calls.add('afterInsertMultiple:${ids.join(",")}'),
            ),
          ),
        ],
      );

      db
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
        'beforeInsertMultiple:new-1,new-2',
        'afterInsertMultiple:new-1,new-2',
        'afterUpdateMultiple:new-1,new-2',
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
                beforeInsertMultiple: (_, __, ___) async {
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
      Future<void> futureHook(
        Object _,
        List<String> __,
        List<SearchlightRecord>? ___,
      ) {
        return Future<void>.value();
      }

      db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: [
          SearchlightPlugin(
            name: 'hooks',
            hooks: SearchlightHooks(beforeInsertMultiple: futureHook),
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
  });
}
