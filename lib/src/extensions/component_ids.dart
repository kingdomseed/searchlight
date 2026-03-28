import 'package:searchlight/src/extensions/components.dart';
import 'package:searchlight/src/indexing/index_manager.dart';
import 'package:searchlight/src/indexing/sort_index.dart';

const searchlightDefaultIndexComponentId = 'searchlight.index.default';
const searchlightDefaultSorterComponentId = 'searchlight.sorter.default';

final defaultSearchlightIndexComponent = SearchlightIndexComponent(
  id: searchlightDefaultIndexComponentId,
  create: ({
    required schema,
    required algorithm,
  }) => SearchIndex.create(schema: schema, algorithm: algorithm),
);

final defaultSearchlightSorterComponent = SearchlightSorterComponent(
  id: searchlightDefaultSorterComponentId,
  create: ({required language}) => SortIndex(language: language),
);

final defaultSearchlightComponents = SearchlightComponents(
  index: defaultSearchlightIndexComponent,
  sorter: defaultSearchlightSorterComponent,
);
