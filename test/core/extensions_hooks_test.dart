import 'package:searchlight/src/extensions/hooks.dart';
import 'package:searchlight/src/extensions/runtime.dart';
import 'package:test/test.dart';

void main() {
  group('extensions hook runtime', () {
    test('hook registration order is preserved', () async {
      final calls = <String>[];
      final runtime = SearchlightHookRuntime.fromHooks([
        SearchlightHooks(
          beforeInsert: (_, __, ___) {
            calls.add('first');
          },
        ),
        SearchlightHooks(
          beforeInsert: (_, __, ___) {
            calls.add('second');
          },
        ),
      ]);

      await runtime.runBeforeInsert(
        db: Object(),
        id: 'doc-1',
        doc: const {'title': 'A'},
      );

      expect(calls, ['first', 'second']);
    });

    test('sync hooks run in order for multi-record dispatch', () async {
      final calls = <String>[];
      final runtime = SearchlightHookRuntime.fromHooks([
        SearchlightHooks(
          beforeInsertMultiple: (_, __) {
            calls.add('sync-first');
          },
        ),
        SearchlightHooks(
          beforeInsertMultiple: (_, __) {
            calls.add('sync-second');
          },
        ),
      ]);

      await runtime.runBeforeInsertMultiple(
        db: Object(),
        docs: const [
          {'title': 'A'},
          {'title': 'B'},
        ],
      );

      expect(calls, ['sync-first', 'sync-second']);
    });

    test('async hooks are awaited in order', () async {
      final calls = <String>[];
      final runtime = SearchlightHookRuntime.fromHooks([
        SearchlightHooks(
          beforeUpdate: (_, __, ___) async {
            calls.add('async-start');
            await Future<void>.delayed(const Duration(milliseconds: 10));
            calls.add('async-end');
          },
        ),
        SearchlightHooks(
          beforeUpdate: (_, __, ___) {
            calls.add('sync-after-async');
          },
        ),
      ]);

      await runtime.runBeforeUpdate(
        db: Object(),
        id: 'doc-2',
        doc: const {'title': 'B'},
      );

      expect(calls, ['async-start', 'async-end', 'sync-after-async']);
    });

    test('search hooks use dedicated callback shapes', () async {
      final calls = <String>[];
      Object? capturedDb;
      Map<String, Object?>? capturedParams;
      String? capturedLanguage;
      Object? capturedResults;

      final runtime = SearchlightHookRuntime.fromHooks([
        SearchlightHooks(
          beforeSearch: (db, params, language) {
            calls.add('before-search');
            capturedDb = db;
            capturedParams = params;
            capturedLanguage = language;
          },
          afterSearch: (db, params, language, results) {
            calls.add('after-search');
            capturedDb = db;
            capturedParams = params;
            capturedLanguage = language;
            capturedResults = results;
          },
        ),
      ]);

      final params = <String, Object?>{
        'term': 'ember',
        'limit': 10,
      };
      final results = Object();
      final db = Object();

      await runtime.runBeforeSearch(
        db: db,
        params: params,
        language: 'english',
      );
      await runtime.runAfterSearch(
        db: db,
        params: params,
        language: 'english',
        results: results,
      );

      expect(calls, ['before-search', 'after-search']);
      expect(identical(capturedDb, db), isTrue);
      expect(identical(capturedParams, params), isTrue);
      expect(capturedLanguage, 'english');
      expect(identical(capturedResults, results), isTrue);
    });

    test('all declared hook buckets are dispatchable', () async {
      final calls = <String>[];
      final runtime = SearchlightHookRuntime.fromHooks([
        SearchlightHooks(
          afterCreate: (_) {
            calls.add('afterCreate');
          },
          beforeInsert: (_, __, ___) {
            calls.add('beforeInsert');
          },
          afterInsert: (_, __, ___) {
            calls.add('afterInsert');
          },
          beforeRemove: (_, __, ___) {
            calls.add('beforeRemove');
          },
          afterRemove: (_, __, ___) {
            calls.add('afterRemove');
          },
          beforeUpdate: (_, __, ___) {
            calls.add('beforeUpdate');
          },
          afterUpdate: (_, __, ___) {
            calls.add('afterUpdate');
          },
          beforeUpsert: (_, __, ___) {
            calls.add('beforeUpsert');
          },
          afterUpsert: (_, __, ___) {
            calls.add('afterUpsert');
          },
          beforeInsertMultiple: (_, __) {
            calls.add('beforeInsertMultiple');
          },
          afterInsertMultiple: (_, __) {
            calls.add('afterInsertMultiple');
          },
          beforeRemoveMultiple: (_, __) {
            calls.add('beforeRemoveMultiple');
          },
          afterRemoveMultiple: (_, __) {
            calls.add('afterRemoveMultiple');
          },
          beforeUpdateMultiple: (_, __) {
            calls.add('beforeUpdateMultiple');
          },
          afterUpdateMultiple: (_, __) {
            calls.add('afterUpdateMultiple');
          },
          beforeSearch: (_, __, ___) {
            calls.add('beforeSearch');
          },
          afterSearch: (_, __, ___, ____) {
            calls.add('afterSearch');
          },
          beforeLoad: (_, __) {
            calls.add('beforeLoad');
          },
          afterLoad: (_, __) {
            calls.add('afterLoad');
          },
        ),
      ]);

      final db = Object();
      final record = <String, Object?>{'title': 'A'};
      final params = <String, Object?>{'term': 'ember'};
      final ids = <String>['1', '2'];
      final docs = <SearchlightRecord>[record, record];
      final raw = Object();
      final results = Object();

      await runtime.runAfterCreate(db: db);
      await runtime.runBeforeInsert(db: db, id: '1', doc: record);
      await runtime.runAfterInsert(db: db, id: '1', doc: record);
      await runtime.runBeforeRemove(db: db, id: '1', doc: null);
      await runtime.runAfterRemove(db: db, id: '1', doc: null);
      await runtime.runBeforeUpdate(db: db, id: '1', doc: record);
      await runtime.runAfterUpdate(db: db, id: '1', doc: record);
      await runtime.runBeforeUpsert(db: db, id: '1', doc: record);
      await runtime.runAfterUpsert(db: db, id: '1', doc: record);
      await runtime.runBeforeInsertMultiple(db: db, docs: docs);
      await runtime.runAfterInsertMultiple(db: db, docs: docs);
      await runtime.runBeforeRemoveMultiple(db: db, ids: ids);
      await runtime.runAfterRemoveMultiple(db: db, ids: ids);
      await runtime.runBeforeUpdateMultiple(db: db, ids: ids);
      await runtime.runAfterUpdateMultiple(db: db, ids: ids);
      await runtime.runBeforeSearch(
        db: db,
        params: params,
        language: 'english',
      );
      await runtime.runAfterSearch(
        db: db,
        params: params,
        language: 'english',
        results: results,
      );
      await runtime.runBeforeLoad(db: db, raw: raw);
      await runtime.runAfterLoad(db: db, raw: raw);

      expect(calls, [
        'afterCreate',
        'beforeInsert',
        'afterInsert',
        'beforeRemove',
        'afterRemove',
        'beforeUpdate',
        'afterUpdate',
        'beforeUpsert',
        'afterUpsert',
        'beforeInsertMultiple',
        'afterInsertMultiple',
        'beforeRemoveMultiple',
        'afterRemoveMultiple',
        'beforeUpdateMultiple',
        'afterUpdateMultiple',
        'beforeSearch',
        'afterSearch',
        'beforeLoad',
        'afterLoad',
      ]);
    });
  });
}
