import 'package:searchlight/src/extensions/components.dart';
import 'package:searchlight/src/indexing/index_manager.dart';
import 'package:searchlight/src/indexing/sort_index.dart';
import 'package:searchlight/src/pinning/pinning_store.dart';
import 'package:searchlight/src/storage/documents_store.dart';

/// Stable identifier for Searchlight's built-in index component.
const searchlightDefaultIndexComponentId = 'searchlight.index.default';

/// Stable identifier for Searchlight's built-in sorter component.
const searchlightDefaultSorterComponentId = 'searchlight.sorter.default';

/// Stable identifier for Searchlight's built-in documents-store component.
const searchlightDefaultDocumentsStoreComponentId =
    'searchlight.documents.default';

/// Stable identifier for Searchlight's built-in pinning component.
const searchlightDefaultPinningComponentId = 'searchlight.pinning.default';

/// Built-in search index component descriptor.
final defaultSearchlightIndexComponent = SearchlightIndexComponent(
  id: searchlightDefaultIndexComponentId,
  create: ({
    required schema,
    required algorithm,
  }) =>
      SearchIndex.create(schema: schema, algorithm: algorithm),
);

/// Built-in sorter component descriptor.
final defaultSearchlightSorterComponent = SearchlightSorterComponent(
  id: searchlightDefaultSorterComponentId,
  create: ({required language}) => SortIndex(language: language),
);

/// Built-in documents-store component descriptor.
const defaultSearchlightDocumentsStoreComponent =
    SearchlightDocumentsStoreComponent(
  id: searchlightDefaultDocumentsStoreComponentId,
  create: InMemorySearchlightDocumentsStore.new,
);

/// Built-in pinning component descriptor.
const defaultSearchlightPinningComponent = SearchlightPinningComponent(
  id: searchlightDefaultPinningComponentId,
  create: InMemorySearchlightPinningStore.new,
);

/// Built-in component bundle used when no overrides are provided.
final defaultSearchlightComponents = SearchlightComponents(
  index: defaultSearchlightIndexComponent,
  sorter: defaultSearchlightSorterComponent,
  documentsStore: defaultSearchlightDocumentsStoreComponent,
  pinning: defaultSearchlightPinningComponent,
);
