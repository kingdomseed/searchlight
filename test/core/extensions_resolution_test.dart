import 'package:searchlight/src/core/exceptions.dart';
import 'package:searchlight/src/extensions/components.dart';
import 'package:searchlight/src/extensions/hooks.dart';
import 'package:searchlight/src/extensions/plugin.dart';
import 'package:searchlight/src/extensions/resolver.dart';
import 'package:test/test.dart';

void main() {
  group('extension resolution', () {
    test('plugins resolve in declared order', () {
      final resolved = resolveExtensions(
        defaults: const SearchlightComponents(),
        plugins: const [
          SearchlightPlugin(name: 'first'),
          SearchlightPlugin(name: 'second'),
          SearchlightPlugin(name: 'third'),
        ],
      );

      expect(
        resolved.plugins.map((plugin) => plugin.name),
        ['first', 'second', 'third'],
      );
    });

    test('duplicate plugin names fail deterministically', () {
      expect(
        () => resolveExtensions(
          defaults: const SearchlightComponents(),
          plugins: const [
            SearchlightPlugin(name: 'dupe'),
            SearchlightPlugin(name: 'dupe'),
          ],
        ),
        throwsA(
          isA<ExtensionResolutionException>().having(
            (error) => error.message,
            'message',
            contains('dupe'),
          ),
        ),
      );
    });

    test('explicit component overrides win after plugin contributions', () {
      final defaultHooks = SearchlightHooks(afterCreate: (_) {});
      final pluginHooks = SearchlightHooks(afterCreate: (_) {});
      final overrideHooks = SearchlightHooks(afterCreate: (_) {});

      final resolved = resolveExtensions(
        defaults: SearchlightComponents(hooks: defaultHooks),
        plugins: [
          SearchlightPlugin(
            name: 'plugin',
            components: SearchlightComponents(hooks: pluginHooks),
          ),
        ],
        overrides: SearchlightComponents(hooks: overrideHooks),
      );

      expect(identical(resolved.components.hooks, overrideHooks), isTrue);
    });
  });
}
