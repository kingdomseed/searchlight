import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

import '../helpers/extensions/test_index_plugin.dart';

void main() {
  group('extensions component plugin', () {
    test('plugin-provided index replacement is used by the database', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: [
          testIndexPlugin(
            name: 'pt15-plugin',
            componentId: 'test.index.pt15',
            forcedAlgorithm: SearchAlgorithm.pt15,
          ),
        ],
      );
      addTearDown(db.dispose);

      expect(db.algorithm, SearchAlgorithm.bm25);
      expect(db.indexAlgorithm, SearchAlgorithm.pt15);
    });

    test('replacement component can influence search behavior', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: [
          testIndexPlugin(
            name: 'pt15-plugin',
            componentId: 'test.index.pt15',
            forcedAlgorithm: SearchAlgorithm.pt15,
          ),
        ],
      )..insert({'id': 'doc-1', 'title': 'hello world'});
      addTearDown(db.dispose);

      final results = db.search(term: 'hel');

      expect(results.count, 1);
      expect(results.hits.first.id, 'doc-1');
    });

    test('direct components override still wins over plugin component', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: [
          testIndexPlugin(
            name: 'pt15-plugin',
            componentId: 'test.index.pt15',
            forcedAlgorithm: SearchAlgorithm.pt15,
          ),
        ],
        components: SearchlightComponents(
          index: testIndexComponent(
            id: 'test.index.qps',
            forcedAlgorithm: SearchAlgorithm.qps,
          ),
        ),
      );
      addTearDown(db.dispose);

      expect(db.indexAlgorithm, SearchAlgorithm.qps);
    });
  });
}
