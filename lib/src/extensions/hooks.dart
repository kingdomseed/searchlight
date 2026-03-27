import 'dart:async';

import 'package:searchlight/src/core/database.dart';

/// Callback signature for create-time lifecycle hooks.
typedef SearchlightAfterCreateHook = FutureOr<void> Function(Searchlight db);

/// Container for extension lifecycle hooks.
final class SearchlightHooks {
  const SearchlightHooks({this.afterCreate});

  final SearchlightAfterCreateHook? afterCreate;
}
