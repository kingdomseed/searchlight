import 'package:searchlight/src/extensions/hooks.dart';

/// Runtime hook registry with deterministic ordering.
final class SearchlightHookRuntime {
  SearchlightHookRuntime._({
    required this.afterCreate,
    required this.beforeInsert,
    required this.afterInsert,
    required this.beforeRemove,
    required this.afterRemove,
    required this.beforeUpdate,
    required this.afterUpdate,
    required this.beforeUpsert,
    required this.afterUpsert,
    required this.beforeInsertMultiple,
    required this.afterInsertMultiple,
    required this.beforeRemoveMultiple,
    required this.afterRemoveMultiple,
    required this.beforeUpdateMultiple,
    required this.afterUpdateMultiple,
    required this.beforeSearch,
    required this.afterSearch,
    required this.beforeLoad,
    required this.afterLoad,
  });

  factory SearchlightHookRuntime.fromHooks(Iterable<SearchlightHooks> hooks) {
    final afterCreate = <SearchlightAfterCreateHook>[];
    final beforeInsert = <SearchlightSingleHook>[];
    final afterInsert = <SearchlightSingleHook>[];
    final beforeRemove = <SearchlightSingleHook>[];
    final afterRemove = <SearchlightSingleHook>[];
    final beforeUpdate = <SearchlightSingleHook>[];
    final afterUpdate = <SearchlightSingleHook>[];
    final beforeUpsert = <SearchlightSingleHook>[];
    final afterUpsert = <SearchlightSingleHook>[];
    final beforeInsertMultiple = <SearchlightMultipleHook>[];
    final afterInsertMultiple = <SearchlightMultipleHook>[];
    final beforeRemoveMultiple = <SearchlightMultipleHook>[];
    final afterRemoveMultiple = <SearchlightMultipleHook>[];
    final beforeUpdateMultiple = <SearchlightMultipleHook>[];
    final afterUpdateMultiple = <SearchlightMultipleHook>[];
    final beforeSearch = <SearchlightBeforeSearchHook>[];
    final afterSearch = <SearchlightAfterSearchHook>[];
    final beforeLoad = <SearchlightLoadHook>[];
    final afterLoad = <SearchlightLoadHook>[];

    for (final hookSet in hooks) {
      _addIfPresent(afterCreate, hookSet.afterCreate);
      _addIfPresent(beforeInsert, hookSet.beforeInsert);
      _addIfPresent(afterInsert, hookSet.afterInsert);
      _addIfPresent(beforeRemove, hookSet.beforeRemove);
      _addIfPresent(afterRemove, hookSet.afterRemove);
      _addIfPresent(beforeUpdate, hookSet.beforeUpdate);
      _addIfPresent(afterUpdate, hookSet.afterUpdate);
      _addIfPresent(beforeUpsert, hookSet.beforeUpsert);
      _addIfPresent(afterUpsert, hookSet.afterUpsert);
      _addIfPresent(beforeInsertMultiple, hookSet.beforeInsertMultiple);
      _addIfPresent(afterInsertMultiple, hookSet.afterInsertMultiple);
      _addIfPresent(beforeRemoveMultiple, hookSet.beforeRemoveMultiple);
      _addIfPresent(afterRemoveMultiple, hookSet.afterRemoveMultiple);
      _addIfPresent(beforeUpdateMultiple, hookSet.beforeUpdateMultiple);
      _addIfPresent(afterUpdateMultiple, hookSet.afterUpdateMultiple);
      _addIfPresent(beforeSearch, hookSet.beforeSearch);
      _addIfPresent(afterSearch, hookSet.afterSearch);
      _addIfPresent(beforeLoad, hookSet.beforeLoad);
      _addIfPresent(afterLoad, hookSet.afterLoad);
    }

    return SearchlightHookRuntime._(
      afterCreate: List.unmodifiable(afterCreate),
      beforeInsert: List.unmodifiable(beforeInsert),
      afterInsert: List.unmodifiable(afterInsert),
      beforeRemove: List.unmodifiable(beforeRemove),
      afterRemove: List.unmodifiable(afterRemove),
      beforeUpdate: List.unmodifiable(beforeUpdate),
      afterUpdate: List.unmodifiable(afterUpdate),
      beforeUpsert: List.unmodifiable(beforeUpsert),
      afterUpsert: List.unmodifiable(afterUpsert),
      beforeInsertMultiple: List.unmodifiable(beforeInsertMultiple),
      afterInsertMultiple: List.unmodifiable(afterInsertMultiple),
      beforeRemoveMultiple: List.unmodifiable(beforeRemoveMultiple),
      afterRemoveMultiple: List.unmodifiable(afterRemoveMultiple),
      beforeUpdateMultiple: List.unmodifiable(beforeUpdateMultiple),
      afterUpdateMultiple: List.unmodifiable(afterUpdateMultiple),
      beforeSearch: List.unmodifiable(beforeSearch),
      afterSearch: List.unmodifiable(afterSearch),
      beforeLoad: List.unmodifiable(beforeLoad),
      afterLoad: List.unmodifiable(afterLoad),
    );
  }

  final List<SearchlightAfterCreateHook> afterCreate;
  final List<SearchlightSingleHook> beforeInsert;
  final List<SearchlightSingleHook> afterInsert;
  final List<SearchlightSingleHook> beforeRemove;
  final List<SearchlightSingleHook> afterRemove;
  final List<SearchlightSingleHook> beforeUpdate;
  final List<SearchlightSingleHook> afterUpdate;
  final List<SearchlightSingleHook> beforeUpsert;
  final List<SearchlightSingleHook> afterUpsert;
  final List<SearchlightMultipleHook> beforeInsertMultiple;
  final List<SearchlightMultipleHook> afterInsertMultiple;
  final List<SearchlightMultipleHook> beforeRemoveMultiple;
  final List<SearchlightMultipleHook> afterRemoveMultiple;
  final List<SearchlightMultipleHook> beforeUpdateMultiple;
  final List<SearchlightMultipleHook> afterUpdateMultiple;
  final List<SearchlightBeforeSearchHook> beforeSearch;
  final List<SearchlightAfterSearchHook> afterSearch;
  final List<SearchlightLoadHook> beforeLoad;
  final List<SearchlightLoadHook> afterLoad;

  Future<void> runBeforeInsert({
    required Object db,
    required String id,
    required SearchlightRecord? doc,
  }) =>
      _runSingleHook(beforeInsert, db: db, id: id, doc: doc);

  Future<void> runBeforeUpdate({
    required Object db,
    required String id,
    required SearchlightRecord? doc,
  }) =>
      _runSingleHook(beforeUpdate, db: db, id: id, doc: doc);

  Future<void> runBeforeInsertMultiple({
    required Object db,
    required List<String> ids,
    required List<SearchlightRecord>? docs,
  }) =>
      _runMultipleHook(beforeInsertMultiple, db: db, ids: ids, docs: docs);

  Future<void> runBeforeSearch({
    required Object db,
    required SearchlightSearchParams params,
    required String language,
  }) async {
    for (final hook in beforeSearch) {
      await hook(db, params, language);
    }
  }

  Future<void> runAfterSearch({
    required Object db,
    required SearchlightSearchParams params,
    required String language,
    required Object results,
  }) async {
    for (final hook in afterSearch) {
      await hook(db, params, language, results);
    }
  }

  static void _addIfPresent<T>(List<T> target, T? candidate) {
    if (candidate != null) {
      target.add(candidate);
    }
  }

  static Future<void> _runSingleHook(
    List<SearchlightSingleHook> hooks, {
    required Object db,
    required String id,
    required SearchlightRecord? doc,
  }) async {
    for (final hook in hooks) {
      await hook(db, id, doc);
    }
  }

  static Future<void> _runMultipleHook(
    List<SearchlightMultipleHook> hooks, {
    required Object db,
    required List<String> ids,
    required List<SearchlightRecord>? docs,
  }) async {
    for (final hook in hooks) {
      await hook(db, ids, docs);
    }
  }
}
