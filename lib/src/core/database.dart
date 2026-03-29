// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert' show jsonDecode, jsonEncode, utf8;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:searchlight/src/core/doc_id.dart';
import 'package:searchlight/src/core/document.dart';
import 'package:searchlight/src/core/exceptions.dart';
import 'package:searchlight/src/core/schema.dart';
import 'package:searchlight/src/core/search_algorithm.dart';
import 'package:searchlight/src/core/types.dart';
import 'package:searchlight/src/extensions/component_ids.dart';
import 'package:searchlight/src/extensions/components.dart';
import 'package:searchlight/src/extensions/hooks.dart';
import 'package:searchlight/src/extensions/plugin.dart';
import 'package:searchlight/src/extensions/resolver.dart';
import 'package:searchlight/src/extensions/runtime.dart';
import 'package:searchlight/src/indexing/index_manager.dart';
import 'package:searchlight/src/indexing/sort_index.dart';
import 'package:searchlight/src/persistence/cbor_serializer.dart';
import 'package:searchlight/src/persistence/format.dart';
import 'package:searchlight/src/persistence/json_serializer.dart';
import 'package:searchlight/src/persistence/storage.dart';
import 'package:searchlight/src/scoring/bm25.dart';
import 'package:searchlight/src/search/facets.dart' as facets_lib;
import 'package:searchlight/src/search/filters.dart';
import 'package:searchlight/src/search/grouping.dart' as grouping_lib;
import 'package:searchlight/src/storage/documents_store.dart';
import 'package:searchlight/src/text/tokenizer.dart';
import 'package:searchlight/src/trees/bkd_tree.dart';

export 'package:searchlight/src/core/search_algorithm.dart'
    show SearchAlgorithm;

typedef _SearchlightFutureSingleHook<T extends Object?> = Future<T> Function(
  Object,
  String,
  SearchlightRecord?,
);
typedef _SearchlightFutureMultipleIdsHook<T extends Object?> = Future<T>
    Function(Object, List<String>);
typedef _SearchlightFutureMultipleDocsHook<T extends Object?> = Future<T>
    Function(Object, List<SearchlightRecord>);
typedef _SearchlightFutureAfterCreateHook<T extends Object?> = Future<T>
    Function(Object);
typedef _SearchlightFutureBeforeSearchHook<T extends Object?> = Future<T>
    Function(Object, SearchlightSearchParams, String);
typedef _SearchlightFutureAfterSearchHook<T extends Object?> = Future<T>
    Function(Object, SearchlightSearchParams, String, Object);

/// A full-text search engine instance.
final class Searchlight {
  Searchlight._({
    required this.schema,
    required this.algorithm,
    required this.language,
    required ResolvedExtensions resolvedExtensions,
    required SearchlightHookRuntime hookRuntime,
    required bool hasCustomStemmer,
    required bool hasInjectedTokenizer,
    required SearchIndex index,
    required Tokenizer tokenizer,
    required SearchlightDocumentsStore documentsStore,
    required SortIndex sortIndex,
  })  : _index = index,
        _documentsStore = documentsStore,
        _resolvedExtensions = resolvedExtensions,
        _hookRuntime = hookRuntime,
        _tokenizer = tokenizer,
        _sortIndex = sortIndex,
        _hasCustomStemmer = hasCustomStemmer,
        _hasInjectedTokenizer = hasInjectedTokenizer;

  /// Creates a new Searchlight database.
  ///
  /// The [schema] defines the structure and types of documents that will be
  /// stored. The optional [algorithm] (default [SearchAlgorithm.bm25]) sets
  /// the scoring strategy. The optional [language] (default `'en'`) controls
  /// tokenization. The optional [stemming] overrides the default stemming
  /// behavior for the resolved tokenizer language. The optional [stopWords]
  /// supplies an explicit stop-word list for the internal tokenizer.
  /// The optional [useDefaultStopWords] enables the built-in stop-word list
  /// for the resolved tokenizer language.
  /// The optional [stemmer] injects a custom stemming function.
  /// The optional [allowDuplicates] preserves duplicate query/index tokens in
  /// tokenizer output.
  /// The optional [tokenizeSkipProperties] disables normal splitting and
  /// lowercasing for the named indexed string properties.
  /// The optional [stemmerSkipProperties] disables stemming for the named
  /// indexed string properties. The optional [tokenizer] injects a custom
  /// tokenizer instance directly.
  factory Searchlight.create({
    required Schema schema,
    SearchAlgorithm algorithm = SearchAlgorithm.bm25,
    String? language,
    bool? stemming,
    String Function(String)? stemmer,
    List<String>? stopWords,
    bool? useDefaultStopWords,
    bool allowDuplicates = false,
    Set<String> tokenizeSkipProperties = const {},
    Set<String> stemmerSkipProperties = const {},
    Tokenizer? tokenizer,
    List<SearchlightPlugin<Object?>> plugins = const [],
    SearchlightComponents? components,
  }) {
    final resolvedExtensions = resolveExtensions(
      defaults: defaultSearchlightComponents,
      plugins: plugins,
      overrides: components,
    );
    final componentTokenizer = resolvedExtensions.components.tokenizer;
    if (tokenizer != null && componentTokenizer != null) {
      throw ArgumentError(
        'Cannot provide both a direct tokenizer and an extension '
        'tokenizer component.',
      );
    }
    final injectedTokenizer = tokenizer ?? componentTokenizer;
    if (injectedTokenizer != null && language != null) {
      throw ArgumentError(
        'Cannot provide both language and a custom tokenizer.',
      );
    }
    if (injectedTokenizer != null &&
        (stemming != null ||
            stemmer != null ||
            stopWords != null ||
            useDefaultStopWords != null ||
            allowDuplicates ||
            tokenizeSkipProperties.isNotEmpty ||
            stemmerSkipProperties.isNotEmpty)) {
      throw ArgumentError(
        'Cannot provide built-in tokenizer configuration when a custom '
        'tokenizer is supplied.',
      );
    }

    final resolvedLanguage = language ?? 'en';
    final tokenizerLanguage = _resolveTokenizerLanguage(resolvedLanguage);

    final resolvedTokenizer = injectedTokenizer ??
        _createTokenizer(
          language: tokenizerLanguage,
          stemming: stemming,
          stemmer: stemmer,
          stopWords: stopWords,
          useDefaultStopWords: useDefaultStopWords,
          allowDuplicates: allowDuplicates,
          tokenizeSkipProperties: tokenizeSkipProperties,
          stemmerSkipProperties: stemmerSkipProperties,
        );
    final resolvedIndexComponent =
        resolvedExtensions.components.index ?? defaultSearchlightIndexComponent;
    final resolvedSorterComponent =
        resolvedExtensions.components.sorter ??
            defaultSearchlightSorterComponent;
    final resolvedDocumentsStoreComponent =
        resolvedExtensions.components.documentsStore ??
            defaultSearchlightDocumentsStoreComponent;
    final index = resolvedIndexComponent.create(
      schema: schema,
      algorithm: algorithm,
    );

    final db = Searchlight._(
      schema: schema,
      algorithm: algorithm,
      language: resolvedLanguage,
      resolvedExtensions: resolvedExtensions,
      hookRuntime: _createHookRuntime(resolvedExtensions),
      hasCustomStemmer: stemmer != null,
      hasInjectedTokenizer: injectedTokenizer != null,
      index: index,
      tokenizer: resolvedTokenizer,
      documentsStore: resolvedDocumentsStoreComponent.create(),
      sortIndex: resolvedSorterComponent.create(language: tokenizerLanguage),
    );
    db._runAfterCreateHooks(db._hookRuntime.afterCreate);
    return db;
  }

  /// Deserializes a [Searchlight] instance from a JSON-compatible map
  /// produced by [toJson].
  ///
  /// Matches Orama's `load(orama, raw)` pattern: checks the format version,
  /// restores the tokenizer configuration, then restores documents, index,
  /// and sorting components from the raw data. Legacy snapshots without
  /// serialized `index`/`sorting` component state are still supported by
  /// rebuilding those components through document re-insertion.
  ///
  /// Throws [SerializationException] if the format version is incompatible
  /// or the data is corrupt/missing.
  factory Searchlight.fromJson(
    Map<String, Object?> json, {
    List<SearchlightPlugin<Object?>> plugins = const [],
    SearchlightComponents? components,
  }) {
    // 1. Check format version.
    // E2 fix: reject future versions but accept current and past versions.
    // When a future version bump adds structural changes, add migration logic
    // here (e.g., `if (version == 1) json = _migrateFromV1(json);`).
    final version = json['formatVersion'];
    if (version is! int || version > currentFormatVersion) {
      throw SerializationException(
        'Incompatible format version: $version '
        '(max supported: $currentFormatVersion)',
      );
    }

    // 2. Restore algorithm
    final algorithmName = json['algorithm'] as String?;
    if (algorithmName == null) {
      throw const SerializationException('Missing "algorithm" in JSON');
    }
    final algorithm = SearchAlgorithm.values.firstWhere(
      (a) => a.name == algorithmName,
      orElse: () => throw SerializationException(
        'Unknown algorithm: $algorithmName',
      ),
    );

    // 3. Restore language
    final language = json['language'] as String?;
    if (language == null) {
      throw const SerializationException('Missing "language" in JSON');
    }
    final tokenizerLanguage = _resolveTokenizerLanguage(language);

    final rawTokenizerConfig = json['tokenizerConfig'];
    final tokenizerConfigJson = rawTokenizerConfig == null
        ? null
        : _asObjectMap(
            rawTokenizerConfig,
            'Invalid "tokenizerConfig" in JSON',
          );
    final tokenizerStemming = _asOptionalBool(
      tokenizerConfigJson,
      key: 'stemming',
      message: 'Invalid "tokenizerConfig.stemming" in JSON',
    );
    final tokenizerStopWords = _asOptionalStringList(
      tokenizerConfigJson,
      key: 'stopWords',
      message: 'Invalid "tokenizerConfig.stopWords" in JSON',
    );
    final tokenizerUseDefaultStopWords = _asOptionalBool(
      tokenizerConfigJson,
      key: 'useDefaultStopWords',
      message: 'Invalid "tokenizerConfig.useDefaultStopWords" in JSON',
    );
    final tokenizerAllowDuplicates = _asOptionalBool(
          tokenizerConfigJson,
          key: 'allowDuplicates',
          message: 'Invalid "tokenizerConfig.allowDuplicates" in JSON',
        ) ??
        false;
    final tokenizeSkipProperties = _asOptionalStringList(
          tokenizerConfigJson,
          key: 'tokenizeSkipProperties',
          message: 'Invalid "tokenizerConfig.tokenizeSkipProperties" in JSON',
        )?.toSet() ??
        const <String>{};
    final stemmerSkipProperties = _asOptionalStringList(
          tokenizerConfigJson,
          key: 'stemmerSkipProperties',
          message: 'Invalid "tokenizerConfig.stemmerSkipProperties" in JSON',
        )?.toSet() ??
        const <String>{};

    // 4. Restore schema
    final schemaJson = json['schema'];
    if (schemaJson is! Map<String, Object?>) {
      throw const SerializationException(
        'Missing or invalid "schema" in JSON',
      );
    }
    final schema = schemaFromJson(schemaJson);
    final resolvedExtensions = resolveExtensions(
      defaults: defaultSearchlightComponents,
      plugins: plugins,
      overrides: components,
    );
    if (resolvedExtensions.components.tokenizer != null) {
      throw const SerializationException(
        'Cannot restore with a custom tokenizer component.',
      );
    }
    _validateExtensionCompatibility(
      raw: json['extensionCompatibility'],
      resolvedExtensions: resolvedExtensions,
    );

    // 5. Restore tokenizer configuration
    late final Tokenizer tokenizer;
    try {
      tokenizer = _createTokenizer(
        language: tokenizerLanguage,
        stemming: tokenizerStemming,
        stopWords: tokenizerStopWords,
        useDefaultStopWords: tokenizerUseDefaultStopWords,
        allowDuplicates: tokenizerAllowDuplicates,
        tokenizeSkipProperties: tokenizeSkipProperties,
        stemmerSkipProperties: stemmerSkipProperties,
      );
    } catch (error) {
      if (error is! ArgumentError) {
        rethrow;
      }
      throw SerializationException(
        'Invalid tokenizer configuration in JSON: ${error.message}',
      );
    }

    // 6. Validate serialized documents and ID store
    final docsJson = json['documents'];
    if (docsJson is! Map<String, Object?>) {
      throw const SerializationException('Missing documents data');
    }
    final idStoreJson = json['internalDocumentIDStore'];
    if (idStoreJson is! Map<String, Object?>) {
      throw const SerializationException(
        'Missing or invalid "internalDocumentIDStore" in JSON',
      );
    }

    final hasSerializedIndex = json.containsKey('index');
    final hasSerializedSorting = json.containsKey('sorting');
    if (hasSerializedIndex != hasSerializedSorting) {
      throw const SerializationException(
        'Serialized snapshots must contain both "index" and "sorting" '
        'or neither.',
      );
    }

    final index = hasSerializedIndex
        ? SearchIndex.fromJson(
            _asObjectMap(json['index'], 'Missing or invalid "index" in JSON'),
            algorithm: algorithm,
          )
        : SearchIndex.create(schema: schema, algorithm: algorithm);
    final sortIndex = hasSerializedSorting
        ? SortIndex.fromJson(
            _asObjectMap(
              json['sorting'],
              'Missing or invalid "sorting" in JSON',
            ),
            fallbackLanguage: tokenizerLanguage,
          )
        : SortIndex(language: tokenizerLanguage);
    final resolvedDocumentsStoreComponent =
        resolvedExtensions.components.documentsStore ??
            defaultSearchlightDocumentsStoreComponent;

    final db = Searchlight._(
      schema: schema,
      algorithm: algorithm,
      language: language,
      resolvedExtensions: resolvedExtensions,
      hookRuntime: _createHookRuntime(resolvedExtensions),
      hasCustomStemmer: false,
      hasInjectedTokenizer: false,
      index: index,
      tokenizer: tokenizer,
      documentsStore: resolvedDocumentsStoreComponent.create(),
      sortIndex: sortIndex,
    );

    if (hasSerializedIndex) {
      _restoreSerializedDocuments(
        db,
        docsJson: docsJson,
        idStoreJson: idStoreJson,
      );
    } else {
      _restoreLegacyDocuments(
        db,
        docsJson: docsJson,
        idStoreJson: idStoreJson,
      );
    }

    return db;
  }

  /// The schema defining this database's document structure.
  final Schema schema;

  /// The scoring algorithm in use.
  final SearchAlgorithm algorithm;

  /// The language for tokenization and stemming.
  final String language;

  /// Resolved extension configuration captured at construction.
  // TODO(extension-runtime): consume retained extension state in hook/runtime wiring.
  final ResolvedExtensions _resolvedExtensions;
  final SearchlightHookRuntime _hookRuntime;

  /// The search index managing per-field trees and scoring data.
  final SearchIndex _index;

  /// The algorithm the underlying [SearchIndex] was created with.
  ///
  /// Exposed for testing/verification. Should match [algorithm].
  SearchAlgorithm get indexAlgorithm => _index.algorithm;

  /// The tokenizer for splitting text into normalized tokens.
  final Tokenizer _tokenizer;

  /// The sort index for efficient field-based sorting at search time.
  ///
  /// Populated during insert/remove, used during search when sortBy is
  /// provided. Matches Orama's `Sorter`.
  final SortIndex _sortIndex;

  final bool _hasCustomStemmer;
  final bool _hasInjectedTokenizer;

  List<String>? get _serializedStopWords =>
      _tokenizer.usesDefaultStopWords ? null : _tokenizer.stopWords;

  static const Map<String, String> _languageMap = <String, String>{
    'en': 'english',
    'de': 'german',
    'fi': 'finnish',
    'fr': 'french',
    'it': 'italian',
    'nl': 'dutch',
    'no': 'norwegian',
    'pt': 'portuguese',
    'ru': 'russian',
    'es': 'spanish',
    'sv': 'swedish',
  };

  static String _resolveTokenizerLanguage(String language) {
    return _languageMap[language] ?? language;
  }

  static Tokenizer _createTokenizer({
    required String language,
    bool? stemming,
    String Function(String)? stemmer,
    List<String>? stopWords,
    bool? useDefaultStopWords,
    bool allowDuplicates = false,
    Set<String> tokenizeSkipProperties = const {},
    Set<String> stemmerSkipProperties = const {},
  }) {
    return Tokenizer(
      language: language,
      stemming: stemming ?? false,
      stemmer: stemmer,
      stopWords: stopWords,
      useDefaultStopWords: useDefaultStopWords,
      allowDuplicates: allowDuplicates,
      tokenizeSkipProperties: tokenizeSkipProperties,
      stemmerSkipProperties: stemmerSkipProperties,
    );
  }

  static SearchlightHookRuntime _createHookRuntime(
    ResolvedExtensions resolvedExtensions,
  ) {
    final hookSets = <SearchlightHooks>[];
    for (final plugin in resolvedExtensions.plugins) {
      final pluginHooks = plugin.components?.hooks ?? plugin.hooks;
      if (pluginHooks != null) {
        hookSets.add(pluginHooks);
      }
    }
    final finalHooks = resolvedExtensions.components.hooks;
    if (finalHooks != null &&
        (hookSets.isEmpty || !identical(hookSets.last, finalHooks))) {
      hookSets.add(finalHooks);
    }
    return SearchlightHookRuntime.fromHooks(hookSets);
  }

  static void _validateExtensionCompatibility({
    required Object? raw,
    required ResolvedExtensions resolvedExtensions,
  }) {
    if (raw == null) {
      return;
    }

    final compatibility = _asObjectMap(
      raw,
      'Missing or invalid "extensionCompatibility" in JSON',
    );
    final plugins = compatibility['plugins'];
    if (plugins is! List || plugins.any((plugin) => plugin is! String)) {
      throw const SerializationException(
        'Missing or invalid "extensionCompatibility.plugins" in JSON',
      );
    }
    final actualPluginNames = plugins.cast<String>();
    final expectedPluginNames = [
      for (final plugin in resolvedExtensions.plugins) plugin.name,
    ];
    if (!_sameStringList(actualPluginNames, expectedPluginNames)) {
      throw SerializationException(
        'Incompatible plugin graph: expected ${expectedPluginNames.join(", ")} '
        'but restore was given ${actualPluginNames.join(", ")}.',
      );
    }

    final components = _asObjectMap(
      compatibility['components'],
      'Missing or invalid "extensionCompatibility.components" in JSON',
    );
    final actualIndexId = components['index'];
    final actualSorterId = components['sorter'];
    final actualDocumentsStoreId = components['documentsStore'];
    if (actualIndexId is! String ||
        actualSorterId is! String ||
        actualDocumentsStoreId is! String) {
      throw const SerializationException(
        'Missing or invalid "extensionCompatibility.components" in JSON',
      );
    }
    final expectedIndexId =
        resolvedExtensions.components.index?.id ??
            defaultSearchlightIndexComponent.id;
    final expectedSorterId =
        resolvedExtensions.components.sorter?.id ??
            defaultSearchlightSorterComponent.id;
    final expectedDocumentsStoreId =
        resolvedExtensions.components.documentsStore?.id ??
            defaultSearchlightDocumentsStoreComponent.id;
    if (actualIndexId != expectedIndexId ||
        actualSorterId != expectedSorterId ||
        actualDocumentsStoreId != expectedDocumentsStoreId) {
      throw SerializationException(
        'Incompatible component graph: expected index=$expectedIndexId, '
        'sorter=$expectedSorterId, documentsStore=$expectedDocumentsStoreId '
        'but restore was given index=$actualIndexId, '
        'sorter=$actualSorterId, documentsStore=$actualDocumentsStoreId.',
      );
    }
  }

  static bool _sameStringList(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) {
        return false;
      }
    }
    return true;
  }

  static const _singleHookAsyncError =
      'Async single-record lifecycle hooks are not supported in synchronous '
      'Searchlight operations.';
  static const _multipleHookAsyncError =
      'Async multi-record lifecycle hooks are not supported in synchronous '
      'Searchlight operations.';
  static const _createHookAsyncError =
      'Async create lifecycle hooks are not supported in synchronous '
      'Searchlight operations.';
  static const _searchHookAsyncError =
      'Async search lifecycle hooks are not supported in synchronous '
      'Searchlight operations.';

  void _ensureSyncAfterCreateHooks(List<SearchlightAfterCreateHook> hooks) {
    for (final hook in hooks) {
      if (hook is _SearchlightFutureAfterCreateHook<Object?> ||
          hook is _SearchlightFutureAfterCreateHook<void>) {
        throw UnsupportedError(_createHookAsyncError);
      }
    }
  }

  void _ensureSyncSingleHooks(List<SearchlightSingleHook> hooks) {
    for (final hook in hooks) {
      if (hook is _SearchlightFutureSingleHook<Object?> ||
          hook is _SearchlightFutureSingleHook<void>) {
        throw UnsupportedError(_singleHookAsyncError);
      }
    }
  }

  void _ensureSyncMultipleIdsHooks(List<SearchlightMultipleIdsHook> hooks) {
    for (final hook in hooks) {
      if (hook is _SearchlightFutureMultipleIdsHook<Object?> ||
          hook is _SearchlightFutureMultipleIdsHook<void>) {
        throw UnsupportedError(_multipleHookAsyncError);
      }
    }
  }

  void _ensureSyncMultipleDocsHooks(List<SearchlightMultipleDocsHook> hooks) {
    for (final hook in hooks) {
      if (hook is _SearchlightFutureMultipleDocsHook<Object?> ||
          hook is _SearchlightFutureMultipleDocsHook<void>) {
        throw UnsupportedError(_multipleHookAsyncError);
      }
    }
  }

  void _ensureSyncBeforeSearchHooks(List<SearchlightBeforeSearchHook> hooks) {
    for (final hook in hooks) {
      if (hook is _SearchlightFutureBeforeSearchHook<Object?> ||
          hook is _SearchlightFutureBeforeSearchHook<void>) {
        throw UnsupportedError(_searchHookAsyncError);
      }
    }
  }

  void _ensureSyncAfterSearchHooks(List<SearchlightAfterSearchHook> hooks) {
    for (final hook in hooks) {
      if (hook is _SearchlightFutureAfterSearchHook<Object?> ||
          hook is _SearchlightFutureAfterSearchHook<void>) {
        throw UnsupportedError(_searchHookAsyncError);
      }
    }
  }

  void _preflightInsertLifecycleHooks() {
    _ensureSyncSingleHooks(_hookRuntime.beforeInsert);
    _ensureSyncSingleHooks(_hookRuntime.afterInsert);
  }

  void _preflightRemoveLifecycleHooks() {
    _ensureSyncSingleHooks(_hookRuntime.beforeRemove);
    _ensureSyncSingleHooks(_hookRuntime.afterRemove);
  }

  void _preflightUpdateLifecycleHooks() {
    _ensureSyncSingleHooks(_hookRuntime.beforeUpdate);
    _ensureSyncSingleHooks(_hookRuntime.afterUpdate);
    _preflightRemoveLifecycleHooks();
    _preflightInsertLifecycleHooks();
  }

  void _preflightInsertMultipleLifecycleHooks() {
    _ensureSyncMultipleDocsHooks(_hookRuntime.afterInsertMultiple);
    _preflightInsertLifecycleHooks();
  }

  void _preflightRemoveMultipleLifecycleHooks() {
    _ensureSyncMultipleIdsHooks(_hookRuntime.beforeRemoveMultiple);
    _ensureSyncMultipleIdsHooks(_hookRuntime.afterRemoveMultiple);
    _preflightRemoveLifecycleHooks();
  }

  void _preflightUpdateMultipleLifecycleHooks() {
    _ensureSyncMultipleIdsHooks(_hookRuntime.beforeUpdateMultiple);
    _ensureSyncMultipleIdsHooks(_hookRuntime.afterUpdateMultiple);
    _preflightRemoveMultipleLifecycleHooks();
    _preflightInsertMultipleLifecycleHooks();
  }

  void _preflightSearchLifecycleHooks() {
    _ensureSyncBeforeSearchHooks(_hookRuntime.beforeSearch);
    _ensureSyncAfterSearchHooks(_hookRuntime.afterSearch);
  }

  void _preflightUpsertLifecycleHooks() {
    _ensureSyncSingleHooks(_hookRuntime.beforeUpsert);
    _ensureSyncSingleHooks(_hookRuntime.afterUpsert);
    _preflightUpdateLifecycleHooks();
  }

  void _preflightUpsertMultipleLifecycleHooks() {
    _ensureSyncMultipleDocsHooks(_hookRuntime.beforeUpsertMultiple);
    _ensureSyncMultipleIdsHooks(_hookRuntime.afterUpsertMultiple);
    _preflightUpdateMultipleLifecycleHooks();
  }

  void _runSingleLifecycleHooks(
    List<SearchlightSingleHook> hooks, {
    required String id,
    required SearchlightRecord? doc,
  }) {
    final syncHooks =
        hooks.cast<void Function(Object, String, SearchlightRecord?)>();
    for (final hook in syncHooks) {
      hook(this, id, doc);
    }
  }

  void _runMultipleIdsLifecycleHooks(
    List<SearchlightMultipleIdsHook> hooks, {
    required List<String> ids,
  }) {
    final syncHooks = hooks.cast<void Function(Object, List<String>)>();
    for (final hook in syncHooks) {
      hook(this, ids);
    }
  }

  void _runMultipleDocsLifecycleHooks(
    List<SearchlightMultipleDocsHook> hooks, {
    required List<SearchlightRecord> docs,
  }) {
    final syncHooks =
        hooks.cast<void Function(Object, List<SearchlightRecord>)>();
    for (final hook in syncHooks) {
      hook(this, docs);
    }
  }

  void _runAfterCreateHooks(List<SearchlightAfterCreateHook> hooks) {
    _ensureSyncAfterCreateHooks(hooks);
    final syncHooks = hooks.cast<void Function(Object)>();
    for (final hook in syncHooks) {
      hook(this);
    }
  }

  void _runBeforeSearchHooks({
    required SearchlightSearchParams params,
    required String language,
  }) {
    final syncHooks = _hookRuntime.beforeSearch
        .cast<void Function(Object, SearchlightSearchParams, String)>();
    for (final hook in syncHooks) {
      hook(this, params, language);
    }
  }

  void _runAfterSearchHooks({
    required SearchlightSearchParams params,
    required String language,
    required Object results,
  }) {
    final syncHooks = _hookRuntime.afterSearch
        .cast<void Function(Object, SearchlightSearchParams, String, Object)>();
    for (final hook in syncHooks) {
      hook(this, params, language, results);
    }
  }

  static void _restoreSerializedDocuments(
    Searchlight db, {
    required Map<String, Object?> docsJson,
    required Map<String, Object?> idStoreJson,
  }) {
    final internalToIdJson = _asObjectMap(
      idStoreJson['internalIdToId'],
      'Missing or invalid "internalDocumentIDStore.internalIdToId" in JSON',
    );
    final geoFields = db.schema.fieldPathsOfType(SchemaType.geopoint);
    final sortedEntries = docsJson.entries.toList()
      ..sort((a, b) => int.parse(a.key).compareTo(int.parse(b.key)));

    for (final entry in sortedEntries) {
      final internalId = int.parse(entry.key);
      final externalId = internalToIdJson[entry.key] as String?;
      if (externalId == null) {
        throw SerializationException(
          'Missing external ID mapping for internal document ${entry.key}',
        );
      }

      final data = _deserializeStoredDocument(
        entry.value,
        docKey: entry.key,
        geoFields: geoFields,
      );
      final docId = DocId(internalId);
      final document = Document(data);

      db._externalToInternal[externalId] = docId;
      db._internalToExternal[docId] = externalId;
      db._documentsStore.restore(
        internalId: docId,
        externalId: externalId,
        document: document,
      );
    }

    db._index.restoreDocsCount(db._documentsStore.count);
    _restoreCounters(db, idStoreJson);
  }

  static void _restoreLegacyDocuments(
    Searchlight db, {
    required Map<String, Object?> docsJson,
    required Map<String, Object?> idStoreJson,
  }) {
    final internalToIdJson = _asObjectMap(
      idStoreJson['internalIdToId'],
      'Missing or invalid "internalDocumentIDStore.internalIdToId" in JSON',
    );
    final geoFields = db.schema.fieldPathsOfType(SchemaType.geopoint);
    final sortedEntries = docsJson.entries.toList()
      ..sort((a, b) => int.parse(a.key).compareTo(int.parse(b.key)));

    for (final entry in sortedEntries) {
      final externalId = internalToIdJson[entry.key] as String?;
      if (externalId == null) {
        throw SerializationException(
          'Missing external ID mapping for internal document ${entry.key}',
        );
      }

      final dataWithId = _deserializeStoredDocument(
        entry.value,
        docKey: entry.key,
        geoFields: geoFields,
      )..['id'] = externalId;

      db.insert(dataWithId);
    }

    _restoreCounters(db, idStoreJson);
  }

  static Map<String, Object?> _deserializeStoredDocument(
    Object? rawDocument, {
    required String docKey,
    required List<String> geoFields,
  }) {
    final data = _asObjectMap(
      rawDocument,
      'Invalid document payload for internal document $docKey',
    );
    final document = Map<String, Object?>.from(data);
    for (final geoPath in geoFields) {
      _convertMapToGeoPoint(document, geoPath);
    }
    return document;
  }

  static void _restoreCounters(
    Searchlight db,
    Map<String, Object?> idStoreJson,
  ) {
    final nextId = idStoreJson['nextId'] as int?;
    final nextGeneratedId = idStoreJson['nextGeneratedId'] as int?;

    final maxExistingId = db._documentsStore.internalIds.fold<int>(
      0,
      (maxId, docId) => docId.id > maxId ? docId.id : maxId,
    );
    final minNextId = maxExistingId + 1;
    if (nextId != null) {
      db._nextInternalId = nextId < minNextId ? minNextId : nextId;
    } else {
      db._nextInternalId = minNextId;
    }
    if (nextGeneratedId != null) {
      db._nextGeneratedId = nextGeneratedId;
    }
  }

  static Map<String, Object?> _asObjectMap(Object? raw, String message) {
    if (raw is! Map) {
      throw SerializationException(message);
    }
    return Map<String, Object?>.from(raw);
  }

  static bool? _asOptionalBool(
    Map<String, Object?>? json, {
    required String key,
    required String message,
  }) {
    if (json == null || !json.containsKey(key) || json[key] == null) {
      return null;
    }
    final value = json[key];
    if (value is! bool) {
      throw SerializationException(message);
    }
    return value;
  }

  static List<String>? _asOptionalStringList(
    Map<String, Object?>? json, {
    required String key,
    required String message,
  }) {
    if (json == null || !json.containsKey(key) || json[key] == null) {
      return null;
    }
    final value = json[key];
    if (value is! List) {
      throw SerializationException(message);
    }
    if (value.any((element) => element is! String)) {
      throw SerializationException(message);
    }
    return value.cast<String>();
  }

  // ---------------------------------------------------------------------------
  // Internal document storage
  // ---------------------------------------------------------------------------

  final SearchlightDocumentsStore _documentsStore;

  /// External string ID -> internal DocId mapping.
  final Map<String, DocId> _externalToInternal = {};

  /// Internal DocId -> external string ID mapping.
  final Map<DocId, String> _internalToExternal = {};

  /// Auto-increment counter for internal IDs.
  int _nextInternalId = 1;

  /// Auto-increment counter for generating external IDs.
  int _nextGeneratedId = 0;

  /// Total number of indexed documents.
  int get count => _documentsStore.count;

  /// Whether the database has no documents.
  bool get isEmpty => count == 0;

  /// Internal documents keyed by raw integer ID — for facet/group computation.
  Map<int, Document> get documentsForFacets {
    return <int, Document>{
      for (final docId in _documentsStore.internalIds)
        if (_documentsStore.getByInternalId(docId) case final doc?)
          docId.id: doc,
    };
  }

  /// Field path -> SchemaType mapping — for facet/group type resolution.
  Map<String, SchemaType> get propertiesWithTypes =>
      _index.searchablePropertiesWithTypes;

  List<String> get _sortableProperties {
    return _index.searchablePropertiesWithTypes.entries
        .where((entry) => _sortableTypes.contains(entry.value))
        .map((entry) => entry.key)
        .toList();
  }

  /// Internal doc ID -> external string ID mapping — for group computation.
  Map<int, String> get externalIdsMap {
    return <int, String>{
      for (final docId in _documentsStore.internalIds)
        if (_documentsStore.getExternalId(docId) case final externalId?)
          docId.id: externalId,
    };
  }

  // ---------------------------------------------------------------------------
  // Insert
  // ---------------------------------------------------------------------------

  /// Inserts a document into the database.
  ///
  /// If `data['id']` is a [String], it is used as the external document ID.
  /// If not provided, a unique string ID is auto-generated.
  ///
  /// Validates schema-defined fields against the schema before storing.
  /// Extra document properties (like `id`) are silently ignored.
  ///
  /// Returns the external [String] ID for the new document.
  ///
  /// Throws [DocumentValidationException] if the document does not conform
  /// to the schema, or if a document with the same external ID already exists.
  String insert(Map<String, Object?> data) {
    _validateDocument(data, schema.fields, '');
    _preflightInsertLifecycleHooks();

    // Determine external ID (Fix 1)
    final externalId = _getDocumentIndexId(data);
    _runSingleLifecycleHooks(
      _hookRuntime.beforeInsert,
      id: externalId,
      doc: data,
    );

    // Check for duplicate (Fix 1)
    if (_externalToInternal.containsKey(externalId)) {
      throw DocumentValidationException(
        'Document already exists: $externalId',
        field: 'id',
      );
    }

    // Map external -> internal
    final internalId = DocId(_nextInternalId++);
    _externalToInternal[externalId] = internalId;
    _internalToExternal[internalId] = externalId;

    final document = Document(data);
    _documentsStore.store(
      internalId: internalId,
      externalId: externalId,
      document: document,
    );
    final extractedProperties = _getDocumentProperties(
      data,
      _index.searchableProperties,
    );

    // Index the document for search
    _index.insertDocument(
      docId: internalId.id,
      data: data,
      resolvedProperties: extractedProperties,
      tokenizer: _tokenizer,
      language: language,
    );

    // Populate sort index for sortable fields (string, number, boolean)
    _insertSortableValues(
      internalId.id,
      data,
      resolvedProperties: extractedProperties,
    );
    _runSingleLifecycleHooks(
      _hookRuntime.afterInsert,
      id: externalId,
      doc: data,
    );

    return externalId;
  }

  /// Gets the external document ID from the document data.
  ///
  /// If `doc['id']` is a [String], use it. Otherwise, auto-generate.
  /// Matches Orama's `getDocumentIndexId` behavior.
  String _getDocumentIndexId(Map<String, Object?> data) {
    if (_resolvedExtensions.components.getDocumentIndexId
        case final getDocumentIndexId?) {
      return getDocumentIndexId(data);
    }

    final id = data['id'];
    if (id != null) {
      if (id is! String) {
        throw DocumentValidationException(
          'Document ID must be a string, got ${id.runtimeType}',
          field: 'id',
        );
      }
      return id;
    }
    return _generateUniqueId();
  }

  /// Generates a unique string ID.
  String _generateUniqueId() {
    return '${_nextGeneratedId++}';
  }

  Map<String, Object?> _getDocumentProperties(
    Map<String, Object?> data,
    Iterable<String> paths,
  ) {
    final propertyList = List<String>.from(paths);
    if (_resolvedExtensions.components.getDocumentProperties
        case final getDocumentProperties?) {
      return getDocumentProperties(data, propertyList);
    }

    return {
      for (final path in propertyList)
        path: SearchIndex.resolveValue(data, path),
    };
  }

  // ---------------------------------------------------------------------------
  // Validation (Fix 2: iterate schema keys, not document keys)
  // ---------------------------------------------------------------------------

  void _validateDocument(
    Map<String, Object?> data,
    Map<String, SchemaField> schemaFields,
    String prefix,
  ) {
    final validateSchema = _resolvedExtensions.components.validateSchema;
    if (prefix.isEmpty && validateSchema != null) {
      final invalidPath = validateSchema(data, schema);
      if (invalidPath != null) {
        throw DocumentValidationException(
          "Field '$invalidPath' has invalid type",
          field: invalidPath,
        );
      }
      return;
    }

    for (final entry in schemaFields.entries) {
      final key = entry.key;
      final field = entry.value;
      final path = prefix.isEmpty ? key : '$prefix.$key';
      final value = data[key];

      if (value == null) continue;

      switch (field) {
        case TypedField(:final type):
          _validateFieldType(value, type, path);
        case NestedField(:final children):
          if (value is! Map<String, Object?>) {
            throw DocumentValidationException(
              "Field '$path' must be a Map<String, Object?>",
              field: path,
            );
          }
          _validateDocument(value, children, path);
      }
    }
  }

  void _validateFieldType(Object value, SchemaType type, String path) {
    final valid = switch (type) {
      SchemaType.string => value is String,
      SchemaType.number => value is num,
      SchemaType.boolean => value is bool,
      // Fix 3: enum accepts String or num
      SchemaType.enumType => value is String || value is num,
      SchemaType.geopoint => value is GeoPoint,
      SchemaType.stringArray =>
        value is List && value.every((e) => e is String),
      SchemaType.numberArray => value is List && value.every((e) => e is num),
      SchemaType.booleanArray => value is List && value.every((e) => e is bool),
      // Fix 3: enumArray accepts String or num elements
      SchemaType.enumArray =>
        value is List && value.every((e) => e is String || e is num),
    };

    if (!valid) {
      throw DocumentValidationException(
        "Field '$path' has invalid type: expected $type",
        field: path,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Sort index helpers
  // ---------------------------------------------------------------------------

  /// Sortable types: string, number, boolean (not arrays, enums, geopoints).
  static const Set<SchemaType> _sortableTypes = {
    SchemaType.string,
    SchemaType.number,
    SchemaType.boolean,
  };

  /// Inserts sortable field values into the sort index for a document.
  void _insertSortableValues(
    int docId,
    Map<String, Object?> data, {
    Map<String, Object?>? resolvedProperties,
  }) {
    for (final entry in _index.searchablePropertiesWithTypes.entries) {
      final prop = entry.key;
      final type = entry.value;
      if (!_sortableTypes.contains(type)) continue;

      final value =
          resolvedProperties != null
              ? resolvedProperties[prop]
              : SearchIndex.resolveValue(data, prop);
      if (value == null) continue;

      _sortIndex.insert(property: prop, docId: docId, value: value);
    }
  }

  /// Removes a document from the sort index for all sortable properties.
  void _removeSortableValues(int docId) {
    for (final entry in _index.searchablePropertiesWithTypes.entries) {
      final prop = entry.key;
      final type = entry.value;
      if (!_sortableTypes.contains(type)) continue;

      _sortIndex.remove(property: prop, docId: docId);
    }
  }

  // ---------------------------------------------------------------------------
  // Batch insert (Fix 4: abort on failure, return List<String>)
  // ---------------------------------------------------------------------------

  /// Inserts multiple documents into the database.
  ///
  /// Calls [insert] for each document. If any insert throws, the error
  /// propagates and the batch is aborted (matching Orama's behavior).
  ///
  /// Returns a [List<String>] of external IDs for all successfully inserted
  /// documents.
  ///
  /// The [batchSize] parameter is accepted for API compatibility but does not
  /// change behavior in v1. Default is 1000 (matching Orama).
  List<String> insertMultiple(
    List<Map<String, Object?>> documents, {
    int batchSize = 1000,
  }) {
    _preflightInsertMultipleLifecycleHooks();
    final ids = <String>[];

    for (final doc in documents) {
      final id = insert(doc);
      ids.add(id);
    }
    _runMultipleDocsLifecycleHooks(
      _hookRuntime.afterInsertMultiple,
      docs: documents,
    );

    return ids;
  }

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  /// Returns the document with the given external [id], or `null` if not found.
  Document? getById(String id) => _documentsStore.getByExternalId(id);

  // ---------------------------------------------------------------------------
  // Remove (Fix 5: return bool / int)
  // ---------------------------------------------------------------------------

  /// Removes the document with the given external [id].
  ///
  /// Returns `true` if the document was found and removed,
  /// `false` if the [id] was not found.
  bool remove(String id) {
    _preflightRemoveLifecycleHooks();
    final internalId = _externalToInternal[id];
    if (internalId == null) return false;

    final doc = _documentsStore.getByInternalId(internalId);
    final removedData = doc?.toMap();
    _runSingleLifecycleHooks(
      _hookRuntime.beforeRemove,
      id: id,
      doc: removedData,
    );
    if (doc != null) {
      final removedProperties = _getDocumentProperties(
        doc.toMap(),
        _index.searchableProperties,
      );

      // Un-index the document before removing
      _index.removeDocument(
        docId: internalId.id,
        data: doc.toMap(),
        resolvedProperties: removedProperties,
        tokenizer: _tokenizer,
        language: language,
      );

      // Remove from sort index
      _removeSortableValues(internalId.id);
    }

    _externalToInternal.remove(id);
    _internalToExternal.remove(internalId);
    _documentsStore.removeByExternalId(id);
    _runSingleLifecycleHooks(
      _hookRuntime.afterRemove,
      id: id,
      doc: removedData,
    );
    return true;
  }

  /// Removes all documents with the given external [ids].
  ///
  /// Returns the count of documents actually removed. Silently ignores IDs
  /// that are not found.
  int removeMultiple(List<String> ids) {
    _preflightRemoveMultipleLifecycleHooks();
    _runMultipleIdsLifecycleHooks(
      _hookRuntime.beforeRemoveMultiple,
      ids: ids,
    );
    var count = 0;
    for (final id in ids) {
      if (remove(id)) count++;
    }
    _runMultipleIdsLifecycleHooks(
      _hookRuntime.afterRemoveMultiple,
      ids: ids,
    );
    return count;
  }

  // ---------------------------------------------------------------------------
  // Update
  // ---------------------------------------------------------------------------

  /// Replaces a document by removing the old one and inserting the new one.
  ///
  /// Matching Orama's `updateSync`: removes the document with the given
  /// external [id], then inserts [newDoc] as a fresh document. The remove
  /// may silently fail if [id] doesn't exist — the insert always proceeds.
  ///
  /// Returns the new external [String] ID of the inserted document.
  ///
  /// Validation happens during the insert step, after the old document has
  /// already been removed. If [newDoc] is invalid, the update throws and the
  /// original document stays deleted. This matches Orama's remove-then-insert
  /// semantics.
  ///
  /// Throws [DocumentValidationException] if [newDoc] does not conform
  /// to the schema.
  String update(String id, Map<String, Object?> newDoc) {
    _preflightUpdateLifecycleHooks();
    _runSingleLifecycleHooks(_hookRuntime.beforeUpdate, id: id, doc: newDoc);
    remove(id);
    final newId = insert(newDoc);
    _runSingleLifecycleHooks(
      _hookRuntime.afterUpdate,
      id: newId,
      doc: newDoc,
    );
    return newId;
  }

  /// Replaces multiple documents by removing the old ones and inserting
  /// new ones.
  ///
  /// Matching Orama's `updateMultipleSync`:
  /// 1. Validates ALL [newDocs] against the schema first. If any fail,
  ///    throws immediately — no removes happen.
  /// 2. Calls [removeMultiple] with [ids].
  /// 3. Calls [insertMultiple] with [newDocs].
  /// 4. Returns the new external IDs.
  ///
  /// The validate-all-first pattern prevents partial state corruption.
  ///
  /// The [batchSize] parameter is accepted for API compatibility.
  List<String> updateMultiple(
    List<String> ids,
    List<Map<String, Object?>> newDocs, {
    int batchSize = 1000,
  }) {
    _preflightUpdateMultipleLifecycleHooks();
    // Step 1: Validate ALL docs against schema FIRST (before any removes)
    for (final doc in newDocs) {
      _validateDocument(doc, schema.fields, '');
    }
    _runMultipleIdsLifecycleHooks(
      _hookRuntime.beforeUpdateMultiple,
      ids: ids,
    );

    // Step 2: Remove all old documents
    removeMultiple(ids);

    // Step 3: Insert all new documents
    final updatedIds = insertMultiple(newDocs, batchSize: batchSize);
    _runMultipleIdsLifecycleHooks(
      _hookRuntime.afterUpdateMultiple,
      ids: updatedIds,
    );
    return updatedIds;
  }

  /// Inserts a document when absent, or updates it when the ID already exists.
  ///
  /// Matches Orama's `upsert`: resolve the document ID first, run upsert
  /// hooks, then branch to `update` or `insert`.
  String upsert(Map<String, Object?> data) {
    _preflightUpsertLifecycleHooks();
    final id = _getDocumentIndexId(data);
    _runSingleLifecycleHooks(_hookRuntime.beforeUpsert, id: id, doc: data);

    final resultId = _externalToInternal.containsKey(id)
        ? update(id, data)
        : insert(data);

    _runSingleLifecycleHooks(
      _hookRuntime.afterUpsert,
      id: resultId,
      doc: data,
    );
    return resultId;
  }

  /// Bulk upsert matching Orama's update-first, insert-second flow.
  ///
  /// Runs `beforeUpsertMultiple`, validates all documents, partitions them into
  /// update and insert groups, then performs `updateMultiple` followed by
  /// `insertMultiple`. `afterUpsertMultiple` receives the result IDs in that
  /// same order.
  List<String> upsertMultiple(
    List<Map<String, Object?>> documents, {
    int batchSize = 1000,
  }) {
    _preflightUpsertMultipleLifecycleHooks();
    _runMultipleDocsLifecycleHooks(
      _hookRuntime.beforeUpsertMultiple,
      docs: documents,
    );

    for (final doc in documents) {
      _validateDocument(doc, schema.fields, '');
    }

    final docsToInsert = <Map<String, Object?>>[];
    final docsToUpdate = <Map<String, Object?>>[];
    final idsToUpdate = <String>[];

    for (final doc in documents) {
      final id = _getDocumentIndexId(doc);
      if (_externalToInternal.containsKey(id)) {
        docsToUpdate.add(doc);
        idsToUpdate.add(id);
      } else {
        docsToInsert.add(doc);
      }
    }

    final resultIds = <String>[];
    if (docsToUpdate.isNotEmpty) {
      resultIds.addAll(
        updateMultiple(
          idsToUpdate,
          docsToUpdate,
          batchSize: batchSize,
        ),
      );
    }
    if (docsToInsert.isNotEmpty) {
      resultIds.addAll(
        insertMultiple(
          docsToInsert,
          batchSize: batchSize,
        ),
      );
    }

    _runMultipleIdsLifecycleHooks(
      _hookRuntime.afterUpsertMultiple,
      ids: resultIds,
    );
    return resultIds;
  }

  // ---------------------------------------------------------------------------
  // Patch (Searchlight addition)
  // ---------------------------------------------------------------------------

  /// Patches (partially updates) a document by merging [fields] into the
  /// existing document.
  ///
  /// **Note:** This is a Searchlight-specific addition. Orama does not have
  /// a patch/merge operation — only full replacement via [update].
  ///
  /// Behavior:
  /// 1. Looks up the existing document by external [id].
  /// 2. Performs a shallow merge of [fields] into the existing data.
  /// 3. Validates the merged result against the schema.
  /// 4. Removes the old document and inserts the merged document.
  ///
  /// Returns the external [String] ID.
  ///
  /// Throws [DocumentNotFoundException] if [id] does not exist.
  /// Throws [DocumentValidationException] if the merged document does not
  /// conform to the schema.
  String patch(String id, Map<String, Object?> fields) {
    final existing = getById(id);
    if (existing == null) {
      throw DocumentNotFoundException(id);
    }

    // Shallow merge: existing data + new fields (new fields overwrite)
    final merged = <String, Object?>{
      ...existing.toMap(),
      ...fields,
      'id': id,
    };

    // Validate merged result BEFORE modifying state
    _validateDocument(merged, schema.fields, '');

    // Remove old, insert merged
    remove(id);
    return insert(merged);
  }

  // ---------------------------------------------------------------------------
  // Search (matching Orama's fullTextSearch flow)
  // ---------------------------------------------------------------------------

  /// Searches the database for documents matching [term] and/or [where]
  /// filters.
  ///
  /// Matches Orama's `fullTextSearch` from `search-fulltext.ts` and
  /// `innerFullTextSearch` filter integration.
  ///
  /// Parameters:
  /// - [term]: The search query string. Empty returns all documents.
  /// - [where]: Property-level filters applied before or instead of text
  ///   search. Multiple properties are ANDed. Pass `null` for no filtering.
  /// - [properties]: Which string fields to search
  ///   (default: all string fields).
  /// - [exact]: If true, only exact word matches are returned.
  /// - [tolerance]: Levenshtein distance for fuzzy matching.
  /// - [boost]: Per-property score multipliers.
  /// - [threshold]: 1.0 = any term (OR), 0.0 = all terms (AND).
  /// - [limit]: Maximum number of hits to return per page.
  /// - [offset]: Number of results to skip (pagination).
  ///
  /// Throws [QueryException] if a requested property is not a string field
  /// or if a filter references an unknown field.
  SearchResult search({
    String term = '',
    Map<String, Filter>? where,
    List<String>? properties,
    bool exact = false,
    int tolerance = 0,
    Map<String, double>? boost,
    double threshold = 1.0,
    int limit = 10,
    int offset = 0,
    Map<String, FacetConfig>? facets,
    GroupBy? groupBy,
    SortBy? sortBy,
  }) {
    final stopwatch = Stopwatch()..start();
    final searchParams = <String, Object?>{
      'term': term,
      if (where != null) 'where': where,
      if (properties != null) 'properties': properties,
      'exact': exact,
      'tolerance': tolerance,
      if (boost != null) 'boost': boost,
      'threshold': threshold,
      'limit': limit,
      'offset': offset,
      if (facets != null) 'facets': facets,
      if (groupBy != null) 'groupBy': groupBy,
      if (sortBy != null) 'sortBy': sortBy,
    };
    _preflightSearchLifecycleHooks();
    _runBeforeSearchHooks(
      params: searchParams,
      language: language,
    );

    // 1. Resolve properties: default = all string fields in the schema
    final stringFields = schema.fieldPathsOfType(SchemaType.string);
    List<String> propertiesToSearch;

    if (properties != null) {
      // Validate that requested properties are string type
      for (final prop in properties) {
        if (!stringFields.contains(prop)) {
          throw QueryException(
            "Property '$prop' is not a searchable string field. "
            'Available: ${stringFields.join(', ')}',
          );
        }
      }
      propertiesToSearch = properties;
    } else {
      propertiesToSearch = stringFields;
    }

    if (sortBy != null) {
      final sortableProperties = _sortableProperties;
      if (!sortableProperties.contains(sortBy.field)) {
        throw QueryException(
          "Unable to sort on unknown field '${sortBy.field}'. "
          'Available: ${sortableProperties.join(', ')}',
        );
      }
    }

    // 2. Evaluate where filters (matching Orama's innerFullTextSearch)
    final hasFilters = where != null && where.isNotEmpty;
    Set<int>? whereFiltersIDs;
    if (hasFilters) {
      whereFiltersIDs = searchByWhereClause(
        _index,
        where,
        existingDocIds: _documentsStore.internalIds
            .map((docId) => docId.id)
            .toSet(),
        tokenizer: _tokenizer,
        language: language,
      );
    }

    // 3. Search or return all/filtered docs
    // Item 6: Orama checks `if (term || properties)` — when properties
    // is specified (even without a term), the search path is taken.
    List<TokenScore> uniqueDocsArray;

    if (term.isNotEmpty || properties != null) {
      // Call SearchIndex.search matching Orama's innerFullTextSearch
      uniqueDocsArray = _index.search(
        term: term,
        tokenizer: _tokenizer,
        propertiesToSearch: propertiesToSearch,
        relevance: const BM25Params(),
        exact: exact,
        tolerance: tolerance,
        boost: boost ?? const {},
        threshold: threshold,
        language: language,
        whereFiltersIDs: whereFiltersIDs,
      );
      // Item 19: Exact-term post-filtering. Orama checks
      // `if (params.exact && term)` after scoring, filtering to docs where
      // the original text contains the exact search terms as whole words.
      if (exact && term.isNotEmpty) {
        final searchTerms = term.trim().split(RegExp(r'\s+'));
        uniqueDocsArray = uniqueDocsArray.where((tokenScore) {
          final internalId = DocId(tokenScore.$1);
          final doc = _documentsStore.getByInternalId(internalId);
          if (doc == null) return false;

          for (final prop in propertiesToSearch) {
            final propValue = SearchIndex.resolveValue(doc.toMap(), prop);
            if (propValue is String) {
              final hasAllTerms = searchTerms.every((searchTerm) {
                final regex = RegExp(
                  '\\b${RegExp.escape(searchTerm)}\\b',
                );
                return regex.hasMatch(propValue);
              });
              if (hasAllTerms) return true;
            }
          }
          return false;
        }).toList();
      }
    } else {
      // No term and no properties — matching Orama: if filters, check for
      // geo-only query first, else return filtered IDs with score 0.
      if (hasFilters) {
        // Item 18: Check if this is a geo-only query for distance scoring
        final geoResults = _searchByGeoWhereClause(where);
        if (geoResults != null) {
          uniqueDocsArray = geoResults;
        } else {
          final docIds = whereFiltersIDs ?? <int>{};
          uniqueDocsArray = docIds.map<TokenScore>((id) => (id, 0.0)).toList();
        }
      } else {
        uniqueDocsArray = _documentsStore.internalIds
            .map<TokenScore>((docId) => (docId.id, 0.0))
            .toList();
      }
    }

    // 4. Sort: by field (sortBy) or by score descending
    if (sortBy != null) {
      // Sort by field value using the sort index (overrides score order)
      uniqueDocsArray = _sortIndex.sortBy(
        results: uniqueDocsArray,
        property: sortBy.field,
        order: sortBy.order,
      );
    } else if (term.isEmpty) {
      // For no-term case, sort by score descending for consistency
      uniqueDocsArray.sort((a, b) => b.$2.compareTo(a.$2));
    }

    // 5. Total count before pagination
    final totalCount = uniqueDocsArray.length;

    // 6. Paginate
    final end = (offset + limit).clamp(0, uniqueDocsArray.length);
    final start = offset.clamp(0, uniqueDocsArray.length);
    final page = uniqueDocsArray.sublist(start, end);

    // 7. Fetch documents for the result page
    final hits = <SearchHit>[];
    for (final (docId, score) in page) {
      final internalId = DocId(docId);
      final externalId = _documentsStore.getExternalId(internalId);
      if (externalId == null) continue;
      final doc = _documentsStore.getByInternalId(internalId);
      if (doc == null) continue;

      hits.add(SearchHit(id: externalId, score: score, document: doc));
    }

    // 8. Compute facets on the FULL result set (before pagination)
    Map<String, FacetResult>? facetResults;
    final shouldCalculateFacets = facets != null && facets.isNotEmpty;
    if (shouldCalculateFacets) {
      facetResults = facets_lib.getFacets(
        documents: documentsForFacets,
        results: uniqueDocsArray,
        facetsConfig: facets,
        propertiesWithTypes: propertiesWithTypes,
      );
    }

    // 9. Compute groups on the FULL result set (before pagination)
    List<GroupResult>? groupResults;
    if (groupBy != null) {
      groupResults = grouping_lib.getGroups(
        documents: documentsForFacets,
        externalIds: externalIdsMap,
        results: uniqueDocsArray,
        groupBy: groupBy,
        schemaProperties: propertiesWithTypes,
      );
    }

    stopwatch.stop();

    final result = SearchResult(
      hits: hits,
      count: totalCount,
      elapsed: stopwatch.elapsed,
      facets: facetResults,
      groups: groupResults,
    );
    _runAfterSearchHooks(
      params: searchParams,
      language: language,
      results: result,
    );
    return result;
  }

  // ---------------------------------------------------------------------------
  // Item 18: Geo-only distance scoring
  // Matches Orama's searchByGeoWhereClause + isGeosearchOnlyQuery
  // ---------------------------------------------------------------------------

  /// Checks if the where clause is a geo-only query (single BKD filter)
  /// and returns distance-scored results if so.
  List<TokenScore>? _searchByGeoWhereClause(Map<String, Filter> filters) {
    if (filters.length != 1) return null;

    final param = filters.keys.first;
    final operation = filters.values.first;

    final indexTree = _index.indexes[param];
    if (indexTree == null || indexTree.type != TreeType.bkd) return null;

    if (operation is! GeoRadiusFilter && operation is! GeoPolygonFilter) {
      return null;
    }

    final bkdNode = indexTree.node as BKDTree;

    if (operation is GeoRadiusFilter) {
      final center = GeoPoint(lat: operation.lat, lon: operation.lon);
      final distanceInMeters =
          BKDTree.convertDistanceToMeters(operation.radius, operation.unit);
      final results = bkdNode.searchByRadius(
        center,
        distanceInMeters,
        inclusive: operation.inside,
        highPrecision: operation.highPrecision,
      );
      return _createGeoTokenScores(results, center, operation.highPrecision);
    }

    if (operation is GeoPolygonFilter) {
      final polygon = operation.coordinates
          .map((c) => GeoPoint(lat: c.lat, lon: c.lon))
          .toList();
      final results = bkdNode.searchByPolygon(
        polygon,
        inclusive: operation.inside,
        sort: SortOrder.asc,
        highPrecision: operation.highPrecision,
      );
      final centroid = BKDTree.calculatePolygonCentroid(polygon);
      return _createGeoTokenScores(results, centroid, operation.highPrecision);
    }

    return null;
  }

  /// Creates scored results from geo results using inverse distance scoring.
  ///
  /// Matches Orama's `createGeoTokenScores`.
  static List<TokenScore> _createGeoTokenScores(
    List<GeoSearchResult> results,
    GeoPoint centerPoint,
    bool highPrecision,
  ) {
    final distanceFn =
        highPrecision ? BKDTree.vincentyDistance : BKDTree.haversineDistance;

    final distances = <double>[];
    for (final r in results) {
      distances.add(distanceFn(centerPoint, r.point));
    }
    final maxDistance = distances.isEmpty ? 0.0 : distances.reduce(math.max);

    final scored = <TokenScore>[];
    for (var i = 0; i < results.length; i++) {
      final distance = distances[i];
      // Inverse score: closer points get higher scores
      final score = maxDistance - distance + 1;
      for (final docID in results[i].docIDs) {
        scored.add((docID, score));
      }
    }

    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored;
  }

  // ---------------------------------------------------------------------------
  // Reindex
  // ---------------------------------------------------------------------------

  /// Creates a new [Searchlight] instance with a different [algorithm],
  /// re-inserting all current documents into the new index.
  ///
  /// This matches Orama's plugin architecture: QPS and PT15 are plugins that
  /// REPLACE the index component. Reindexing creates a fresh instance with
  /// the new algorithm and copies all documents over.
  ///
  /// Returns the new [Searchlight] instance. The original instance is
  /// unmodified.
  Searchlight reindex({required SearchAlgorithm algorithm}) {
    if (_hasInjectedTokenizer) {
      throw StateError(
        'Cannot reindex a database created with a custom tokenizer.',
      );
    }
    if (_hasCustomStemmer) {
      throw StateError(
        'Cannot reindex a database created with a custom stemmer.',
      );
    }

    final newDb = Searchlight.create(
      schema: schema,
      algorithm: algorithm,
      language: language,
      stemming: _tokenizer.stemmingEnabled,
      stopWords: _serializedStopWords,
      useDefaultStopWords: _tokenizer.usesDefaultStopWords,
      allowDuplicates: _tokenizer.allowDuplicates,
      tokenizeSkipProperties: _tokenizer.tokenizeSkipProperties,
      stemmerSkipProperties: _tokenizer.stemmerSkipProperties,
      plugins: _resolvedExtensions.plugins,
      components: _resolvedExtensions.components,
    );

    // Re-insert all documents from the current instance
    for (final internalId in _documentsStore.internalIds) {
      final externalId = _documentsStore.getExternalId(internalId);
      final doc = _documentsStore.getByInternalId(internalId);
      if (externalId == null || doc == null) continue;

      // Preserve the original external ID by including it in the data
      final data = <String, Object?>{
        ...doc.toMap(),
        'id': externalId,
      };
      newDb.insert(data);
    }

    return newDb;
  }

  /// Removes all documents from the database.
  void clear() {
    // Remove each document through the normal remove path to ensure
    // the search index and sort index are properly updated.
    final ids = <String>[
      for (final internalId in _documentsStore.internalIds)
        if (_documentsStore.getExternalId(internalId) case final externalId?)
          externalId,
    ];
    ids.forEach(remove);
  }

  // ---------------------------------------------------------------------------
  // Serialization (matching Orama's save/load pattern)
  // ---------------------------------------------------------------------------

  /// Serializes the entire database state to a JSON-compatible map.
  ///
  /// Matches Orama's `save(orama)` which returns a `RawData` object
  /// containing all component states. Adds `formatVersion` for forward
  /// compatibility.
  Map<String, Object?> toJson() {
    if (_hasInjectedTokenizer) {
      throw const SerializationException(
        'Cannot serialize a database created with a custom tokenizer.',
      );
    }
    if (_hasCustomStemmer) {
      throw const SerializationException(
        'Cannot serialize a database created with a custom stemmer.',
      );
    }

    // Collect geopoint field paths from the schema so we can convert
    // GeoPoint objects to serializable maps (I4 fix).
    final geoFields = schema.fieldPathsOfType(SchemaType.geopoint);

    // Serialize documents from the active documents store.
    final docsJson = Map<String, Object?>.from(_documentsStore.save());
    for (final entry in docsJson.entries.toList()) {
      final docMap = Map<String, Object?>.from(entry.value! as Map);
      // Convert GeoPoint objects to JSON-serializable maps
      for (final geoPath in geoFields) {
        _convertGeoPointToMap(docMap, geoPath);
      }
      docsJson[entry.key] = docMap;
    }

    // Serialize ID store (matching Orama's internalDocumentIDStore.save)
    final idToInternalJson = <String, int>{};
    final internalToIdJson = <String, String>{};
    for (final internalId in _documentsStore.internalIds) {
      final externalId = _documentsStore.getExternalId(internalId);
      if (externalId == null) {
        continue;
      }
      idToInternalJson[externalId] = internalId.id;
      internalToIdJson[internalId.id.toString()] = externalId;
    }

    return {
      'formatVersion': currentFormatVersion,
      'algorithm': algorithm.name,
      'language': language,
      'extensionCompatibility': {
        'plugins': [
          for (final plugin in _resolvedExtensions.plugins) plugin.name,
        ],
        'components': {
          'index':
              _resolvedExtensions.components.index?.id ??
                  defaultSearchlightIndexComponent.id,
          'sorter':
              _resolvedExtensions.components.sorter?.id ??
                  defaultSearchlightSorterComponent.id,
          'documentsStore':
              _resolvedExtensions.components.documentsStore?.id ??
                  defaultSearchlightDocumentsStoreComponent.id,
        },
      },
      'tokenizerConfig': {
        'stemming': _tokenizer.stemmingEnabled,
        'stopWords': _serializedStopWords,
        'useDefaultStopWords': _tokenizer.usesDefaultStopWords,
        'allowDuplicates': _tokenizer.allowDuplicates,
        'tokenizeSkipProperties': (_tokenizer.tokenizeSkipProperties.toList()
          ..sort()),
        'stemmerSkipProperties': (_tokenizer.stemmerSkipProperties.toList()
          ..sort()),
      },
      'schema': schemaToJson(schema),
      'internalDocumentIDStore': {
        'idToInternalId': idToInternalJson,
        'internalIdToId': internalToIdJson,
        'nextId': _nextInternalId,
        'nextGeneratedId': _nextGeneratedId,
      },
      'index': _index.toJson(),
      'sorting': _sortIndex.toJson(),
      'documents': docsJson,
    };
  }

  // ---------------------------------------------------------------------------
  // GeoPoint serialization helpers (I4 fix)
  // ---------------------------------------------------------------------------

  /// Converts a [GeoPoint] at [path] in [data] to a `{'lat': ..., 'lon': ...}`
  /// map for JSON/CBOR serialization.
  static void _convertGeoPointToMap(Map<String, Object?> data, String path) {
    final segments = path.split('.');
    var current = data;
    for (var i = 0; i < segments.length - 1; i++) {
      final value = current[segments[i]];
      if (value is! Map<String, Object?>) return;
      // Make a mutable copy of nested maps
      final mutable = Map<String, Object?>.from(value);
      current[segments[i]] = mutable;
      current = mutable;
    }
    final leafKey = segments.last;
    final value = current[leafKey];
    if (value is GeoPoint) {
      current[leafKey] = <String, Object?>{'lat': value.lat, 'lon': value.lon};
    }
  }

  /// Converts a `{'lat': ..., 'lon': ...}` map at [path] in [data] back to a
  /// [GeoPoint] object during deserialization.
  static void _convertMapToGeoPoint(Map<String, Object?> data, String path) {
    final segments = path.split('.');
    var current = data;
    for (var i = 0; i < segments.length - 1; i++) {
      final value = current[segments[i]];
      if (value is! Map<String, Object?>) return;
      current = value;
    }
    final leafKey = segments.last;
    final value = current[leafKey];
    if (value is Map<String, Object?> &&
        value.containsKey('lat') &&
        value.containsKey('lon')) {
      final lat = value['lat'];
      final lon = value['lon'];
      if (lat is num && lon is num) {
        current[leafKey] = GeoPoint(
          lat: lat.toDouble(),
          lon: lon.toDouble(),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // CBOR binary serialization
  // ---------------------------------------------------------------------------

  /// Serializes the entire database state to CBOR binary format.
  ///
  /// Calls [toJson] to get the JSON-compatible map, then encodes it with
  /// CBOR. This is Searchlight's binary format, analogous to Orama's
  /// msgpack encoding.
  Uint8List serialize() {
    return cborEncode(toJson());
  }

  /// Deserializes a [Searchlight] instance from CBOR bytes produced by
  /// [serialize].
  ///
  /// Decodes the CBOR bytes to a JSON-compatible map, then delegates to
  /// [Searchlight.fromJson].
  ///
  /// Throws [SerializationException] if the bytes are not valid CBOR or
  /// the decoded data is incompatible.
  static Searchlight deserialize(
    Uint8List bytes, {
    List<SearchlightPlugin<Object?>> plugins = const [],
    SearchlightComponents? components,
  }) {
    try {
      final map = cborDecode(bytes);
      return Searchlight.fromJson(
        map,
        plugins: plugins,
        components: components,
      );
    } on FormatException catch (e) {
      throw SerializationException('Invalid CBOR data: ${e.message}');
    }
  }

  // ---------------------------------------------------------------------------
  // Persist / Restore (convenience wrappers around serialize + storage)
  // ---------------------------------------------------------------------------

  /// Persists the database to the given [storage].
  ///
  /// The [format] parameter selects the encoding: [PersistenceFormat.cbor]
  /// (default, compact binary) or [PersistenceFormat.json] (human-readable).
  /// Both formats use the same logical structure produced by [toJson].
  Future<void> persist({
    required SearchlightStorage storage,
    PersistenceFormat format = PersistenceFormat.cbor,
  }) async {
    final Uint8List bytes;
    switch (format) {
      case PersistenceFormat.cbor:
        bytes = serialize();
      case PersistenceFormat.json:
        final jsonString = jsonEncode(toJson());
        bytes = Uint8List.fromList(utf8.encode(jsonString));
    }
    await storage.save(bytes);
  }

  /// Restores a [Searchlight] instance from the given [storage].
  ///
  /// The [format] must match the format used when [persist] was called.
  /// Throws [StorageException] if no data is found.
  static Future<Searchlight> restore({
    required SearchlightStorage storage,
    PersistenceFormat format = PersistenceFormat.cbor,
    List<SearchlightPlugin<Object?>> plugins = const [],
    SearchlightComponents? components,
  }) async {
    final bytes = await storage.load();
    if (bytes == null) {
      throw const StorageException('No data found');
    }
    switch (format) {
      case PersistenceFormat.cbor:
        return deserialize(
          bytes,
          plugins: plugins,
          components: components,
        );
      case PersistenceFormat.json:
        final jsonString = utf8.decode(bytes);
        final map = jsonDecode(jsonString) as Map<String, Object?>;
        return Searchlight.fromJson(
          map,
          plugins: plugins,
          components: components,
        );
    }
  }

  /// Releases resources. Flushes pending writes if applicable.
  Future<void> dispose() async {
    // Will be expanded when persistence/isolates are added
  }
}
