import 'package:searchlight/src/highlight/highlighter.dart';
import 'package:test/test.dart';

void main() {
  group('Highlighter', () {
    test('returns correct positions for single term', () {
      const highlighter = Highlighter();
      final result = highlighter.highlight(
        'The quick brown fox jumps over the lazy dog',
        'brown',
      );

      expect(result.positions, hasLength(1));
      expect(result.positions[0].start, equals(10));
      expect(result.positions[0].end, equals(15));
    });

    test('returns correct positions for multiple terms', () {
      const highlighter = Highlighter();
      final result = highlighter.highlight(
        'The quick brown fox jumps over the lazy dog',
        'quick lazy',
      );

      expect(result.positions, hasLength(2));
      expect(result.positions[0].start, equals(4));
      expect(result.positions[0].end, equals(9));
      expect(result.positions[1].start, equals(35));
      expect(result.positions[1].end, equals(39));
    });

    test('is case-insensitive by default', () {
      const highlighter = Highlighter();
      final result = highlighter.highlight(
        'The Quick Brown Fox',
        'quick',
      );

      expect(result.positions, hasLength(1));
      expect(result.positions[0].start, equals(4));
      expect(result.positions[0].end, equals(9));
    });

    test('with caseSensitive=true only matches exact case', () {
      const highlighter = Highlighter(caseSensitive: true);
      final result = highlighter.highlight(
        'The Quick Brown Fox',
        'quick',
      );

      expect(result.positions, isEmpty);
      expect(result.tokens, isEmpty);

      final result2 = highlighter.highlight(
        'The Quick Brown Fox',
        'Quick',
      );

      expect(result2.positions, hasLength(1));
      expect(result2.positions[0].start, equals(4));
      expect(result2.positions[0].end, equals(9));
    });

    test('with wholeWords=false matches partial words (default)', () {
      const highlighter = Highlighter();
      final result = highlighter.highlight(
        'The brownish fox is brownest',
        'brown',
      );

      expect(result.positions, hasLength(2));
      expect(result.positions[0].start, equals(4));
      expect(result.positions[0].end, equals(9));
      expect(result.positions[1].start, equals(20));
      expect(result.positions[1].end, equals(25));
    });

    test('with wholeWords=true only matches complete words', () {
      const highlighter = Highlighter(wholeWords: true);
      final result = highlighter.highlight(
        'The brownish fox brown brownest',
        'brown',
      );

      expect(result.positions, hasLength(1));
      expect(result.positions[0].start, equals(17));
      expect(result.positions[0].end, equals(22));
    });

    test('tokens returns the matched substrings', () {
      const highlighter = Highlighter();
      final result = highlighter.highlight(
        'The Quick Brown Fox',
        'quick brown',
      );

      expect(result.tokens, containsAll(['Quick', 'Brown']));
      expect(result.tokens, hasLength(2));
    });

    test(
      'trim returns excerpt centered around first match with ellipsis',
      () {
        const highlighter = Highlighter();
        const text = 'The quick brown fox jumps over '
            'the lazy dog and more text follows';
        final result = highlighter.highlight(text, 'lazy');

        final trimmed = result.trim(text, 20);
        expect(trimmed, contains('lazy'));
        expect(trimmed, startsWith('...'));
        expect(trimmed, endsWith('...'));
        // +6 for two "..."
        expect(trimmed.length, lessThanOrEqualTo(20 + 6));
      },
    );

    test('trim with short text returns full text (no ellipsis needed)', () {
      const highlighter = Highlighter();
      const text = 'The quick brown fox';
      final result = highlighter.highlight(text, 'brown');

      final trimmed = result.trim(text, 50);
      expect(trimmed, equals(text));
    });

    test('with no matches returns empty positions and tokens', () {
      const highlighter = Highlighter();
      final result = highlighter.highlight(
        'The quick brown fox',
        'zebra',
      );

      expect(result.positions, isEmpty);
      expect(result.tokens, isEmpty);
    });

    test('with empty search term returns empty results', () {
      const highlighter = Highlighter();
      final result = highlighter.highlight(
        'The quick brown fox',
        '',
      );

      expect(result.positions, isEmpty);
      expect(result.tokens, isEmpty);

      final result2 = highlighter.highlight(
        'The quick brown fox',
        '   ',
      );

      expect(result2.positions, isEmpty);
      expect(result2.tokens, isEmpty);
    });

    test('with overlapping matches handles correctly', () {
      const highlighter = Highlighter();
      // "abab" searching for "aba" - overlapping occurrence at 0 and 2
      final result = highlighter.highlight('abab', 'aba');

      // Should find the match starting at index 0
      expect(result.positions, hasLength(1));
      expect(result.positions[0].start, equals(0));
      expect(result.positions[0].end, equals(3));
    });
  });
}
