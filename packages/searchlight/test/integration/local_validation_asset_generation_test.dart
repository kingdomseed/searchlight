import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../tool/build_validation_assets.dart';

void main() {
  group('local validation asset generation', () {
    test('generator writes corpus and snapshot into .local', () async {
      final packageRoot = await Directory.systemTemp.createTemp(
        'searchlight_validation_assets_',
      );
      final localDir = Directory('${packageRoot.path}/.local');
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

        await buildValidationAssets(packageRoot: packageRoot);

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

        final snapshot =
            jsonDecode(snapshotFile.readAsStringSync()) as Map<String, dynamic>;
        expect(snapshot.containsKey('documents'), isTrue);
      } finally {
        await packageRoot.delete(recursive: true);
      }
    });
  });
}
