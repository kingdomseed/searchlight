import 'dart:async';

typedef SearchlightRecord = Map<String, Object?>;
typedef SearchlightSearchParams = Map<String, Object?>;

/// Callback signature for create-time lifecycle hooks.
typedef SearchlightAfterCreateHook = FutureOr<void> Function(Object db);
typedef SearchlightSingleHook = FutureOr<void> Function(
  Object db,
  String id,
  SearchlightRecord? doc,
);
typedef SearchlightMultipleDocsHook = FutureOr<void> Function(
  Object db,
  List<SearchlightRecord> docs,
);
typedef SearchlightMultipleIdsHook = FutureOr<void> Function(
  Object db,
  List<String> ids,
);
typedef SearchlightBeforeSearchHook = FutureOr<void> Function(
  Object db,
  SearchlightSearchParams params,
  String language,
);
typedef SearchlightAfterSearchHook = FutureOr<void> Function(
  Object db,
  SearchlightSearchParams params,
  String language,
  Object results,
);
typedef SearchlightLoadHook = FutureOr<void> Function(Object db, Object raw);

/// Container for extension lifecycle hooks.
final class SearchlightHooks {
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

  final SearchlightAfterCreateHook? afterCreate;
  final SearchlightSingleHook? beforeInsert;
  final SearchlightSingleHook? afterInsert;
  final SearchlightSingleHook? beforeRemove;
  final SearchlightSingleHook? afterRemove;
  final SearchlightSingleHook? beforeUpdate;
  final SearchlightSingleHook? afterUpdate;
  final SearchlightSingleHook? beforeUpsert;
  final SearchlightSingleHook? afterUpsert;
  final SearchlightMultipleDocsHook? beforeInsertMultiple;
  final SearchlightMultipleDocsHook? afterInsertMultiple;
  final SearchlightMultipleIdsHook? beforeRemoveMultiple;
  final SearchlightMultipleIdsHook? afterRemoveMultiple;
  final SearchlightMultipleIdsHook? beforeUpdateMultiple;
  final SearchlightMultipleIdsHook? afterUpdateMultiple;
  final SearchlightMultipleDocsHook? beforeUpsertMultiple;
  final SearchlightMultipleIdsHook? afterUpsertMultiple;
  final SearchlightBeforeSearchHook? beforeSearch;
  final SearchlightAfterSearchHook? afterSearch;
  final SearchlightLoadHook? beforeLoad;
  final SearchlightLoadHook? afterLoad;
}
