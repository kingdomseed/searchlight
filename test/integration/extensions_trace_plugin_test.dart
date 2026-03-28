import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

import '../helpers/extensions/test_trace_plugin.dart';

void main() {
  group('extensions trace plugin', () {
    test('observes create, insert, and search lifecycle events', () async {
      final trace = <String>[];
      final plugin = TestTracePlugin(
        name: 'alpha',
        trace: trace,
      );

      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: [plugin.plugin],
      )..insert({'id': 'doc-1', 'title': 'Hello'});
      addTearDown(db.dispose);

      db.search(term: 'Hello');

      expect(trace, <String>[
        'alpha:afterCreate',
        'alpha:beforeInsert:doc-1',
        'alpha:afterInsert:doc-1',
        'alpha:beforeSearch:Hello',
        'alpha:afterSearch:Hello',
      ]);
    });

    test('preserves deterministic ordering across multiple plugins', () async {
      final trace = <String>[];
      final alpha = TestTracePlugin(name: 'alpha', trace: trace);
      final beta = TestTracePlugin(name: 'beta', trace: trace);

      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: [alpha.plugin, beta.plugin],
      );
      addTearDown(db.dispose);

      db.insert({'id': 'doc-1', 'title': 'Hello'});

      expect(trace, <String>[
        'alpha:afterCreate',
        'beta:afterCreate',
        'alpha:beforeInsert:doc-1',
        'beta:beforeInsert:doc-1',
        'alpha:afterInsert:doc-1',
        'beta:afterInsert:doc-1',
      ]);
    });

    test(
      'restore succeeds with matching graph and does not dispatch load hooks',
      () async {
        final trace = <String>[];
        final plugin = TestTracePlugin(
          name: 'alpha',
          trace: trace,
          includeLoadHooks: true,
        );

        final db = Searchlight.create(
          schema: Schema({
            'title': const TypedField(SchemaType.string),
          }),
          plugins: [plugin.plugin],
        )..insert({'id': 'doc-1', 'title': 'Hello'});
        final json = db.toJson();
        trace.clear();

        final restored = Searchlight.fromJson(
          json,
          plugins: [plugin.plugin],
        );
        addTearDown(restored.dispose);

        expect(restored.getById('doc-1'), isNotNull);
        expect(trace, isEmpty);
      },
    );
  });
}
