import 'package:searchlight/src/core/schema.dart';
import 'package:searchlight/src/core/search_algorithm.dart';
import 'package:searchlight/src/extensions/hooks.dart';
import 'package:searchlight/src/indexing/index_manager.dart';
import 'package:searchlight/src/indexing/sort_index.dart';

typedef SearchlightIndexFactory = SearchIndex Function({
  required Schema schema,
  required SearchAlgorithm algorithm,
});
typedef SearchlightSorterFactory = SortIndex Function({required String language});

/// Search index component descriptor with stable identity and factories.
final class SearchlightIndexComponent {
  const SearchlightIndexComponent({
    required this.id,
    required this.create,
  });

  final String id;
  final SearchlightIndexFactory create;
}

/// Sort index component descriptor with stable identity and factories.
final class SearchlightSorterComponent {
  const SearchlightSorterComponent({
    required this.id,
    required this.create,
  });

  final String id;
  final SearchlightSorterFactory create;
}

/// Advanced extension override surface for Searchlight internals.
final class SearchlightComponents {
  const SearchlightComponents({
    this.index,
    this.sorter,
    this.hooks,
  });

  final SearchlightIndexComponent? index;
  final SearchlightSorterComponent? sorter;
  final SearchlightHooks? hooks;
}
