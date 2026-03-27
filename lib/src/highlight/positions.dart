/// Represents a match position within text.
final class HighlightPosition {
  /// Creates a [HighlightPosition] with the given [start] and [end] offsets.
  const HighlightPosition({required this.start, required this.end});

  /// The start index (inclusive) of the match in the original text.
  final int start;

  /// The end index (exclusive) of the match in the original text.
  final int end;
}

/// The result of highlighting search terms within text.
final class HighlightResult {
  /// Creates a [HighlightResult] with the given [positions] and [tokens].
  const HighlightResult({required this.positions, required this.tokens});

  /// The positions of all matches found in the text.
  final List<HighlightPosition> positions;

  /// The matched substrings from the original text.
  final List<String> tokens;

  /// Returns a trimmed excerpt of [text] centered around the first match.
  ///
  /// If the text is shorter than or equal to [length], returns the full text.
  /// Otherwise, returns a substring of approximately [length] characters
  /// centered around the first match, with "..." ellipsis markers.
  String trim(String text, int length) {
    if (positions.isEmpty || text.length <= length) {
      return text;
    }

    final firstMatch = positions.first;
    final matchCenter = (firstMatch.start + firstMatch.end) ~/ 2;
    var start = matchCenter - length ~/ 2;
    var end = start + length;

    // Clamp to text bounds
    if (start < 0) {
      start = 0;
      end = length.clamp(0, text.length);
    }
    if (end > text.length) {
      end = text.length;
      start = (end - length).clamp(0, text.length);
    }

    final prefix = start > 0 ? '...' : '';
    final suffix = end < text.length ? '...' : '';

    return '$prefix${text.substring(start, end)}$suffix';
  }
}
