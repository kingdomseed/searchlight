import 'package:searchlight/src/core/schema.dart';
import 'package:searchlight/src/core/search_algorithm.dart';
import 'package:searchlight/src/extensions/hooks.dart';
import 'package:searchlight/src/indexing/index_manager.dart';
import 'package:searchlight/src/indexing/sort_index.dart';
import 'package:searchlight/src/storage/documents_store.dart';
import 'package:searchlight/src/text/tokenizer.dart';

/// Factory for constructing a search index implementation.
typedef SearchlightIndexFactory = SearchIndex Function({
  required Schema schema,
  required SearchAlgorithm algorithm,
});

/// Factory for constructing a sort index implementation.
typedef SearchlightSorterFactory =
    SortIndex Function({required String language});

/// Factory for constructing a documents-store implementation.
typedef SearchlightDocumentsStoreFactory = SearchlightDocumentsStore Function();

/// Validates a document against the active schema and returns the failing path.
typedef SearchlightSchemaValidator =
    String? Function(SearchlightRecord doc, Schema schema);

/// Resolves the external document ID for a record at insert/upsert time.
typedef SearchlightDocumentIdResolver = String Function(SearchlightRecord doc);

/// Extracts the properties Searchlight should index or sort for a record.
typedef SearchlightDocumentPropertiesResolver =
    Map<String, Object?> Function(
      SearchlightRecord doc,
      List<String> paths,
    );

/// Search index component descriptor with stable identity and factories.
final class SearchlightIndexComponent {
  /// Creates an index component descriptor.
  const SearchlightIndexComponent({
    required this.id,
    required this.create,
  });

  /// Stable component identity used in compatibility checks.
  final String id;

  /// Creates the index runtime for a database instance.
  final SearchlightIndexFactory create;
}

/// Sort index component descriptor with stable identity and factories.
final class SearchlightSorterComponent {
  /// Creates a sorter component descriptor.
  const SearchlightSorterComponent({
    required this.id,
    required this.create,
  });

  /// Stable component identity used in compatibility checks.
  final String id;

  /// Creates the sorter runtime for a database instance.
  final SearchlightSorterFactory create;
}

/// Documents-store component descriptor with stable identity and factories.
final class SearchlightDocumentsStoreComponent {
  /// Creates a documents-store component descriptor.
  const SearchlightDocumentsStoreComponent({
    required this.id,
    required this.create,
  });

  /// Stable component identity used in compatibility checks.
  final String id;

  /// Creates the documents-store runtime for a database instance.
  final SearchlightDocumentsStoreFactory create;
}

/// Advanced extension override surface for Searchlight internals.
final class SearchlightComponents {
  /// Creates a bundle of extension component overrides.
  const SearchlightComponents({
    this.tokenizer,
    this.index,
    this.sorter,
    this.documentsStore,
    this.hooks,
    this.validateSchema,
    this.getDocumentIndexId,
    this.getDocumentProperties,
  });

  /// Replaces the database tokenizer at create time.
  final Tokenizer? tokenizer;

  /// Replaces the search index implementation.
  final SearchlightIndexComponent? index;

  /// Replaces the sort index implementation.
  final SearchlightSorterComponent? sorter;

  /// Replaces the documents-store implementation.
  final SearchlightDocumentsStoreComponent? documentsStore;

  /// Overrides the final resolved hook set.
  final SearchlightHooks? hooks;

  /// Replaces schema validation for insert/update/upsert operations.
  final SearchlightSchemaValidator? validateSchema;

  /// Replaces document ID resolution for insert/upsert operations.
  final SearchlightDocumentIdResolver? getDocumentIndexId;

  /// Replaces property extraction for indexing and sorting.
  final SearchlightDocumentPropertiesResolver? getDocumentProperties;
}
