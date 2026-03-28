import 'package:searchlight/src/core/exceptions.dart';
import 'package:searchlight/src/extensions/components.dart';
import 'package:searchlight/src/extensions/plugin.dart';

/// Resolved extension inputs for a `Searchlight.create()` call.
final class ResolvedExtensions {
  const ResolvedExtensions({
    required this.plugins,
    required this.components,
  });

  final List<SearchlightPlugin<Object?>> plugins;
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
  var resolvedIndex = defaults.index;
  var resolvedSorter = defaults.sorter;
  for (final plugin in plugins) {
    if (plugin.components?.index case final index?) {
      resolvedIndex = index;
    }
    if (plugin.components?.sorter case final sorter?) {
      resolvedSorter = sorter;
    }
    final pluginHooks = plugin.components?.hooks ?? plugin.hooks;
    if (pluginHooks != null) {
      resolvedHooks = pluginHooks;
    }
  }
  if (overrides?.index case final overrideIndex?) {
    resolvedIndex = overrideIndex;
  }
  if (overrides?.sorter case final overrideSorter?) {
    resolvedSorter = overrideSorter;
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
