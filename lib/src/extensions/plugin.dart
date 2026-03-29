import 'package:searchlight/src/extensions/components.dart';
import 'package:searchlight/src/extensions/hooks.dart';

/// A create-time extension unit for Searchlight.
final class SearchlightPlugin<TExtra extends Object?> {
  /// Creates a plugin contribution bundle for `Searchlight.create()`.
  const SearchlightPlugin({
    required this.name,
    this.extra,
    this.hooks,
    this.components,
  });

  /// Human-readable plugin name used in diagnostics and conflict errors.
  final String name;

  /// Optional plugin-specific metadata bag carried at create time.
  final TExtra? extra;

  /// Hook contributions registered by this plugin.
  final SearchlightHooks? hooks;

  /// Component overrides contributed by this plugin.
  final SearchlightComponents? components;
}
