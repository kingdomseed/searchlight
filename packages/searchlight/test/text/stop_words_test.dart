import 'package:searchlight/src/text/stop_words.dart';
import 'package:searchlight/src/text/tokenizer.dart';
import 'package:test/test.dart';

void main() {
  group('stopWordsForLanguage', () {
    test('returns non-empty set for English containing the, is, at', () {
      final words = stopWordsForLanguage('english');
      expect(words, isNotEmpty);
      expect(words, contains('the'));
      expect(words, contains('is'));
      expect(words, contains('at'));
    });

    test('returns non-empty set for German containing der, die, das', () {
      final words = stopWordsForLanguage('german');
      expect(words, isNotEmpty);
      expect(words, contains('der'));
      expect(words, contains('die'));
      expect(words, contains('das'));
    });

    test('returns non-empty set for French containing le, la, les', () {
      final words = stopWordsForLanguage('french');
      expect(words, isNotEmpty);
      expect(words, contains('le'));
      expect(words, contains('la'));
      expect(words, contains('les'));
    });

    test('returns empty set for unknown language', () {
      final words = stopWordsForLanguage('unknown');
      expect(words, isEmpty);
    });

    test('default Tokenizer does NOT auto-apply stop words (matches Orama)',
        () {
      // Orama's tokenizer defaults to NO stop word filtering.
      // Stop words must be explicitly opted in.
      final tokenizer = Tokenizer(language: 'german');
      final tokens = tokenizer.tokenize('der hund die katze');
      // All tokens preserved — no auto-filtering
      expect(tokens, contains('der'));
      expect(tokens, contains('die'));
      expect(tokens, contains('hund'));
      expect(tokens, contains('katze'));
    });

    test('Tokenizer with useDefaultStopWords: true auto-filters stop words',
        () {
      final tokenizer = Tokenizer(
        language: 'german',
        useDefaultStopWords: true,
      );
      // 'der' and 'die' are German stop words, should be filtered
      final tokens = tokenizer.tokenize('der hund die katze');
      expect(tokens, isNot(contains('der')));
      expect(tokens, isNot(contains('die')));
      expect(tokens, contains('hund'));
      expect(tokens, contains('katze'));
    });

    test('Tokenizer with explicit stopWords overrides built-in list', () {
      // German built-in has 'der', 'die', 'das'. Override with custom list.
      final tokenizer = Tokenizer(
        language: 'german',
        stopWords: ['hund'],
      );
      final tokens = tokenizer.tokenize('der hund die katze');
      // 'der' and 'die' should NOT be filtered (custom list overrides)
      expect(tokens, contains('der'));
      expect(tokens, contains('die'));
      // 'hund' SHOULD be filtered (it's in the custom list)
      expect(tokens, isNot(contains('hund')));
      expect(tokens, contains('katze'));
    });

    test('all 28 tokenizer-supported language sets are non-empty', () {
      const languages = [
        'armenian',
        'arabic',
        'bulgarian',
        'german',
        'danish',
        'english',
        'spanish',
        'finnish',
        'french',
        'greek',
        'hungarian',
        'indonesian',
        'irish',
        'indian',
        'italian',
        'lithuanian',
        'dutch',
        'norwegian',
        'nepali',
        'portuguese',
        'romanian',
        'serbian',
        'russian',
        'swedish',
        'sanskrit',
        'tamil',
        'turkish',
        'ukrainian',
      ];
      expect(languages, hasLength(28));
      for (final lang in languages) {
        final words = stopWordsForLanguage(lang);
        expect(words, isNotEmpty, reason: '$lang should have stop words');
      }
    });

    test(
      'japanese and chinese are not in the lookup map '
      '(no tokenizer support)',
      () {
        // These languages have const stop word sets available directly
        // but are not auto-resolved via stopWordsForLanguage because
        // the tokenizer does not support them.
        expect(stopWordsForLanguage('japanese'), isEmpty);
        expect(stopWordsForLanguage('chinese'), isEmpty);
      },
    );
  });
}
