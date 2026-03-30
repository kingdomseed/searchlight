import 'package:flutter/material.dart';
import 'package:searchlight_highlight/searchlight_highlight.dart';

List<TextSpan> buildHighlightedExcerptSpans(
  String excerpt,
  List<Position> positions,
) {
  final spans = <TextSpan>[];
  var cursor = 0;

  for (final position in positions) {
    final start = position.start < cursor ? cursor : position.start;
    final endExclusive = position.end + 1;
    if (start >= endExclusive) {
      continue;
    }
    if (start > cursor) {
      spans.add(TextSpan(text: excerpt.substring(cursor, start)));
    }
    spans.add(
      TextSpan(
        text: excerpt.substring(start, endExclusive),
        style: const TextStyle(
          backgroundColor: Colors.yellow,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    cursor = endExclusive;
  }

  if (cursor < excerpt.length) {
    spans.add(TextSpan(text: excerpt.substring(cursor)));
  }

  return spans;
}
