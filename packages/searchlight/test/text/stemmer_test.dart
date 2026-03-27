import 'package:searchlight/src/text/stemmer.dart';
import 'package:test/test.dart';

void main() {
  group('Stemmer', () {
    test('English stem of running is run', () {
      final stem = createStemmer('english');
      expect(stem, isNotNull);
      expect(stem!('running'), equals('run'));
    });

    test('English stem of dogs is dog', () {
      final stem = createStemmer('english');
      expect(stem, isNotNull);
      expect(stem!('dogs'), equals('dog'));
    });

    test('returns null for unsupported language', () {
      expect(createStemmer('klingon'), isNull);
    });
  });
}
