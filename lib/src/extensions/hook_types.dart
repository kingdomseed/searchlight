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
