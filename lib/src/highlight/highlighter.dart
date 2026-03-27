import 'package:searchlight/src/highlight/positions.dart';

/// A text highlighter that finds occurrences of search terms within text.
///
/// Matches Orama's `@orama/highlight` library behavior.
final class Highlighter {
  /// Creates a [Highlighter].
  ///
  /// [caseSensitive] controls whether matching is case-sensitive
  /// (default false).
  /// [wholeWords] controls whether only complete words are matched
  /// (default false).
  const Highlighter({
    this.caseSensitive = false,
    this.wholeWords = false,
  });

  /// Whether matching is case-sensitive.
  final bool caseSensitive;

  /// Whether only complete words are matched.
  final bool wholeWords;

  /// Finds all occurrences of [searchTerms] in [text].
  ///
  /// [searchTerms] is split on whitespace to produce individual terms.
  /// Returns a [HighlightResult] with positions and matched tokens.
  HighlightResult highlight(String text, String searchTerms) {
    if (searchTerms.trim().isEmpty) {
      return const HighlightResult(positions: [], tokens: []);
    }

    final terms = searchTerms.split(RegExp(r'\s+'));
    final positions = <HighlightPosition>[];
    final tokens = <String>[];

    final searchText = caseSensitive ? text : text.toLowerCase();

    for (final term in terms) {
      final searchTerm = caseSensitive ? term : term.toLowerCase();
      if (wholeWords) {
        final pattern = RegExp(
          '(?<![\\p{L}0-9_])${RegExp.escape(searchTerm)}(?![\\p{L}0-9_])',
          caseSensitive: caseSensitive,
          unicode: true,
        );
        for (final match in pattern.allMatches(searchText)) {
          positions.add(
            HighlightPosition(start: match.start, end: match.end),
          );
          tokens.add(text.substring(match.start, match.end));
        }
      } else {
        var startIndex = 0;
        while (true) {
          final index = searchText.indexOf(searchTerm, startIndex);
          if (index == -1) break;
          positions.add(
            HighlightPosition(start: index, end: index + searchTerm.length),
          );
          tokens.add(text.substring(index, index + searchTerm.length));
          startIndex = index + 1;
        }
      }
    }

    // Sort positions by start index
    positions.sort((a, b) => a.start.compareTo(b.start));

    return HighlightResult(positions: positions, tokens: tokens);
  }
}
