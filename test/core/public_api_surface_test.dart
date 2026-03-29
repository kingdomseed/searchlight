import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('public API surface', () {
    test('searchlight barrel does not export DocumentAdapter', () async {
      final tempDir = Directory(
        '${Directory.current.path}/test/.tmp_public_api_surface',
      );
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
      await tempDir.create(recursive: true);
      final source = File('${tempDir.path}/document_adapter_surface.dart');

      try {
        source.writeAsStringSync('''
import 'package:searchlight/searchlight.dart';

class Adapter extends DocumentAdapter<String> {
  @override
  List<Map<String, Object?>> toDocuments(String source) => const [];
}
''');

        final result = await Process.run(
          'dart',
          ['analyze', source.path],
          workingDirectory: Directory.current.path,
        );

        final output = '${result.stdout}\n${result.stderr}';
        expect(result.exitCode, isNonZero);
        expect(output, isNot(contains('uri_does_not_exist')));
        expect(output, contains('extends_non_class'));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'searchlight barrel exports extension types and create accepts them',
      () async {
        final tempDir = Directory(
          '${Directory.current.path}/test/.tmp_extension_api_surface',
        );
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
        await tempDir.create(recursive: true);
        final source = File('${tempDir.path}/extension_surface.dart');

        try {
          source.writeAsStringSync('''
import 'package:searchlight/searchlight.dart';

Searchlight buildDatabase() {
  final plugin = SearchlightPlugin(name: 'test-plugin');
  const components = SearchlightComponents();
  return Searchlight.create(
    schema: Schema({
      'title': TypedField(SchemaType.string),
    }),
    plugins: [plugin],
    components: components,
  );
}
''');

          final result = await Process.run(
            'dart',
            ['analyze', source.path],
            workingDirectory: Directory.current.path,
          );

          final output = '${result.stdout}\n${result.stderr}';
          expect(result.exitCode, 0, reason: output);
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );

    test('searchlight public API exposes upsert methods and hook fields',
        () async {
      final tempDir = Directory(
        '${Directory.current.path}/test/.tmp_upsert_api_surface',
      );
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
      await tempDir.create(recursive: true);
      final source = File('${tempDir.path}/upsert_surface.dart');

      try {
        source.writeAsStringSync('''
import 'package:searchlight/searchlight.dart';

Searchlight buildDatabase() {
  final db = Searchlight.create(
    schema: Schema({
      'title': TypedField(SchemaType.string),
    }),
    plugins: [
      SearchlightPlugin(
        name: 'hooks',
        hooks: SearchlightHooks(
          beforeUpsert: (_, __, ___) {},
          afterUpsert: (_, __, ___) {},
          beforeUpsertMultiple: (_, __) {},
          afterUpsertMultiple: (_, __) {},
        ),
      ),
    ],
  );

  db.upsert({
    'id': 'doc-1',
    'title': 'One',
  });
  db.upsertMultiple([
    {
      'id': 'doc-1',
      'title': 'Two',
    },
  ]);
  return db;
}
''');

        final result = await Process.run(
          'dart',
          ['analyze', source.path],
          workingDirectory: Directory.current.path,
        );

        final output = '${result.stdout}\n${result.stderr}';
        expect(result.exitCode, 0, reason: output);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('searchlight barrel exports component types for overrides', () async {
      final tempDir = Directory(
        '${Directory.current.path}/test/.tmp_component_api_surface',
      );
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
      await tempDir.create(recursive: true);
      final source = File('${tempDir.path}/component_surface.dart');

      try {
        source.writeAsStringSync('''
import 'package:searchlight/searchlight.dart';

Searchlight buildDatabase() {
  final index = SearchlightIndexComponent(
    id: 'test.index',
    create: ({
      required schema,
      required algorithm,
    }) => SearchIndex.create(schema: schema, algorithm: algorithm),
  );
  final sorter = SearchlightSorterComponent(
    id: 'test.sorter',
    create: ({required language}) => SortIndex(language: language),
  );
  return Searchlight.create(
    schema: Schema({
      'title': TypedField(SchemaType.string),
    }),
    components: SearchlightComponents(
      tokenizer: Tokenizer(),
      index: index,
      sorter: sorter,
      validateSchema: (doc, schema) {
        final _ = schema;
        return doc['title'] == null ? 'title' : null;
      },
      getDocumentIndexId: (doc) => doc['id'] as String? ?? 'generated-id',
      getDocumentProperties: (doc, paths) => {
        for (final path in paths) path: doc[path],
      },
    ),
  );
}
''');

        final result = await Process.run(
          'dart',
          ['analyze', source.path],
          workingDirectory: Directory.current.path,
        );

        final output = '${result.stdout}\n${result.stderr}';
        expect(result.exitCode, 0, reason: output);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('searchlight does not expose internal resolved extension state',
        () async {
      final tempDir = Directory(
        '${Directory.current.path}/test/.tmp_extension_internal_surface',
      );
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
      await tempDir.create(recursive: true);
      final source = File('${tempDir.path}/internal_surface.dart');

      try {
        source.writeAsStringSync('''
import 'package:searchlight/searchlight.dart';

void inspect(Searchlight db) {
  // Should remain internal implementation detail.
  db.resolvedExtensions;
}
''');

        final result = await Process.run(
          'dart',
          ['analyze', source.path],
          workingDirectory: Directory.current.path,
        );

        final output = '${result.stdout}\n${result.stderr}';
        expect(result.exitCode, isNonZero, reason: output);
        expect(output, contains('undefined_getter'));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}
