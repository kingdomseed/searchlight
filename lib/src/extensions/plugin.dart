import 'package:searchlight/src/extensions/components.dart';
import 'package:searchlight/src/extensions/hooks.dart';

/// A create-time extension unit for Searchlight.
final class SearchlightPlugin<TExtra extends Object?> {
  const SearchlightPlugin({
    required this.name,
    this.extra,
    this.hooks,
    this.components,
  });

  final String name;
  final TExtra? extra;
  final SearchlightHooks? hooks;
  final SearchlightComponents? components;
}
