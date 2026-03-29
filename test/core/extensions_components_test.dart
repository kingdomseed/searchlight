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

    test('plugin tokenizer conflicts with a user tokenizer component', () {
      expect(
        () => resolveExtensions(
          defaults: defaultSearchlightComponents,
          overrides: SearchlightComponents(tokenizer: Tokenizer()),
          plugins: [
            SearchlightPlugin(
              name: 'plugin-tokenizer',
              components: SearchlightComponents(
                tokenizer: Tokenizer(stopWords: ['the']),
              ),
            ),
          ],
        ),
        throwsA(
          isA<ExtensionResolutionException>().having(
            (error) => error.message,
            'message',
            contains('tokenizer'),
          ),
        ),
      );
    });

    test('user-supplied components conflict with plugin components', () {
      final overrideIndex = SearchlightIndexComponent(
        id: 'test.index.override',
        create: ({
          required schema,
          required algorithm,
        }) => SearchIndex.create(schema: schema, algorithm: algorithm),
      );
      final pluginIndex = SearchlightIndexComponent(
        id: 'test.index.plugin',
        create: ({
          required schema,
          required algorithm,
        }) => SearchIndex.create(schema: schema, algorithm: algorithm),
      );

      expect(
        () => resolveExtensions(
          defaults: defaultSearchlightComponents,
          overrides: SearchlightComponents(index: overrideIndex),
          plugins: [
            SearchlightPlugin(
              name: 'plugin-index',
              components: SearchlightComponents(index: pluginIndex),
            ),
          ],
        ),
        throwsA(
          isA<ExtensionResolutionException>().having(
            (error) => error.message,
            'message',
            contains('index'),
          ),
        ),
      );
    });

    test('plugin components conflict with earlier plugin components', () {
      final firstIndex = SearchlightIndexComponent(
        id: 'test.index.first',
        create: ({
          required schema,
          required algorithm,
        }) => SearchIndex.create(schema: schema, algorithm: algorithm),
      );
      final secondIndex = SearchlightIndexComponent(
        id: 'test.index.second',
        create: ({
          required schema,
          required algorithm,
        }) => SearchIndex.create(schema: schema, algorithm: algorithm),
      );

      expect(
        () => resolveExtensions(
          defaults: defaultSearchlightComponents,
          plugins: [
            SearchlightPlugin(
              name: 'first-plugin',
              components: SearchlightComponents(index: firstIndex),
            ),
            SearchlightPlugin(
              name: 'second-plugin',
              components: SearchlightComponents(index: secondIndex),
            ),
          ],
        ),
        throwsA(
          isA<ExtensionResolutionException>().having(
            (error) => error.message,
            'message',
            allOf(contains('index'), contains('second-plugin')),
          ),
        ),
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
