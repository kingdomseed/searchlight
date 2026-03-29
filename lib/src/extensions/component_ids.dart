import 'package:searchlight/src/extensions/components.dart';
import 'package:searchlight/src/indexing/index_manager.dart';
import 'package:searchlight/src/indexing/sort_index.dart';
import 'package:searchlight/src/pinning/pinning_store.dart';
import 'package:searchlight/src/storage/documents_store.dart';

const searchlightDefaultIndexComponentId = 'searchlight.index.default';
const searchlightDefaultSorterComponentId = 'searchlight.sorter.default';
const searchlightDefaultDocumentsStoreComponentId =
    'searchlight.documents.default';
const searchlightDefaultPinningComponentId = 'searchlight.pinning.default';

final defaultSearchlightIndexComponent = SearchlightIndexComponent(
  id: searchlightDefaultIndexComponentId,
  create: ({
    required schema,
    required algorithm,
  }) =>
      SearchIndex.create(schema: schema, algorithm: algorithm),
);

final defaultSearchlightSorterComponent = SearchlightSorterComponent(
  id: searchlightDefaultSorterComponentId,
  create: ({required language}) => SortIndex(language: language),
);

final defaultSearchlightDocumentsStoreComponent =
    SearchlightDocumentsStoreComponent(
  id: searchlightDefaultDocumentsStoreComponentId,
  create: InMemorySearchlightDocumentsStore.new,
);

final defaultSearchlightPinningComponent = SearchlightPinningComponent(
  id: searchlightDefaultPinningComponentId,
  create: InMemorySearchlightPinningStore.new,
);

final defaultSearchlightComponents = SearchlightComponents(
  index: defaultSearchlightIndexComponent,
  sorter: defaultSearchlightSorterComponent,
  documentsStore: defaultSearchlightDocumentsStoreComponent,
  pinning: defaultSearchlightPinningComponent,
);
