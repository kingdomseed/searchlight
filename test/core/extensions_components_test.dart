import 'package:searchlight/searchlight.dart';
import 'package:searchlight/src/extensions/component_ids.dart';
import 'package:searchlight/src/extensions/resolver.dart';
import 'package:test/test.dart';

void main() {
  group('extension components', () {
    test('default component identities are stable', () {
      final resolved = resolveExtensions(
        defaults: defaultSearchlightComponents,
      );

      expect(
        resolved.components.index?.id,
        searchlightDefaultIndexComponentId,
      );
      expect(
        resolved.components.sorter?.id,
        searchlightDefaultSorterComponentId,
      );
    });

    test('direct component overrides replace the targeted component', () {
      final overrideIndex = SearchlightIndexComponent(
        id: 'test.index.override',
        create: ({
          required schema,
          required algorithm,
        }) => SearchIndex.create(schema: schema, algorithm: algorithm),
      );

      final resolved = resolveExtensions(
        defaults: defaultSearchlightComponents,
        overrides: SearchlightComponents(index: overrideIndex),
      );

      expect(identical(resolved.components.index, overrideIndex), isTrue);
      expect(
        resolved.components.sorter?.id,
        searchlightDefaultSorterComponentId,
      );
    });

    test('database creation uses the resolved component graph', () {
      var indexCreateCalls = 0;
      var sorterCreateCalls = 0;
      late SearchAlgorithm capturedAlgorithm;
      String? capturedSorterLanguage;

      final indexComponent = SearchlightIndexComponent(
        id: 'test.index.runtime',
        create: ({
          required schema,
          required algorithm,
        }) {
          indexCreateCalls++;
          capturedAlgorithm = algorithm;
          return SearchIndex.create(schema: schema, algorithm: algorithm);
        },
      );
      final sorterComponent = SearchlightSorterComponent(
        id: 'test.sorter.runtime',
        create: ({required language}) {
          sorterCreateCalls++;
          capturedSorterLanguage = language;
          return SortIndex(language: language);
        },
      );

      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        algorithm: SearchAlgorithm.qps,
        language: 'en',
        components: SearchlightComponents(
          index: indexComponent,
          sorter: sorterComponent,
        ),
      );
      addTearDown(db.dispose);

      expect(indexCreateCalls, 1);
      expect(sorterCreateCalls, 1);
      expect(capturedAlgorithm, SearchAlgorithm.qps);
      expect(capturedSorterLanguage, 'english');
    });

    test('reindex preserves the resolved component graph', () {
      var indexCreateCalls = 0;
      var sorterCreateCalls = 0;

      final indexComponent = SearchlightIndexComponent(
        id: 'test.index.reindex',
        create: ({
          required schema,
          required algorithm,
        }) {
          indexCreateCalls++;
          return SearchIndex.create(schema: schema, algorithm: algorithm);
        },
      );
      final sorterComponent = SearchlightSorterComponent(
        id: 'test.sorter.reindex',
        create: ({required language}) {
          sorterCreateCalls++;
          return SortIndex(language: language);
        },
      );

      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        components: SearchlightComponents(
          index: indexComponent,
          sorter: sorterComponent,
        ),
      )..insert({'id': 'doc-1', 'title': 'One'});
      addTearDown(db.dispose);

      final reindexed = db.reindex(algorithm: SearchAlgorithm.qps);
      addTearDown(reindexed.dispose);

      expect(indexCreateCalls, 2);
      expect(sorterCreateCalls, 2);
      expect(reindexed.indexAlgorithm, SearchAlgorithm.qps);
      expect(reindexed.getById('doc-1'), isNotNull);
    });
  });
}
