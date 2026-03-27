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
    required this.expectedTopUrl,
    required this.limit,
  });

  final String name;
  final String term;
  final List<String> properties;
  final String expectedTopUrl;
  final int limit;
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
  final corpusRaw = await File('test/fixtures/search_corpus.json').readAsString();
  final expectationsRaw =
      await File('test/fixtures/search_expectations.json').readAsString();

  final corpusJson = jsonDecode(corpusRaw) as List<dynamic>;
  final expectationsJson = jsonDecode(expectationsRaw) as List<dynamic>;

  final records = corpusJson
      .cast<Map<String, dynamic>>()
      .map(
        (record) => SearchFixtureRecord(
          url: record['url'] as String,
          title: record['title'] as String,
          content: record['content'] as String,
          type: record['type'] as String,
          group: record['group'] as String,
        ),
      )
      .toList();

  final expectations = expectationsJson
      .cast<Map<String, dynamic>>()
      .map(
        (expectation) => SearchFixtureExpectation(
          name: expectation['name'] as String,
          term: expectation['term'] as String,
          properties: (expectation['properties'] as List<dynamic>)
              .cast<String>()
              .toList(),
          expectedTopUrl: expectation['expectedTopUrl'] as String,
          limit: expectation['limit'] as int? ?? 10,
        ),
      )
      .toList();

  return SearchFixture(records: records, expectations: expectations);
}
