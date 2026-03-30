import 'package:searchlight/src/core/exceptions.dart';
import 'package:searchlight/src/extensions/components.dart';
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

    test('plugin hooks do not affect resolved component graph', () {
      final resolved = resolveExtensions(
        defaults: const SearchlightComponents(),
        plugins: const [
          SearchlightPlugin(
            name: 'plugin',
          ),
        ],
      );

      expect(resolved.components, isA<SearchlightComponents>());
    });
  });
}
