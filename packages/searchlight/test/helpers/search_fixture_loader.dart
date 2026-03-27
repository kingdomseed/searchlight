import 'dart:convert';
import 'dart:io';

final class SearchFixtureRecord {
  const SearchFixtureRecord({
    required this.url,
    required this.title,
    required this.content,
    required this.type,
    required this.group,
  });

  final String url;
  final String title;
  final String content;
  final String type;
  final String group;
}

final class SearchFixtureExpectation {
  const SearchFixtureExpectation({
    required this.name,
    required this.term,
    required this.properties,
    required this.limit,
    required this.expectedTopUrl,
    required this.expectEmpty,
    this.whereField,
    this.whereEq,
    this.highlightField,
    this.assertHighlight = false,
    this.assertJsonRoundTrip = false,
  });

  final String name;
  final String term;
  final List<String> properties;
  final int limit;
  final String? expectedTopUrl;
  final bool expectEmpty;
  final String? whereField;
  final String? whereEq;
  final String? highlightField;
  final bool assertHighlight;
  final bool assertJsonRoundTrip;
}

final class SearchFixture {
  const SearchFixture({
    required this.records,
    required this.expectations,
  });

  final List<SearchFixtureRecord> records;
  final List<SearchFixtureExpectation> expectations;
}

Future<SearchFixture> loadSearchFixture() async {
  final corpusFile = _resolveFixtureFile('search_corpus.json');
  final expectationsFile = _resolveFixtureFile('search_expectations.json');

  final corpusRaw = await corpusFile.readAsString();
  final expectationsRaw = await expectationsFile.readAsString();

  final corpusJson = _readTopLevelList(
    jsonDecode(corpusRaw),
    'search_corpus.json',
  );
  final expectationsJson = _readTopLevelList(
    jsonDecode(expectationsRaw),
    'search_expectations.json',
  );

  final records = <SearchFixtureRecord>[];
  for (var i = 0; i < corpusJson.length; i++) {
    final context = 'search_corpus.json entry #$i';
    final record = _readMap(corpusJson[i], context);
    records.add(
      SearchFixtureRecord(
        url: _readString(record, 'url', context),
        title: _readString(record, 'title', context),
        content: _readString(record, 'content', context),
        type: _readString(record, 'type', context),
        group: _readString(record, 'group', context),
      ),
    );
  }

  final expectations = <SearchFixtureExpectation>[];
  for (var i = 0; i < expectationsJson.length; i++) {
    final context = 'search_expectations.json entry #$i';
    final expectation = _readMap(expectationsJson[i], context);
    final whereField = _readOptionalString(expectation, 'whereField', context);
    final whereEq = _readOptionalString(expectation, 'whereEq', context);
    final expectEmpty = _readBool(
      expectation,
      'expectEmpty',
      context,
      defaultValue: false,
    );
    final expectedTopUrl = _readOptionalString(
      expectation,
      'expectedTopUrl',
      context,
    );
    if ((whereField == null) != (whereEq == null)) {
      throw FormatException(
        '$context fields "whereField" and "whereEq" must be provided together',
      );
    }
    if (!expectEmpty && expectedTopUrl == null) {
      throw FormatException(
        '$context must provide "expectedTopUrl" when "expectEmpty" is false',
      );
    }
    if (expectEmpty && expectedTopUrl != null) {
      throw FormatException(
        '$context must not provide "expectedTopUrl" when "expectEmpty" is true',
      );
    }
    expectations.add(
      SearchFixtureExpectation(
        name: _readString(expectation, 'name', context),
        term: _readString(expectation, 'term', context),
        properties: _readStringList(expectation, 'properties', context),
        limit: _readInt(expectation, 'limit', context, defaultValue: 10),
        expectedTopUrl: expectedTopUrl,
        expectEmpty: expectEmpty,
        whereField: whereField,
        whereEq: whereEq,
        highlightField: _readOptionalString(
          expectation,
          'highlightField',
          context,
        ),
        assertHighlight: _readBool(
          expectation,
          'assertHighlight',
          context,
          defaultValue: false,
        ),
        assertJsonRoundTrip: _readBool(
          expectation,
          'assertJsonRoundTrip',
          context,
          defaultValue: false,
        ),
      ),
    );
  }

  return SearchFixture(records: records, expectations: expectations);
}

List<dynamic> _readTopLevelList(dynamic value, String fileName) {
  if (value is List<dynamic>) {
    return value;
  }
  throw FormatException('$fileName must be a JSON array');
}

File _resolveFixtureFile(String fileName) {
  var current = Directory.current.absolute;
  while (true) {
    final packageCandidate = File('${current.path}/test/fixtures/$fileName');
    if (packageCandidate.existsSync()) {
      return packageCandidate;
    }

    final repoCandidate =
        File('${current.path}/packages/searchlight/test/fixtures/$fileName');
    if (repoCandidate.existsSync()) {
      return repoCandidate;
    }

    final parent = current.parent;
    if (parent.path == current.path) {
      final path = Directory.current.path;
      throw FileSystemException(
        'Could not locate fixture file "$fileName" from $path',
      );
    }
    current = parent;
  }
}

Map<String, dynamic> _readMap(dynamic value, String context) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  throw FormatException('$context must be a JSON object');
}

String _readString(Map<String, dynamic> map, String key, String context) {
  final value = map[key];
  if (value is String) {
    return value;
  }
  throw FormatException('$context field "$key" must be a string');
}

List<String> _readStringList(
  Map<String, dynamic> map,
  String key,
  String context,
) {
  final value = map[key];
  if (value is List<dynamic> && value.every((entry) => entry is String)) {
    return value.cast<String>();
  }
  throw FormatException('$context field "$key" must be a list of strings');
}

int _readInt(
  Map<String, dynamic> map,
  String key,
  String context, {
  required int defaultValue,
}) {
  final value = map[key];
  if (value == null) {
    return defaultValue;
  }
  if (value is int) {
    return value;
  }
  throw FormatException('$context field "$key" must be an int');
}

String? _readOptionalString(
  Map<String, dynamic> map,
  String key,
  String context,
) {
  final value = map[key];
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  throw FormatException('$context field "$key" must be a string');
}

bool _readBool(
  Map<String, dynamic> map,
  String key,
  String context, {
  required bool defaultValue,
}) {
  final value = map[key];
  if (value == null) {
    return defaultValue;
  }
  if (value is bool) {
    return value;
  }
  throw FormatException(
    '$context field "$key" must be a bool',
  );
}
