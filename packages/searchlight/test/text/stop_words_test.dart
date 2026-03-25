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

    test('Tokenizer with language german auto-filters stop words', () {
      final tokenizer = Tokenizer(language: 'german');
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

    test('all 30 language sets are non-empty', () {
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
        'japanese',
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
        'chinese',
      ];
      expect(languages, hasLength(30));
      for (final lang in languages) {
        final words = stopWordsForLanguage(lang);
        expect(words, isNotEmpty, reason: '$lang should have stop words');
      }
    });
  });
}
