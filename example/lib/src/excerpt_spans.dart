import 'package:flutter/material.dart';
import 'package:searchlight/searchlight.dart';

List<TextSpan> buildHighlightedExcerptSpans(
  String excerpt,
  List<HighlightPosition> positions,
) {
  final spans = <TextSpan>[];
  var cursor = 0;

  for (final position in positions) {
    final start = position.start < cursor ? cursor : position.start;
    if (start >= position.end) {
      continue;
    }
    if (start > cursor) {
      spans.add(TextSpan(text: excerpt.substring(cursor, start)));
    }
    spans.add(
      TextSpan(
        text: excerpt.substring(start, position.end),
        style: const TextStyle(
          backgroundColor: Colors.yellow,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    cursor = position.end;
  }

  if (cursor < excerpt.length) {
    spans.add(TextSpan(text: excerpt.substring(cursor)));
  }

  return spans;
}
