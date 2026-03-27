/// Language-specific splitter regexes matching Orama's tokenizer.
///
/// Each language has a regex that matches characters NOT in the language's
/// character set, used to split text into tokens.
library;

// Regex patterns use double quotes for Unicode escapes.
// ignore_for_file: prefer_single_quotes

/// All language names supported by the tokenizer.
const supportedLanguages = <String>[
  'arabic',
  'armenian',
  'bulgarian',
  'czech',
  'danish',
  'dutch',
  'english',
  'finnish',
  'french',
  'german',
  'greek',
  'hungarian',
  'indian',
  'indonesian',
  'irish',
  'italian',
  'lithuanian',
  'nepali',
  'norwegian',
  'portuguese',
  'romanian',
  'russian',
  'sanskrit',
  'serbian',
  'slovenian',
  'spanish',
  'swedish',
  'tamil',
  'turkish',
  'ukrainian',
];

/// Splitter regexes keyed by language name.
///
/// These are copied directly from Orama's `languages.ts` SPLITTERS map.
/// Each regex matches characters that are NOT valid token characters for
/// that language, so `String.split(regex)` yields the tokens.
final splitters = <String, RegExp>{
  'dutch': RegExp(
    "[^A-Za-z\u00e0\u00e8\u00e9\u00ec\u00f2\u00f3\u00f90-9_'-]+",
    caseSensitive: false,
  ),
  'english': RegExp(
    "[^A-Za-z\u00e0\u00e8\u00e9\u00ec\u00f2\u00f3\u00f90-9_'-]+",
    caseSensitive: false,
  ),
  'french': RegExp(
    "[^a-z0-9\u00e4\u00e2\u00e0\u00e9\u00e8\u00eb\u00ea"
    "\u00ef\u00ee\u00f6\u00f4\u00f9\u00fc\u00fb\u0153\u00e7-]+",
    caseSensitive: false,
  ),
  'italian': RegExp(
    "[^A-Za-z\u00e0\u00e8\u00e9\u00ec\u00f2\u00f3\u00f90-9_'-]+",
    caseSensitive: false,
  ),
  'norwegian': RegExp(
    "[^a-z0-9_\u00e6\u00f8\u00e5\u00c6\u00d8\u00c5"
    "\u00e4\u00c4\u00f6\u00d6\u00fc\u00dc]+",
    caseSensitive: false,
  ),
  'portuguese': RegExp(
    "[^a-z0-9\u00e0-\u00fa\u00c0-\u00da]",
    caseSensitive: false,
  ),
  'russian': RegExp(
    "[^a-z0-9\u0430-\u044f\u0410-\u042f\u0451\u0401]+",
    caseSensitive: false,
  ),
  'spanish': RegExp(
    "[^a-z0-9A-Z\u00e1-\u00fa\u00c1-\u00da\u00f1\u00d1\u00fc\u00dc]+",
    caseSensitive: false,
  ),
  'swedish': RegExp(
    "[^a-z0-9_\u00e5\u00c5\u00e4\u00c4\u00f6\u00d6\u00fc\u00dc-]+",
    caseSensitive: false,
  ),
  'german': RegExp(
    "[^a-z0-9A-Z\u00e4\u00f6\u00fc\u00c4\u00d6\u00dc\u00df]+",
    caseSensitive: false,
  ),
  'finnish': RegExp(
    "[^a-z0-9\u00e4\u00f6\u00c4\u00d6]+",
    caseSensitive: false,
  ),
  'danish': RegExp(
    "[^a-z0-9\u00e6\u00f8\u00e5\u00c6\u00d8\u00c5]+",
    caseSensitive: false,
  ),
  'hungarian': RegExp(
    "[^a-z0-9\u00e1\u00e9\u00ed\u00f3\u00f6\u0151"
    "\u00fa\u00fc\u0171\u00c1\u00c9\u00cd\u00d3\u00d6\u0150"
    "\u00da\u00dc\u0170]+",
    caseSensitive: false,
  ),
  'romanian': RegExp(
    "[^a-z0-9\u0103\u00e2\u00ee\u0219\u021b\u0102\u00c2"
    "\u00ce\u0218\u021a]+",
    caseSensitive: false,
  ),
  'serbian': RegExp(
    "[^a-z0-9\u010d\u0107\u017e\u0161\u0111\u010c\u0106"
    "\u017d\u0160\u0110]+",
    caseSensitive: false,
  ),
  'turkish': RegExp(
    "[^a-z0-9\u00e7\u00c7\u011f\u011e\u0131\u0130\u00f6"
    "\u00d6\u015f\u015e\u00fc\u00dc]+",
    caseSensitive: false,
  ),
  'lithuanian': RegExp(
    "[^a-z0-9\u0105\u010d\u0119\u0117\u012f\u0161"
    "\u0173\u016b\u017e\u0104\u010c\u0118\u0116\u012e"
    "\u0160\u0172\u016a\u017d]+",
    caseSensitive: false,
  ),
  'arabic': RegExp(
    "[^a-z0-9\u0623-\u064a]+",
    caseSensitive: false,
  ),
  'nepali': RegExp(
    "[^a-z0-9\u0905-\u0939]+",
    caseSensitive: false,
  ),
  'irish': RegExp(
    "[^a-z0-9\u00e1\u00e9\u00ed\u00f3\u00fa\u00c1\u00c9"
    "\u00cd\u00d3\u00da]+",
    caseSensitive: false,
  ),
  'indian': RegExp(
    "[^a-z0-9\u0905-\u0939]+",
    caseSensitive: false,
  ),
  'armenian': RegExp(
    "[^a-z0-9\u0561-\u0586]+",
    caseSensitive: false,
  ),
  'greek': RegExp(
    "[^a-z0-9\u03b1-\u03c9\u03ac-\u03ce]+",
    caseSensitive: false,
  ),
  'indonesian': RegExp(
    '[^a-z0-9]+',
    caseSensitive: false,
  ),
  'ukrainian': RegExp(
    "[^a-z0-9\u0430-\u044f\u0410-\u042f\u0456\u0457"
    "\u0454\u0406\u0407\u0404]+",
    caseSensitive: false,
  ),
  'slovenian': RegExp(
    "[^a-z0-9\u010d\u017e\u0161\u010c\u017d\u0160]+",
    caseSensitive: false,
  ),
  'bulgarian': RegExp(
    "[^a-z0-9\u0430-\u044f\u0410-\u042f]+",
    caseSensitive: false,
  ),
  'tamil': RegExp(
    "[^a-z0-9\u0b85-\u0bb9]+",
    caseSensitive: false,
  ),
  'sanskrit': RegExp(
    "[^a-z0-9A-Z\u0101\u012b\u016b\u1e5b\u1e37\u1e43"
    "\u1e41\u1e25\u015b\u1e63\u1e6d\u1e0d\u1e47\u1e45"
    "\u00f1\u1e3b\u1e39\u1e5d]+",
    caseSensitive: false,
  ),
  'czech': RegExp(
    "[^A-Z0-9a-z\u011b\u0161\u010d\u0159\u017e\u00fd\u00e1"
    "\u00ed\u00e9\u00fa\u016f\u00f3\u0165\u010f\u011a\u0160"
    "\u010c\u0158\u017d\u00dd\u00c1\u00cd\u00c9\u00d3\u00da"
    "\u016e\u0164\u010e-]+",
    caseSensitive: false,
  ),
};
