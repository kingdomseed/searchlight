import 'package:snowball_stemmer/snowball_stemmer.dart';

/// Maps language names (matching Orama's language keys) to snowball
/// [Algorithm] values.
const _languageToAlgorithm = <String, Algorithm>{
  'arabic': Algorithm.arabic,
  'armenian': Algorithm.armenian,
  'danish': Algorithm.danish,
  'dutch': Algorithm.dutch,
  'english': Algorithm.english,
  'finnish': Algorithm.finnish,
  'french': Algorithm.french,
  'german': Algorithm.german,
  'greek': Algorithm.greek,
  'hungarian': Algorithm.hungarian,
  'indian': Algorithm.hindi,
  'indonesian': Algorithm.indonesian,
  'irish': Algorithm.irish,
  'italian': Algorithm.italian,
  'lithuanian': Algorithm.lithuanian,
  'nepali': Algorithm.nepali,
  'norwegian': Algorithm.norwegian,
  'portuguese': Algorithm.portuguese,
  'romanian': Algorithm.romanian,
  'russian': Algorithm.russian,
  'serbian': Algorithm.serbian,
  'spanish': Algorithm.spanish,
  'swedish': Algorithm.swedish,
  'tamil': Algorithm.tamil,
  'turkish': Algorithm.turkish,
};

/// Returns a stemmer function for [language], or `null` if the language
/// has no snowball stemmer available.
///
/// The returned function takes a token and returns its stemmed form.
String Function(String)? createStemmer(String language) {
  final algorithm = _languageToAlgorithm[language];
  if (algorithm == null) return null;
  final stemmer = SnowballStemmer(algorithm);
  return stemmer.stem;
}
