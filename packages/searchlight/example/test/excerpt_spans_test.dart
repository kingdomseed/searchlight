import 'package:flutter_test/flutter_test.dart';
import 'package:searchlight/searchlight.dart';
import 'package:searchlight_example/src/excerpt_spans.dart';

void main() {
  test('buildHighlightedExcerptSpans skips overlapping highlight ranges', () {
    const excerpt = 'fire';
    final result = const Highlighter().highlight(excerpt, 'fire fir');

    final spans = buildHighlightedExcerptSpans(
      excerpt,
      result.positions,
    );
    final text = spans.map((span) => span.text ?? '').join();

    expect(text, excerpt);
  });
}
