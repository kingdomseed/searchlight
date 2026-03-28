import 'package:searchlight/searchlight.dart';

final class TestTracePlugin {
  TestTracePlugin({
    required this.name,
    required this.trace,
    this.includeLoadHooks = false,
  }) : plugin = SearchlightPlugin(
          name: name,
          hooks: SearchlightHooks(
            afterCreate: (_) {
              trace.add('$name:afterCreate');
            },
            beforeInsert: (_, id, __) {
              trace.add('$name:beforeInsert:$id');
            },
            afterInsert: (_, id, __) {
              trace.add('$name:afterInsert:$id');
            },
            beforeSearch: (_, params, __) {
              trace.add('$name:beforeSearch:${params['term']}');
            },
            afterSearch: (_, params, __, ___) {
              trace.add('$name:afterSearch:${params['term']}');
            },
            beforeLoad: includeLoadHooks
                ? (_, __) {
                    trace.add('$name:beforeLoad');
                  }
                : null,
            afterLoad: includeLoadHooks
                ? (_, __) {
                    trace.add('$name:afterLoad');
                  }
                : null,
          ),
        );

  final String name;
  final List<String> trace;
  final bool includeLoadHooks;
  final SearchlightPlugin<Object?> plugin;
}
