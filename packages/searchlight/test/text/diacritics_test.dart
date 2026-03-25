import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

void main() {
  group('replaceDiacritics', () {
    test('replaces e-acute in café', () {
      expect(replaceDiacritics('café'), equals('cafe'));
    });

    test('replaces i-diaeresis in naïve', () {
      expect(replaceDiacritics('naïve'), equals('naive'));
    });

    test('replaces u-diaeresis in über', () {
      expect(replaceDiacritics('über'), equals('uber'));
    });

    test('returns ASCII string unchanged', () {
      expect(replaceDiacritics('hello'), equals('hello'));
    });

    test('replaces uppercase Latin Extended-A diacritics', () {
      expect(replaceDiacritics('ÀÁÂÃÄÅÆ'), equals('AAAAAAA'));
    });

    test('returns empty string for empty input', () {
      expect(replaceDiacritics(''), equals(''));
    });

    test('passes CJK characters through unchanged', () {
      expect(replaceDiacritics('日本語'), equals('日本語'));
    });

    test('handles boundary: charcode 191 unchanged, charcode 192 mapped', () {
      // charcode 191 = ¿ (just below range start of 192)
      final belowRange = String.fromCharCode(191);
      expect(replaceDiacritics(belowRange), equals('¿'));

      // charcode 192 = À (first entry in mapping, maps to 65 = 'A')
      final atRangeStart = String.fromCharCode(192);
      expect(replaceDiacritics(atRangeStart), equals('A'));
    });
  });
}
