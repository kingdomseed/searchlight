import 'package:searchlight/src/core/exceptions.dart';
import 'package:searchlight/src/core/schema.dart';
import 'package:searchlight/src/extensions/components.dart';
import 'package:searchlight/src/extensions/plugin.dart';

/// Resolved extension inputs for a `Searchlight.create()` call.
final class ResolvedExtensions {
  /// Creates a resolved extension bundle.
  const ResolvedExtensions({
    required this.plugins,
    required this.components,
  });

  /// Plugins preserved in deterministic registration order.
  final List<SearchlightPlugin<Object?>> plugins;

  /// Final resolved component graph after defaults, plugins, and overrides.
  final SearchlightComponents components;
}

/// Resolves plugin and component inputs into a deterministic final shape.
ResolvedExtensions resolveExtensions({
  required Schema schema,
  required SearchlightComponents defaults,
  List<SearchlightPlugin<Object?>> plugins = const [],
  SearchlightComponents? overrides,
}) {
  final seenNames = <String>{};
  for (final plugin in plugins) {
    if (!seenNames.add(plugin.name)) {
      throw ExtensionResolutionException(
        'Duplicate plugin name: "${plugin.name}"',
      );
    }
  }

  var resolvedTokenizer = overrides?.tokenizer ?? defaults.tokenizer;
  var resolvedIndex = overrides?.index ?? defaults.index;
  var resolvedSorter = overrides?.sorter ?? defaults.sorter;
  var resolvedDocumentsStore =
      overrides?.documentsStore ?? defaults.documentsStore;
  var resolvedPinning = overrides?.pinning ?? defaults.pinning;
  var resolvedValidateSchema =
      overrides?.validateSchema ?? defaults.validateSchema;
  var resolvedGetDocumentIndexId =
      overrides?.getDocumentIndexId ?? defaults.getDocumentIndexId;
  var resolvedGetDocumentProperties =
      overrides?.getDocumentProperties ?? defaults.getDocumentProperties;
  var resolvedFormatElapsedTime =
      overrides?.formatElapsedTime ?? defaults.formatElapsedTime;
  String? tokenizerOwner;
  String? indexOwner;
  String? sorterOwner;
  String? documentsStoreOwner;
  String? pinningOwner;
  String? validateSchemaOwner;
  String? documentIndexIdOwner;
  String? documentPropertiesOwner;
  String? formatElapsedTimeOwner;

  if (overrides?.tokenizer != null) {
    tokenizerOwner = 'user components';
  }
  if (overrides?.index != null) {
    indexOwner = 'user components';
  }
  if (overrides?.sorter != null) {
    sorterOwner = 'user components';
  }
  if (overrides?.documentsStore != null) {
    documentsStoreOwner = 'user components';
  }
  if (overrides?.pinning != null) {
    pinningOwner = 'user components';
  }
  if (overrides?.validateSchema != null) {
    validateSchemaOwner = 'user components';
  }
  if (overrides?.getDocumentIndexId != null) {
    documentIndexIdOwner = 'user components';
  }
  if (overrides?.getDocumentProperties != null) {
    documentPropertiesOwner = 'user components';
  }
  if (overrides?.formatElapsedTime != null) {
    formatElapsedTimeOwner = 'user components';
  }

  for (final plugin in plugins) {
    final pluginComponents = plugin.getComponents?.call(schema);
    if (pluginComponents?.tokenizer case final tokenizer?) {
      if (tokenizerOwner != null) {
        throw ExtensionResolutionException(
          'Component conflict for "tokenizer": already provided by '
          '$tokenizerOwner; plugin "${plugin.name}" cannot register the '
          'same component slot.',
        );
      }
      resolvedTokenizer = tokenizer;
      tokenizerOwner = 'plugin "${plugin.name}"';
    }
    if (pluginComponents?.index case final index?) {
      if (indexOwner != null) {
        throw ExtensionResolutionException(
          'Component conflict for "index": already provided by $indexOwner; '
          'plugin "${plugin.name}" cannot register the same component slot.',
        );
      }
      resolvedIndex = index;
      indexOwner = 'plugin "${plugin.name}"';
    }
    if (pluginComponents?.sorter case final sorter?) {
      if (sorterOwner != null) {
        throw ExtensionResolutionException(
          'Component conflict for "sorter": already provided by $sorterOwner; '
          'plugin "${plugin.name}" cannot register the same component slot.',
        );
      }
      resolvedSorter = sorter;
      sorterOwner = 'plugin "${plugin.name}"';
    }
    if (pluginComponents?.documentsStore case final documentsStore?) {
      if (documentsStoreOwner != null) {
        throw ExtensionResolutionException(
          'Component conflict for "documentsStore": already provided by '
          '$documentsStoreOwner; plugin "${plugin.name}" cannot register '
          'the same component slot.',
        );
      }
      resolvedDocumentsStore = documentsStore;
      documentsStoreOwner = 'plugin "${plugin.name}"';
    }
    if (pluginComponents?.pinning case final pinning?) {
      if (pinningOwner != null) {
        throw ExtensionResolutionException(
          'Component conflict for "pinning": already provided by '
          '$pinningOwner; plugin "${plugin.name}" cannot register '
          'the same component slot.',
        );
      }
      resolvedPinning = pinning;
      pinningOwner = 'plugin "${plugin.name}"';
    }
    if (pluginComponents?.validateSchema case final validateSchema?) {
      if (validateSchemaOwner != null) {
        throw ExtensionResolutionException(
          'Component conflict for "validateSchema": already provided by '
          '$validateSchemaOwner; plugin "${plugin.name}" cannot register '
          'the same component slot.',
        );
      }
      resolvedValidateSchema = validateSchema;
      validateSchemaOwner = 'plugin "${plugin.name}"';
    }
    if (pluginComponents?.getDocumentIndexId case final getDocumentIndexId?) {
      if (documentIndexIdOwner != null) {
        throw ExtensionResolutionException(
          'Component conflict for "getDocumentIndexId": already provided by '
          '$documentIndexIdOwner; plugin "${plugin.name}" cannot register '
          'the same component slot.',
        );
      }
      resolvedGetDocumentIndexId = getDocumentIndexId;
      documentIndexIdOwner = 'plugin "${plugin.name}"';
    }
    if (pluginComponents?.getDocumentProperties
        case final getDocumentProperties?) {
      if (documentPropertiesOwner != null) {
        throw ExtensionResolutionException(
          'Component conflict for "getDocumentProperties": already '
          'provided by $documentPropertiesOwner; plugin "${plugin.name}" '
          'cannot register the same component slot.',
        );
      }
      resolvedGetDocumentProperties = getDocumentProperties;
      documentPropertiesOwner = 'plugin "${plugin.name}"';
    }
    if (pluginComponents?.formatElapsedTime case final formatElapsedTime?) {
      if (formatElapsedTimeOwner != null) {
        throw ExtensionResolutionException(
          'Component conflict for "formatElapsedTime": already '
          'provided by $formatElapsedTimeOwner; plugin "${plugin.name}" '
          'cannot register the same component slot.',
        );
      }
      resolvedFormatElapsedTime = formatElapsedTime;
      formatElapsedTimeOwner = 'plugin "${plugin.name}"';
    }
  }

  return ResolvedExtensions(
    plugins: List.unmodifiable(plugins),
    components: SearchlightComponents(
      tokenizer: resolvedTokenizer,
      index: resolvedIndex,
      sorter: resolvedSorter,
      documentsStore: resolvedDocumentsStore,
      pinning: resolvedPinning,
      validateSchema: resolvedValidateSchema,
      getDocumentIndexId: resolvedGetDocumentIndexId,
      getDocumentProperties: resolvedGetDocumentProperties,
      formatElapsedTime: resolvedFormatElapsedTime,
    ),
  );
}
