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
          beforeInsertMultiple: (_, __, ___) {
            calls.add('sync-first');
          },
        ),
        SearchlightHooks(
          beforeInsertMultiple: (_, __, ___) {
            calls.add('sync-second');
          },
        ),
      ]);

      await runtime.runBeforeInsertMultiple(
        db: Object(),
        ids: const ['a', 'b'],
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
  });
}
