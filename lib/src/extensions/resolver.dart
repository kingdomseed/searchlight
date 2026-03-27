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
  for (final plugin in plugins) {
    final pluginHooks = plugin.components?.hooks;
    if (pluginHooks != null) {
      resolvedHooks = pluginHooks;
    }
  }
  if (overrides?.hooks case final overrideHooks?) {
    resolvedHooks = overrideHooks;
  }

  return ResolvedExtensions(
    plugins: List.unmodifiable(plugins),
    components: SearchlightComponents(hooks: resolvedHooks),
  );
}
