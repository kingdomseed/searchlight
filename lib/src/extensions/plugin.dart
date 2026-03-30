import 'package:searchlight/src/core/schema.dart';
import 'package:searchlight/src/extensions/components.dart';
import 'package:searchlight/src/extensions/hook_types.dart';
import 'package:searchlight/src/extensions/hooks.dart';

/// Produces plugin-owned component contributions for a schema.
typedef SearchlightPluginComponentsFactory = SearchlightComponents Function(
  Schema schema,
);

/// A create-time extension unit for Searchlight.
final class SearchlightPlugin<TExtra extends Object?> {
  /// Creates a plugin contribution bundle for `Searchlight.create()`.
  const SearchlightPlugin({
    required this.name,
    this.extra,
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
    this.getComponents,
  });

  /// Human-readable plugin name used in diagnostics and conflict errors.
  final String name;

  /// Optional plugin-specific metadata bag carried at create time.
  final TExtra? extra;

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

  /// Component overrides contributed by this plugin for a specific schema.
  final SearchlightPluginComponentsFactory? getComponents;

  /// Whether this plugin contributes any lifecycle hooks.
  bool get hasHooks =>
      afterCreate != null ||
      beforeInsert != null ||
      afterInsert != null ||
      beforeRemove != null ||
      afterRemove != null ||
      beforeUpdate != null ||
      afterUpdate != null ||
      beforeUpsert != null ||
      afterUpsert != null ||
      beforeInsertMultiple != null ||
      afterInsertMultiple != null ||
      beforeRemoveMultiple != null ||
      afterRemoveMultiple != null ||
      beforeUpdateMultiple != null ||
      afterUpdateMultiple != null ||
      beforeUpsertMultiple != null ||
      afterUpsertMultiple != null ||
      beforeSearch != null ||
      afterSearch != null ||
      beforeLoad != null ||
      afterLoad != null;

  /// Internal hook bundle used by the runtime collector.
  SearchlightHooks toHooks() => SearchlightHooks(
    afterCreate: afterCreate,
    beforeInsert: beforeInsert,
    afterInsert: afterInsert,
    beforeRemove: beforeRemove,
    afterRemove: afterRemove,
    beforeUpdate: beforeUpdate,
    afterUpdate: afterUpdate,
    beforeUpsert: beforeUpsert,
    afterUpsert: afterUpsert,
    beforeInsertMultiple: beforeInsertMultiple,
    afterInsertMultiple: afterInsertMultiple,
    beforeRemoveMultiple: beforeRemoveMultiple,
    afterRemoveMultiple: afterRemoveMultiple,
    beforeUpdateMultiple: beforeUpdateMultiple,
    afterUpdateMultiple: afterUpdateMultiple,
    beforeUpsertMultiple: beforeUpsertMultiple,
    afterUpsertMultiple: afterUpsertMultiple,
    beforeSearch: beforeSearch,
    afterSearch: afterSearch,
    beforeLoad: beforeLoad,
    afterLoad: afterLoad,
  );
}
