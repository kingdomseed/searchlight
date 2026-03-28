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
    final beforeInsertMultiple = <SearchlightMultipleDocsHook>[];
    final afterInsertMultiple = <SearchlightMultipleDocsHook>[];
    final beforeRemoveMultiple = <SearchlightMultipleIdsHook>[];
    final afterRemoveMultiple = <SearchlightMultipleIdsHook>[];
    final beforeUpdateMultiple = <SearchlightMultipleIdsHook>[];
    final afterUpdateMultiple = <SearchlightMultipleIdsHook>[];
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
  final List<SearchlightMultipleDocsHook> beforeInsertMultiple;
  final List<SearchlightMultipleDocsHook> afterInsertMultiple;
  final List<SearchlightMultipleIdsHook> beforeRemoveMultiple;
  final List<SearchlightMultipleIdsHook> afterRemoveMultiple;
  final List<SearchlightMultipleIdsHook> beforeUpdateMultiple;
  final List<SearchlightMultipleIdsHook> afterUpdateMultiple;
  final List<SearchlightBeforeSearchHook> beforeSearch;
  final List<SearchlightAfterSearchHook> afterSearch;
  final List<SearchlightLoadHook> beforeLoad;
  final List<SearchlightLoadHook> afterLoad;

  Future<void> runAfterCreate({required Object db}) =>
      _runAfterCreateHook(afterCreate, db: db);

  Future<void> runBeforeInsert({
    required Object db,
    required String id,
    required SearchlightRecord? doc,
  }) =>
      _runSingleHook(beforeInsert, db: db, id: id, doc: doc);

  Future<void> runAfterInsert({
    required Object db,
    required String id,
    required SearchlightRecord? doc,
  }) =>
      _runSingleHook(afterInsert, db: db, id: id, doc: doc);

  Future<void> runBeforeRemove({
    required Object db,
    required String id,
    required SearchlightRecord? doc,
  }) =>
      _runSingleHook(beforeRemove, db: db, id: id, doc: doc);

  Future<void> runAfterRemove({
    required Object db,
    required String id,
    required SearchlightRecord? doc,
  }) =>
      _runSingleHook(afterRemove, db: db, id: id, doc: doc);

  Future<void> runBeforeUpdate({
    required Object db,
    required String id,
    required SearchlightRecord? doc,
  }) =>
      _runSingleHook(beforeUpdate, db: db, id: id, doc: doc);

  Future<void> runAfterUpdate({
    required Object db,
    required String id,
    required SearchlightRecord? doc,
  }) =>
      _runSingleHook(afterUpdate, db: db, id: id, doc: doc);

  Future<void> runBeforeUpsert({
    required Object db,
    required String id,
    required SearchlightRecord? doc,
  }) =>
      _runSingleHook(beforeUpsert, db: db, id: id, doc: doc);

  Future<void> runAfterUpsert({
    required Object db,
    required String id,
    required SearchlightRecord? doc,
  }) =>
      _runSingleHook(afterUpsert, db: db, id: id, doc: doc);

  Future<void> runBeforeInsertMultiple({
    required Object db,
    required List<SearchlightRecord> docs,
  }) =>
      _runMultipleDocsHook(beforeInsertMultiple, db: db, docs: docs);

  Future<void> runAfterInsertMultiple({
    required Object db,
    required List<SearchlightRecord> docs,
  }) =>
      _runMultipleDocsHook(afterInsertMultiple, db: db, docs: docs);

  Future<void> runBeforeRemoveMultiple({
    required Object db,
    required List<String> ids,
  }) =>
      _runMultipleIdsHook(beforeRemoveMultiple, db: db, ids: ids);

  Future<void> runAfterRemoveMultiple({
    required Object db,
    required List<String> ids,
  }) =>
      _runMultipleIdsHook(afterRemoveMultiple, db: db, ids: ids);

  Future<void> runBeforeUpdateMultiple({
    required Object db,
    required List<String> ids,
  }) =>
      _runMultipleIdsHook(beforeUpdateMultiple, db: db, ids: ids);

  Future<void> runAfterUpdateMultiple({
    required Object db,
    required List<String> ids,
  }) =>
      _runMultipleIdsHook(afterUpdateMultiple, db: db, ids: ids);

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

  Future<void> runBeforeLoad({
    required Object db,
    required Object raw,
  }) =>
      _runLoadHook(beforeLoad, db: db, raw: raw);

  Future<void> runAfterLoad({
    required Object db,
    required Object raw,
  }) =>
      _runLoadHook(afterLoad, db: db, raw: raw);

  static void _addIfPresent<T>(List<T> target, T? candidate) {
    if (candidate != null) {
      target.add(candidate);
    }
  }

  static Future<void> _runAfterCreateHook(
    List<SearchlightAfterCreateHook> hooks, {
    required Object db,
  }) async {
    for (final hook in hooks) {
      await hook(db);
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

  static Future<void> _runMultipleDocsHook(
    List<SearchlightMultipleDocsHook> hooks, {
    required Object db,
    required List<SearchlightRecord> docs,
  }) async {
    for (final hook in hooks) {
      await hook(db, docs);
    }
  }

  static Future<void> _runMultipleIdsHook(
    List<SearchlightMultipleIdsHook> hooks, {
    required Object db,
    required List<String> ids,
  }) async {
    for (final hook in hooks) {
      await hook(db, ids);
    }
  }

  static Future<void> _runLoadHook(
    List<SearchlightLoadHook> hooks, {
    required Object db,
    required Object raw,
  }) async {
    for (final hook in hooks) {
      await hook(db, raw);
    }
  }
}
