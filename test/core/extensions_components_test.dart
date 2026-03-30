import 'package:searchlight/searchlight.dart';
import 'package:searchlight/src/extensions/component_ids.dart';
import 'package:searchlight/src/extensions/resolver.dart';
import 'package:test/test.dart';

import '../helpers/extensions/test_index_plugin.dart';

void main() {
  group('extension components', () {
    final schema = Schema({
      'title': const TypedField(SchemaType.string),
    });

    test('default component identities are stable', () {
      final resolved = resolveExtensions(
        schema: schema,
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
      expect(
        resolved.components.documentsStore?.id,
        searchlightDefaultDocumentsStoreComponentId,
      );
      expect(
        resolved.components.pinning?.id,
        searchlightDefaultPinningComponentId,
      );
    });

    test('direct component overrides replace the targeted component', () {
      final overrideIndex = SearchlightIndexComponent(
        id: 'test.index.override',
        create: ({
          required schema,
          required algorithm,
        }) =>
            SearchIndex.create(schema: schema, algorithm: algorithm),
      );

      final resolved = resolveExtensions(
        schema: schema,
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
          schema: schema,
          defaults: defaultSearchlightComponents,
          overrides: SearchlightComponents(tokenizer: Tokenizer()),
          plugins: [
            SearchlightPlugin(
              name: 'plugin-tokenizer',
              getComponents: (_) => SearchlightComponents(
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

    test('plugin documentsStore conflicts with a user documentsStore', () {
      final overrideStore = SearchlightDocumentsStoreComponent(
        id: 'test.docs.override',
        create: () => throw UnimplementedError(),
      );

      expect(
        () => resolveExtensions(
          schema: schema,
          defaults: defaultSearchlightComponents,
          overrides: SearchlightComponents(documentsStore: overrideStore),
          plugins: [
            SearchlightPlugin(
              name: 'plugin-docs',
              getComponents: (_) => SearchlightComponents(
                documentsStore: SearchlightDocumentsStoreComponent(
                  id: 'test.docs.plugin',
                  create: () => throw UnimplementedError(),
                ),
              ),
            ),
          ],
        ),
        throwsA(
          isA<ExtensionResolutionException>().having(
            (error) => error.message,
            'message',
            contains('documentsStore'),
          ),
        ),
      );
    });

    test('plugin pinning conflicts with a user pinning component', () {
      const overridePinning = SearchlightPinningComponent(
        id: 'test.pinning.override',
        create: InMemorySearchlightPinningStore.new,
      );

      expect(
        () => resolveExtensions(
          schema: schema,
          defaults: defaultSearchlightComponents,
          overrides: const SearchlightComponents(pinning: overridePinning),
          plugins: [
            const SearchlightPlugin(
              name: 'plugin-pinning',
              getComponents: _pinningPluginComponents,
            ),
          ],
        ),
        throwsA(
          isA<ExtensionResolutionException>().having(
            (error) => error.message,
            'message',
            contains('pinning'),
          ),
        ),
      );
    });

    test(
      'plugin formatElapsedTime conflicts with a user formatter component',
      () {
        SearchlightElapsedTime overrideFormatter(int elapsedNanoseconds) =>
            SearchlightElapsedTime(
              raw: elapsedNanoseconds,
              formatted: '$elapsedNanoseconds ns',
            );

        expect(
          () => resolveExtensions(
            schema: schema,
            defaults: defaultSearchlightComponents,
            overrides: SearchlightComponents(
              formatElapsedTime: overrideFormatter,
            ),
            plugins: [
              SearchlightPlugin(
                name: 'plugin-elapsed',
                getComponents: (_) => SearchlightComponents(
                  formatElapsedTime: (elapsedNanoseconds) =>
                      SearchlightElapsedTime(
                    raw: elapsedNanoseconds,
                    formatted: 'plugin',
                  ),
                ),
              ),
            ],
          ),
          throwsA(
            isA<ExtensionResolutionException>().having(
              (error) => error.message,
              'message',
              contains('formatElapsedTime'),
            ),
          ),
        );
      },
    );

    test('user-supplied components conflict with plugin components', () {
      final overrideIndex = SearchlightIndexComponent(
        id: 'test.index.override',
        create: ({
          required schema,
          required algorithm,
        }) =>
            SearchIndex.create(schema: schema, algorithm: algorithm),
      );
      final pluginIndex = SearchlightIndexComponent(
        id: 'test.index.plugin',
        create: ({
          required schema,
          required algorithm,
        }) =>
            SearchIndex.create(schema: schema, algorithm: algorithm),
      );

      expect(
        () => resolveExtensions(
          schema: schema,
          defaults: defaultSearchlightComponents,
          overrides: SearchlightComponents(index: overrideIndex),
          plugins: [
            SearchlightPlugin(
              name: 'plugin-index',
              getComponents: (_) => SearchlightComponents(index: pluginIndex),
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
        }) =>
            SearchIndex.create(schema: schema, algorithm: algorithm),
      );
      final secondIndex = SearchlightIndexComponent(
        id: 'test.index.second',
        create: ({
          required schema,
          required algorithm,
        }) =>
            SearchIndex.create(schema: schema, algorithm: algorithm),
      );

      expect(
        () => resolveExtensions(
          schema: schema,
          defaults: defaultSearchlightComponents,
          plugins: [
            SearchlightPlugin(
              name: 'first-plugin',
              getComponents: (_) => SearchlightComponents(index: firstIndex),
            ),
            SearchlightPlugin(
              name: 'second-plugin',
              getComponents: (_) => SearchlightComponents(index: secondIndex),
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

    test('plugin getComponents receives the active schema', () {
      SearchlightPlugin<Object?> buildPlugin() {
        return SearchlightPlugin(
          name: 'schema-aware',
          getComponents: (schema) {
            expect(
              schema.fieldPaths,
              containsAll(<String>['title', 'meta.rank']),
            );
            return const SearchlightComponents();
          },
        );
      }

      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
          'meta': const NestedField({
            'rank': TypedField(SchemaType.number),
          }),
        }),
        plugins: [buildPlugin()],
      );
      addTearDown(db.dispose);
    });

    test('reindex preserves plugin-provided index components', () {
      final db = Searchlight.create(
        schema: Schema({
          'title': const TypedField(SchemaType.string),
        }),
        plugins: [
          testIndexPlugin(
            name: 'plugin-index',
            componentId: 'test.index.plugin',
            forcedAlgorithm: SearchAlgorithm.pt15,
          ),
        ],
      )..insert({
          'id': 'doc-1',
          'title': 'Ember Lance',
        });
      addTearDown(db.dispose);

      final reindexed = db.reindex(algorithm: SearchAlgorithm.qps);
      addTearDown(reindexed.dispose);

      expect(reindexed.indexAlgorithm, SearchAlgorithm.pt15);
      expect(reindexed.getById('doc-1'), isNotNull);
    });
  });
}

SearchlightComponents _pinningPluginComponents(Schema _) =>
    const SearchlightComponents(
      pinning: SearchlightPinningComponent(
        id: 'test.pinning.plugin',
        create: InMemorySearchlightPinningStore.new,
      ),
    );
