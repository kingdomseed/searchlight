import 'dart:async';

/// Generic document payload shape used by the extension API.
typedef SearchlightRecord = Map<String, Object?>;

/// Unstructured search parameter payload passed through lifecycle hooks.
typedef SearchlightSearchParams = Map<String, Object?>;

/// Callback signature for create-time lifecycle hooks.
typedef SearchlightAfterCreateHook = FutureOr<void> Function(Object db);

/// Callback signature for single-document lifecycle hooks.
typedef SearchlightSingleHook = FutureOr<void> Function(
  Object db,
  String id,
  SearchlightRecord? doc,
);

/// Callback signature for batch lifecycle hooks that receive documents.
typedef SearchlightMultipleDocsHook = FutureOr<void> Function(
  Object db,
  List<SearchlightRecord> docs,
);

/// Callback signature for batch lifecycle hooks that receive document IDs.
typedef SearchlightMultipleIdsHook = FutureOr<void> Function(
  Object db,
  List<String> ids,
);

/// Callback signature for the pre-search hook.
typedef SearchlightBeforeSearchHook = FutureOr<void> Function(
  Object db,
  SearchlightSearchParams params,
  String language,
);

/// Callback signature for the post-search hook.
typedef SearchlightAfterSearchHook = FutureOr<void> Function(
  Object db,
  SearchlightSearchParams params,
  String language,
  Object results,
);

/// Callback signature for load lifecycle hooks.
typedef SearchlightLoadHook = FutureOr<void> Function(Object db, Object raw);

/// Container for extension lifecycle hooks.
final class SearchlightHooks {
  /// Creates a hook bundle contributed by the app or a plugin.
  const SearchlightHooks({
    this.afterCreate,
    this.beforeInsert,
    this.afterInsert,
    this.beforeRemove,
    this.afterRemove,
    this.beforeUpdate,
    this.afterUpdate,
    this.beforeUpsert,
    this.afterUpsert,
    this.beforeInsertMultiple,
    this.afterInsertMultiple,
    this.beforeRemoveMultiple,
    this.afterRemoveMultiple,
    this.beforeUpdateMultiple,
    this.afterUpdateMultiple,
    this.beforeUpsertMultiple,
    this.afterUpsertMultiple,
    this.beforeSearch,
    this.afterSearch,
    this.beforeLoad,
    this.afterLoad,
  });

  /// Runs once after database creation completes.
  final SearchlightAfterCreateHook? afterCreate;

  /// Runs before a single insert.
  final SearchlightSingleHook? beforeInsert;

  /// Runs after a single insert.
  final SearchlightSingleHook? afterInsert;

  /// Runs before a single remove.
  final SearchlightSingleHook? beforeRemove;

  /// Runs after a single remove.
  final SearchlightSingleHook? afterRemove;

  /// Runs before a single update.
  final SearchlightSingleHook? beforeUpdate;

  /// Runs after a single update.
  final SearchlightSingleHook? afterUpdate;

  /// Runs before a single upsert.
  final SearchlightSingleHook? beforeUpsert;

  /// Runs after a single upsert.
  final SearchlightSingleHook? afterUpsert;

  /// Runs before a batch insert.
  final SearchlightMultipleDocsHook? beforeInsertMultiple;

  /// Runs after a batch insert.
  final SearchlightMultipleDocsHook? afterInsertMultiple;

  /// Runs before a batch remove.
  final SearchlightMultipleIdsHook? beforeRemoveMultiple;

  /// Runs after a batch remove.
  final SearchlightMultipleIdsHook? afterRemoveMultiple;

  /// Runs before a batch update.
  final SearchlightMultipleIdsHook? beforeUpdateMultiple;

  /// Runs after a batch update.
  final SearchlightMultipleIdsHook? afterUpdateMultiple;

  /// Runs before a batch upsert.
  final SearchlightMultipleDocsHook? beforeUpsertMultiple;

  /// Runs after a batch upsert.
  final SearchlightMultipleIdsHook? afterUpsertMultiple;

  /// Runs before search execution begins.
  final SearchlightBeforeSearchHook? beforeSearch;

  /// Runs after search execution completes.
  final SearchlightAfterSearchHook? afterSearch;

  /// Runs before a snapshot is loaded into a database instance.
  final SearchlightLoadHook? beforeLoad;

  /// Runs after a snapshot has been loaded into a database instance.
  final SearchlightLoadHook? afterLoad;
}
