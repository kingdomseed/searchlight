import 'package:searchlight/src/text/tokenizer.dart';
import 'package:test/test.dart';

void main() {
  group('Tokenizer', () {
    test('tokenizes basic English text', () {
      final tokenizer = Tokenizer();
      expect(tokenizer.tokenize('hello world'), equals(['hello', 'world']));
    });

    test('tokenizes with mixed case to lowercase', () {
      final tokenizer = Tokenizer();
      expect(tokenizer.tokenize('Hello World'), equals(['hello', 'world']));
    });

    test('tokenizes with punctuation', () {
      final tokenizer = Tokenizer();
      expect(tokenizer.tokenize('hello, world!'), equals(['hello', 'world']));
    });

    test('tokenizes with numbers', () {
      final tokenizer = Tokenizer();
      expect(
        tokenizer.tokenize('test 123 foo'),
        equals(['test', '123', 'foo']),
      );
    });

    test('tokenizes with diacritics replaced', () {
      final tokenizer = Tokenizer();
      final tokens = tokenizer.tokenize('caf\u00e9 r\u00e9sum\u00e9');
      expect(tokens, equals(['cafe', 'resume']));
    });

    test('tokenizes with stop words removes them', () {
      final tokenizer = Tokenizer(stopWords: ['the', 'is', 'a']);
      expect(
        tokenizer.tokenize('the cat is a friend'),
        equals(['cat', 'friend']),
      );
    });

    test('tokenizes with stemming enabled', () {
      final tokenizer = Tokenizer(stemming: true);
      expect(
        tokenizer.tokenize('running dogs'),
        equals(['run', 'dog']),
      );
    });

    test('tokenizes without stemming preserves original', () {
      final tokenizer = Tokenizer();
      expect(
        tokenizer.tokenize('running'),
        equals(['running']),
      );
    });

    test('removes duplicates by default', () {
      final tokenizer = Tokenizer();
      expect(
        tokenizer.tokenize('hello hello'),
        equals(['hello']),
      );
    });

    test('keeps duplicates when allowDuplicates is true', () {
      final tokenizer = Tokenizer(allowDuplicates: true);
      expect(
        tokenizer.tokenize('hello hello'),
        equals(['hello', 'hello']),
      );
    });

    test('normalization cache returns same result for repeated input', () {
      final tokenizer = Tokenizer(stemming: true);
      // First call populates cache
      final first = tokenizer.tokenize('running');
      // Second call should hit cache and return identical result
      final second = tokenizer.tokenize('running');
      expect(first, equals(second));
      expect(first, equals(['run']));
    });

    test('tokenizeSkipProperties bypasses splitting and lowercasing', () {
      final tokenizer = Tokenizer(
        tokenizeSkipProperties: {'id'},
      );
      // When property is in skip set, input is NOT split or lowercased,
      // but normalization still runs (for example diacritics replacement).
      expect(
        tokenizer.tokenize('SKU Élite 42', property: 'id'),
        equals(['SKU Elite 42']),
      );
    });

    test('stemmerSkipProperties skips stemming for specified property', () {
      final tokenizer = Tokenizer(
        stemming: true,
        stemmerSkipProperties: {'title'},
      );
      // 'running' is normally stemmed to 'run', but not for 'title' property
      expect(
        tokenizer.tokenize('running', property: 'title'),
        equals(['running']),
      );
      // For other properties, stemming still applies
      expect(
        tokenizer.tokenize('running', property: 'body'),
        equals(['run']),
      );
    });

    // Item 7: Language validation in tokenize()
    test('throws when language parameter mismatches tokenizer language', () {
      final tokenizer = Tokenizer();
      expect(
        () => tokenizer.tokenize('hello', language: 'french'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('does not throw when language matches tokenizer language', () {
      final tokenizer = Tokenizer();
      expect(
        tokenizer.tokenize('hello', language: 'english'),
        equals(['hello']),
      );
    });
  });
}
