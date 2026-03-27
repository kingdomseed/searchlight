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
  });
}
