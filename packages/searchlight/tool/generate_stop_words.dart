// This is a CLI tool; print() is the intentional output mechanism.
// ignore_for_file: avoid_print
import 'dart:io';

/// Reads Orama's JS stop word files and generates the Dart
/// stop_words.dart file.
void main() {
  final refDir = Directory(
    '../../reference/orama/packages/stopwords/lib',
  );

  if (!refDir.existsSync()) {
    print('Reference directory not found: ${refDir.path}');
    exit(1);
  }

  const langMap = <String, String>{
    'am': 'armenian',
    'ar': 'arabic',
    'bg': 'bulgarian',
    'de': 'german',
    'dk': 'danish',
    'en': 'english',
    'es': 'spanish',
    'fi': 'finnish',
    'fr': 'french',
    'gr': 'greek',
    'hu': 'hungarian',
    'id': 'indonesian',
    'ie': 'irish',
    'in': 'indian',
    'it': 'italian',
    'ja': 'japanese',
    'lt': 'lithuanian',
    'nl': 'dutch',
    'no': 'norwegian',
    'np': 'nepali',
    'pt': 'portuguese',
    'ro': 'romanian',
    'rs': 'serbian',
    'ru': 'russian',
    'se': 'swedish',
    'sk': 'sanskrit',
    'ta': 'tamil',
    'tr': 'turkish',
    'uk': 'ukrainian',
    'zh': 'chinese',
  };

  final langOrder = [
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

  // Parse JS files
  final allWords = <String, List<String>>{};
  // Match single-quoted strings (content may contain double quotes)
  final singlePattern = RegExp(r"'((?:[^'\\]|\\.)*)'");
  // Match double-quoted strings (content may contain single quotes)
  final doublePattern = RegExp(r'"((?:[^"\\]|\\.)*)"');

  for (final entry in langMap.entries) {
    final file = File('${refDir.path}/${entry.key}.js');
    if (!file.existsSync()) {
      print('Missing file: ${file.path}');
      continue;
    }
    final content = file.readAsStringSync();
    // Find the array content between [ and ]
    final bracketStart = content.indexOf('[');
    final bracketEnd = content.lastIndexOf(']');
    if (bracketStart < 0 || bracketEnd < 0) continue;
    final arrayContent = content.substring(bracketStart + 1, bracketEnd);

    final words = <String>[];
    // Find all string literals (both single and double quoted)
    var pos = 0;
    while (pos < arrayContent.length) {
      final ch = arrayContent[pos];
      if (ch == "'") {
        final match = singlePattern.matchAsPrefix(arrayContent, pos);
        if (match != null) {
          words.add(match.group(1)!.replaceAll(r"\'", "'"));
          pos = match.end;
          continue;
        }
      } else if (ch == '"') {
        final match = doublePattern.matchAsPrefix(arrayContent, pos);
        if (match != null) {
          words.add(match.group(1)!.replaceAll(r'\"', '"'));
          pos = match.end;
          continue;
        }
      }
      pos++;
    }
    allWords[entry.value] = words;
    print('${entry.value}: ${words.length} words');
  }

  // Generate Dart file
  final buf = StringBuffer()
    ..writeln(
      "/// Built-in stop word lists by language, matching Orama's "
      '`@orama/stopwords`.',
    )
    ..writeln('///')
    ..writeln(
      '/// Each language has a `const Set<String>` of stop words for O(1) '
      'lookup.',
    )
    ..writeln(
      '/// Use [stopWordsForLanguage] to get the stop word set for a given '
      'language.',
    )
    ..writeln('library;\n')
    ..writeln('/// Returns the built-in stop word set for [language].')
    ..writeln('///')
    ..writeln(
      '/// Returns an empty set if the language is not supported.',
    )
    ..writeln(
      "/// Language names match Orama's STEMMERS map "
      "(e.g. 'english', 'german').",
    )
    ..writeln('Set<String> stopWordsForLanguage(String language) {')
    ..writeln('  return _stopWords[language] ?? const <String>{};')
    ..writeln('}\n')
    ..writeln('/// Common English stop words.')
    ..writeln('///')
    ..writeln('/// @deprecated Use [stopWordsForLanguage] instead.')
    ..writeln('const englishStopWords = <String>[');
  const legacyWords = [
    'a',
    'an',
    'and',
    'are',
    'as',
    'at',
    'be',
    'but',
    'by',
    'for',
    'from',
    'had',
    'has',
    'have',
    'he',
    'her',
    'his',
    'how',
    'i',
    'if',
    'in',
    'into',
    'is',
    'it',
    'its',
    'me',
    'my',
    'no',
    'not',
    'of',
    'on',
    'or',
    'our',
    'she',
    'so',
    'than',
    'that',
    'the',
    'their',
    'them',
    'then',
    'there',
    'these',
    'they',
    'this',
    'to',
    'up',
    'was',
    'we',
    'were',
    'what',
    'when',
    'where',
    'which',
    'who',
    'will',
    'with',
    'you',
    'your',
  ];
  for (final w in legacyWords) {
    buf.writeln("  '$w',");
  }
  buf
    ..writeln('];\n')
    ..writeln('/// Map of language name to stop word set.')
    ..writeln('const _stopWords = <String, Set<String>>{');
  for (final lang in langOrder) {
    buf.writeln("  '$lang': _$lang,");
  }
  buf.writeln('};\n');

  for (final lang in langOrder) {
    final words = allWords[lang];
    if (words == null) {
      print('WARNING: No words for $lang');
      continue;
    }
    final fileCode = langMap.entries.firstWhere((e) => e.value == lang).key;
    // Use a Set to deduplicate (Orama arrays may have dupes)
    final unique = words.toSet();
    buf
      ..writeln('// $lang ($fileCode.js) - ${unique.length} words')
      ..writeln('const _$lang = <String>{');
    for (final w in unique) {
      if (w.contains("'")) {
        // Use double-quoted string for words with single quotes
        final escaped = w.replaceAll(r'\', r'\\').replaceAll(r'$', r'\$');
        buf.writeln('  "$escaped",');
      } else {
        final escaped = w.replaceAll(r'\', r'\\').replaceAll(r'$', r'\$');
        buf.writeln("  '$escaped',");
      }
    }
    buf.writeln('};\n');
  }

  final outFile = File('lib/src/text/stop_words.dart')
    ..writeAsStringSync(buf.toString());
  print('\nGenerated ${outFile.path}');
}
