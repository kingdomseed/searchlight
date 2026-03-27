import 'dart:async';

/// Callback signature for create-time lifecycle hooks.
typedef SearchlightAfterCreateHook = FutureOr<void> Function(Object db);

/// Container for extension lifecycle hooks.
final class SearchlightHooks {
  const SearchlightHooks({this.afterCreate});

  final SearchlightAfterCreateHook? afterCreate;
}
