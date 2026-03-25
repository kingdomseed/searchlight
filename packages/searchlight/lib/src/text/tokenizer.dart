import 'package:searchlight/src/text/diacritics.dart';
import 'package:searchlight/src/text/languages.dart';
import 'package:searchlight/src/text/stemmer.dart';

/// Tokenizer matching Orama's DefaultTokenizer pipeline.
///
/// Pipeline: lowercase -> split on language regex -> normalizeToken each ->
/// filter empty -> trim leading/trailing empty -> optionally deduplicate.
final class Tokenizer {
  /// Creates a tokenizer with the given configuration.
  ///
  /// When [stemming] is `true` and no custom [stemmer] is provided, a
  /// snowball stemmer for [language] is used automatically.
  Tokenizer({
    this.language = 'english',
    bool stemming = false,
    String Function(String)? stemmer,
    this.stopWords,
    this.allowDuplicates = false,
    this.tokenizeSkipProperties = const {},
    this.stemmerSkipProperties = const {},
  })  : assert(
          splitters.containsKey(language),
          'Unsupported language: $language',
        ),
        _stemmer = stemmer ?? (stemming ? createStemmer(language) : null);

  /// The language used for splitting text into tokens.
  final String language;

  /// The resolved stemmer function (null if stemming is disabled).
  final String Function(String)? _stemmer;

  /// Optional list of stop words to filter out during normalization.
  final List<String>? stopWords;

  /// Whether to allow duplicate tokens in the output.
  final bool allowDuplicates;

  /// Property names to skip tokenization for (return input as single token).
  final Set<String> tokenizeSkipProperties;

  /// Property names to skip stemming for.
  final Set<String> stemmerSkipProperties;

  final Map<String, String> _normalizationCache = {};

  /// Tokenizes [input] into a list of normalized tokens.
  ///
  /// When [property] is in [tokenizeSkipProperties], returns the input as a
  /// single normalized token instead of splitting.
  List<String> tokenize(
    String input, {
    String? property,
    bool withCache = true,
  }) {
    final prop = property ?? '';

    List<String> tokens;
    if (property != null && tokenizeSkipProperties.contains(property)) {
      tokens = [normalizeToken(prop, input, withCache: withCache)];
    } else {
      final splitRule = splitters[language]!;
      tokens = input
          .toLowerCase()
          .split(splitRule)
          .map((t) => normalizeToken(prop, t, withCache: withCache))
          .where((t) => t.isNotEmpty)
          .toList();
    }

    tokens = _trim(tokens);

    if (!allowDuplicates) {
      return tokens.toSet().toList();
    }

    return tokens;
  }

  /// Normalizes a single token: stop word check, optional stemming,
  /// diacritics replacement.
  String normalizeToken(
    String property,
    String token, {
    bool withCache = true,
  }) {
    final key = '$language:$property:$token';

    if (withCache && _normalizationCache.containsKey(key)) {
      return _normalizationCache[key]!;
    }

    // Remove stop words
    if (stopWords != null && stopWords!.contains(token)) {
      if (withCache) {
        _normalizationCache[key] = '';
      }
      return '';
    }

    var result = token;

    // Apply stemming if enabled and property not skipped
    if (_stemmer != null && !stemmerSkipProperties.contains(property)) {
      result = _stemmer(result);
    }

    result = replaceDiacritics(result);

    if (withCache) {
      _normalizationCache[key] = result;
    }
    return result;
  }

  static List<String> _trim(List<String> tokens) {
    var start = 0;
    var end = tokens.length;
    while (end > start && tokens[end - 1].isEmpty) {
      end--;
    }
    while (start < end && tokens[start].isEmpty) {
      start++;
    }
    if (start == 0 && end == tokens.length) return tokens;
    return tokens.sublist(start, end);
  }
}
