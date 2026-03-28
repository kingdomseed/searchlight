import 'package:searchlight/src/core/exceptions.dart';
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

  var resolvedHooks = defaults.hooks;
  var resolvedIndex = overrides?.index ?? defaults.index;
  var resolvedSorter = overrides?.sorter ?? defaults.sorter;
  String? indexOwner;
  String? sorterOwner;

  if (overrides?.index != null) {
    indexOwner = 'user components';
  }
  if (overrides?.sorter != null) {
    sorterOwner = 'user components';
  }

  for (final plugin in plugins) {
    if (plugin.components?.index case final index?) {
      if (indexOwner != null) {
        throw ExtensionResolutionException(
          'Component conflict for "index": already provided by $indexOwner; '
          'plugin "${plugin.name}" cannot register the same component slot.',
        );
      }
      resolvedIndex = index;
      indexOwner = 'plugin "${plugin.name}"';
    }
    if (plugin.components?.sorter case final sorter?) {
      if (sorterOwner != null) {
        throw ExtensionResolutionException(
          'Component conflict for "sorter": already provided by $sorterOwner; '
          'plugin "${plugin.name}" cannot register the same component slot.',
        );
      }
      resolvedSorter = sorter;
      sorterOwner = 'plugin "${plugin.name}"';
    }
    final pluginHooks = plugin.components?.hooks ?? plugin.hooks;
    if (pluginHooks != null) {
      resolvedHooks = pluginHooks;
    }
  }
  if (overrides?.hooks case final overrideHooks?) {
    resolvedHooks = overrideHooks;
  }

  return ResolvedExtensions(
    plugins: List.unmodifiable(plugins),
    components: SearchlightComponents(
      index: resolvedIndex,
      sorter: resolvedSorter,
      hooks: resolvedHooks,
    ),
  );
}
