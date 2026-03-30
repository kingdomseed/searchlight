import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:searchlight_example/src/folder_source_loader.dart';

void main() {
  test('desktop folder loader extracts live markdown records recursively', () async {
    final root = await Directory.systemTemp.createTemp(
      'searchlight_example_folder_loader_',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final spellsDir = Directory(p.join(root.path, 'spells'))..createSync();
    File(p.join(spellsDir.path, 'ember-lance.md')).writeAsStringSync(
      '# Ember Lance\n\nA focused spear of heat.',
    );
    File(p.join(spellsDir.path, 'notes.txt')).writeAsStringSync(
      'This file should not be indexed.',
    );

    final result = await createFolderSourceLoader().load(root.path);

    expect(result.discoveredMarkdownFiles, 1);
    expect(result.issues, isEmpty);
    expect(result.records, hasLength(1));

    final record = result.records.single;
    expect(record.id, 'spells/ember-lance.md');
    expect(record.pathLabel, 'spells/ember-lance.md');
    expect(record.title, 'Ember Lance');
    expect(record.content, 'A focused spear of heat.');
    expect(record.displayBody, '# Ember Lance\n\nA focused spear of heat.');
    expect(record.type, 'spell');
    expect(record.group, 'spells');
  });
}
