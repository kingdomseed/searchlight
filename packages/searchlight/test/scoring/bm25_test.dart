import 'package:searchlight/src/scoring/bm25.dart';
import 'package:test/test.dart';

void main() {
  group('BM25', () {
    test('returns d * idf / k when tf is 0 (d parameter contributes)', () {
      // With tf=0, BM25 = idf * d / (k * (1 - b + b * fieldLength / avgFL))
      // When fieldLength == averageFieldLength, denominator = k * 1 = k
      // So BM25 = idf * d / k
      final score = bm25(
        tf: 0,
        matchingCount: 1,
        docsCount: 10,
        fieldLength: 5,
        averageFieldLength: 5,
        params: const BM25Params(), // k=1.2, b=0.75, d=0.5
      );
      // idf = ln(1 + (10 - 1 + 0.5) / (1 + 0.5)) = ln(1 + 9.5/1.5)
      //     = ln(1 + 6.333...) = ln(7.333...)
      // BM25 = idf * 0.5 / 1.2
      expect(score, greaterThan(0));
      expect(score, closeTo(0.8301792352875859, 1e-10));
    });
    test('returns positive score for matching term', () {
      final score = bm25(
        tf: 0.5,
        matchingCount: 3,
        docsCount: 10,
        fieldLength: 4,
        averageFieldLength: 5,
        params: const BM25Params(),
      );
      expect(score, greaterThan(0));
    });

    test('score increases with higher term frequency', () {
      final lowTfScore = bm25(
        tf: 0.1,
        matchingCount: 3,
        docsCount: 10,
        fieldLength: 5,
        averageFieldLength: 5,
        params: const BM25Params(),
      );
      final highTfScore = bm25(
        tf: 0.9,
        matchingCount: 3,
        docsCount: 10,
        fieldLength: 5,
        averageFieldLength: 5,
        params: const BM25Params(),
      );
      expect(highTfScore, greaterThan(lowTfScore));
    });

    test('scores rare terms higher than common terms (IDF effect)', () {
      // Rare term: appears in 1 of 100 docs
      final rareScore = bm25(
        tf: 0.5,
        matchingCount: 1,
        docsCount: 100,
        fieldLength: 5,
        averageFieldLength: 5,
        params: const BM25Params(),
      );
      // Common term: appears in 50 of 100 docs
      final commonScore = bm25(
        tf: 0.5,
        matchingCount: 50,
        docsCount: 100,
        fieldLength: 5,
        averageFieldLength: 5,
        params: const BM25Params(),
      );
      expect(rareScore, greaterThan(commonScore));
    });
    test('with default params k=1.2, b=0.75, d=0.5 matches known computation',
        () {
      // Known values: tf=0.25, matchingCount=2, docsCount=10,
      // fieldLength=8, avgFieldLength=5, k=1.2, b=0.75, d=0.5
      //
      // idf = ln(1 + (10 - 2 + 0.5) / (2 + 0.5))
      //     = ln(1 + 8.5 / 2.5) = ln(1 + 3.4) = ln(4.4)
      // numerator = idf * (0.5 + 0.25 * 2.2) = idf * (0.5 + 0.55) = idf * 1.05
      // denominator = 0.25 + 1.2 * (1 - 0.75 + 0.75 * 8 / 5)
      //             = 0.25 + 1.2 * (0.25 + 1.2) = 0.25 + 1.2 * 1.45 = 0.25 + 1.74
      //             = 1.99
      // result = idf * 1.05 / 1.99

      final score = bm25(
        tf: 0.25,
        matchingCount: 2,
        docsCount: 10,
        fieldLength: 8,
        averageFieldLength: 5,
        params: const BM25Params(),
      );

      // Manually computed:
      // idf = ln(1 + (10-2+0.5)/(2+0.5)) = ln(1+3.4) = ln(4.4)
      // num = ln(4.4) * (0.5 + 0.25*2.2) = ln(4.4) * 1.05
      // den = 0.25 + 1.2*(1-0.75+0.75*8/5) = 0.25+1.2*(0.25+1.2) = 0.25+1.74 = 1.99
      // result = ln(4.4)*1.05/1.99
      expect(score, closeTo(0.7821, 0.001));
    });
  });
}
