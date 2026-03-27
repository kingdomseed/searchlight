import 'package:flutter_test/flutter_test.dart';
import 'package:searchlight_example/src/search_index_service.dart';
import 'package:searchlight_example/src/validation_record.dart';

void main() {
  test('search service matches ember in title and content', () async {
    final records = [
      ValidationRecord.fromMap(const {
        'url': '/guide/spells/ember-lance',
        'title': 'Ember Lance',
        'content':
            'A precise fire spell that launches a concentrated spear of heat.',
        'type': 'spell',
        'group': 'fire',
      }),
      ValidationRecord.fromMap(const {
        'url': '/guide/creatures/iron-boar',
        'title': 'Iron Boar',
        'content':
            'A heavily armored beast known for charging through shields.',
        'type': 'monster',
        'group': 'beasts',
      }),
    ];

    final source = const SearchIndexService().buildFromRecords(
      records: records,
      label: 'fixture',
      discoveredCount: records.length,
    );
    addTearDown(source.dispose);

    final results = const SearchIndexService().search(source, 'ember');

    expect(results, hasLength(1));
    expect(results.first.record.title, 'Ember Lance');
  });
}
