import 'dart:convert';
import 'dart:io';

import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

import '../../example/tool/build_validation_assets.dart';

void main() {
  group('local validation asset generation', () {
    test('generator writes corpus and restorable snapshot', () async {
      final exampleRoot = await Directory.systemTemp.createTemp(
        'searchlight_validation_assets_',
      );
      final localDir = Directory('${exampleRoot.path}/.local');
      final sourceDir = Directory('${localDir.path}/source');
      final corpusFile = File('${localDir.path}/generated_search_corpus.json');
      final snapshotFile = File(
        '${localDir.path}/generated_search_snapshot.json',
      );

      try {
        await sourceDir.create(recursive: true);

        final spellsDir = Directory('${sourceDir.path}/spells/fire');
        await spellsDir.create(recursive: true);
        File('${spellsDir.path}/ember-lance.md').writeAsStringSync(
          '# Ember Lance\n'
          '\n'
          'A precise fire spell that launches a concentrated spear of heat.\n',
        );

        await buildValidationAssets(exampleRoot: exampleRoot);

        expect(corpusFile.existsSync(), isTrue);
        expect(snapshotFile.existsSync(), isTrue);

        final corpus =
            jsonDecode(corpusFile.readAsStringSync()) as List<dynamic>;
        expect(corpus, isNotEmpty);

        final first = corpus.first as Map<String, dynamic>;
        expect(first['url'], '/spells/fire/ember-lance');
        expect(first['title'], 'Ember Lance');
        expect(first['type'], 'spell');
        expect(first['group'], 'fire');
        expect(first['content'], isNot(contains('# Ember Lance')));
        expect(first['content'], contains('A precise fire spell'));

        final snapshot =
            jsonDecode(snapshotFile.readAsStringSync()) as Map<String, dynamic>;
        expect(snapshot.containsKey('documents'), isTrue);

        final restored = Searchlight.fromJson(
          snapshot.cast<String, Object?>(),
        );
        final result = restored.search(
          term: 'spear',
          properties: const ['content'],
          limit: 1,
        );
        expect(result.hits, isNotEmpty);
        expect(
          result.hits.first.document.getString('url'),
          '/spells/fire/ember-lance',
        );
        await restored.dispose();
      } finally {
        await exampleRoot.delete(recursive: true);
      }
    });

    test(
      'default root resolves package path when run from repo root',
      () async {
      final sandboxRepo = await Directory.systemTemp.createTemp(
        'searchlight_validation_repo_',
      );
      final exampleRoot = Directory(
        '${sandboxRepo.path}/packages/searchlight/example',
      );
      final localDir = Directory('${exampleRoot.path}/.local');
      final sourceDir = Directory('${localDir.path}/source');
      final corpusFile = File('${localDir.path}/generated_search_corpus.json');
      final snapshotFile = File(
        '${localDir.path}/generated_search_snapshot.json',
      );
      final pubspec = File('${exampleRoot.path}/pubspec.yaml');
      final originalCurrent = Directory.current;

      try {
        await sourceDir.create(recursive: true);
        await pubspec.create(recursive: true);
        pubspec.writeAsStringSync('name: searchlight_example\n');

        final rulesDir = Directory('${sourceDir.path}/rules');
        await rulesDir.create(recursive: true);
        File('${rulesDir.path}/cover.md').writeAsStringSync(
          '# Cover\n'
          '\n'
          'Use terrain to improve defense.\n',
        );

        Directory.current = sandboxRepo;
        await buildValidationAssets();

        expect(corpusFile.existsSync(), isTrue);
        expect(snapshotFile.existsSync(), isTrue);
      } finally {
        Directory.current = originalCurrent;
        await sandboxRepo.delete(recursive: true);
      }
      },
    );
  });
}
