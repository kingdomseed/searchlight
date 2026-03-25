import 'package:searchlight/src/text/diacritics.dart';
import 'package:searchlight/src/text/languages.dart';
import 'package:searchlight/src/text/stemmer.dart';
import 'package:searchlight/src/text/stop_words.dart';

/// Tokenizer matching Orama's DefaultTokenizer pipeline.
///
/// Pipeline: lowercase -> split on language regex -> normalizeToken each ->
/// filter empty -> trim leading/trailing empty -> optionally deduplicate.
///
/// **Searchlight enhancement (Item 8/20):** Orama only has a built-in English
/// stemmer and throws `MISSING_STEMMER` for non-English languages without a
/// custom stemmer. Searchlight provides broader stemmer coverage via the
/// `snowball_stemmer` package, supporting 29 languages out of the box. This
/// means Searchlight can produce stemmed tokens for non-English languages
/// where Orama would error. This is an intentional enhancement, not a
/// divergence.
final class Tokenizer {
  /// Creates a tokenizer with the given configuration.
  ///
  /// When [stemming] is `true` and no custom [stemmer] is provided, a
  /// snowball stemmer for [language] is used automatically.
  ///
  /// When [stopWords] is not provided, the built-in stop word list for
  /// [language] is used automatically (matching Orama's `@orama/stopwords`).
  /// Pass an empty list to disable stop word filtering.
  Tokenizer({
    this.language = 'english',
    bool stemming = false,
    String Function(String)? stemmer,
    List<String>? stopWords,
    bool? useDefaultStopWords,
    this.allowDuplicates = false,
    this.tokenizeSkipProperties = const {},
    this.stemmerSkipProperties = const {},
  })  : assert(
          splitters.containsKey(language),
          'Unsupported language: $language',
        ),
        _stemmer = stemmer ?? (stemming ? createStemmer(language) : null),
        _stopWords = _resolveStopWords(
          stopWords,
          useDefaultStopWords,
          language,
        );

  /// The language used for splitting text into tokens.
  final String language;

  /// The resolved stemmer function (null if stemming is disabled).
  final String Function(String)? _stemmer;

  /// The resolved stop words set (null if stop words are disabled).
  final Set<String>? _stopWords;

  /// Returns the stop words in use (for inspection/testing).
  List<String>? get stopWords => _stopWords?.toList();

  static Set<String>? _resolveStopWords(
    List<String>? explicit,
    bool? useDefault,
    String language,
  ) {
    // If explicit stop words provided, use them
    if (explicit != null) {
      if (explicit.isEmpty) return null; // empty list = disabled
      return explicit.toSet();
    }
    // If useDefault is explicitly false, disable
    if (useDefault == false) return null;
    // Default: use built-in stop words for the language
    final builtIn = stopWordsForLanguage(language);
    return builtIn.isNotEmpty ? builtIn : null;
  }

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
    String? language,
  }) {
    // Item 7: Orama validates language && language !== this.language
    if (language != null && language != this.language) {
      throw ArgumentError(
        'Language mismatch: tokenizer language is "${this.language}", '
        'but tokenize was called with "$language".',
      );
    }

    final prop = property ?? '';

    List<String> tokens;
    if (property != null && tokenizeSkipProperties.contains(property)) {
      tokens = [normalizeToken(prop, input, withCache: withCache)];
    } else {
      final splitRule = splitters[this.language]!;
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
    if (_stopWords != null && _stopWords.contains(token)) {
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
