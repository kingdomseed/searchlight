import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

import '../helpers/search_fixture_loader.dart';

Schema _fixtureSchema() {
  return Schema({
    'url': const TypedField(SchemaType.string),
    'title': const TypedField(SchemaType.string),
    'content': const TypedField(SchemaType.string),
    'type': const TypedField(SchemaType.enumType),
    'group': const TypedField(SchemaType.enumType),
  });
}

Searchlight _createDbFromFixture(SearchFixture fixture) {
  final db = Searchlight.create(schema: _fixtureSchema());
  for (final record in fixture.records) {
    db.insert({
      'url': record.url,
      'title': record.title,
      'content': record.content,
      'type': record.type,
      'group': record.group,
    });
  }
  return db;
}

void _assertExpectation(Searchlight db, SearchFixtureExpectation query) {
  final where = query.whereField == null
      ? null
      : <String, Filter>{
          query.whereField!: eq(query.whereEq!),
        };

  final result = db.search(
    term: query.term,
    properties: query.properties,
    limit: query.limit,
    where: where,
  );

  if (query.expectEmpty) {
    expect(result.hits, isEmpty, reason: 'Expected no hits for ${query.name}');
    return;
  }

  expect(result.hits, isNotEmpty, reason: 'No hits for ${query.name}');
  expect(
    result.hits.first.document.getString('url'),
    query.expectedTopUrl,
    reason: 'Unexpected top hit for ${query.name}',
  );

  if (query.assertHighlight) {
    final field = query.highlightField ?? 'content';
    final text = result.hits.first.document.getString(field);
    final highlighted = const Highlighter().highlight(text, query.term);
    expect(
      highlighted.positions,
      isNotEmpty,
      reason: 'Expected highlight positions for ${query.name}',
    );
  }

  if (query.assertJsonRoundTrip) {
    final restored = Searchlight.fromJson(db.toJson());
    final restoredResult = restored.search(
      term: query.term,
      properties: query.properties,
      limit: query.limit,
      where: where,
    );
    expect(restoredResult.hits, isNotEmpty);
    expect(
      restoredResult.hits.first.document.getString('url'),
      query.expectedTopUrl,
      reason: 'Round-trip mismatch for ${query.name}',
    );
  }
}

SearchFixtureExpectation _expectationByName(
  Map<String, SearchFixtureExpectation> byName,
  String name,
) {
  final query = byName[name];
  expect(query, isNotNull, reason: 'Missing fixture expectation "$name"');
  return query!;
}

void main() {
  group('fixture expectations', () {
    late SearchFixture fixture;
    late Map<String, SearchFixtureExpectation> byName;

    setUpAll(() async {
      fixture = await loadSearchFixture();
      byName = {
        for (final expectation in fixture.expectations)
          expectation.name: expectation,
      };
    });

    test('title match query', () async {
      final db = _createDbFromFixture(fixture);
      try {
        _assertExpectation(db, _expectationByName(byName, 'title match query'));
      } finally {
        await db.dispose();
      }
    });

    test('content match query', () async {
      final db = _createDbFromFixture(fixture);
      try {
        _assertExpectation(
          db,
          _expectationByName(byName, 'content match query'),
        );
      } finally {
        await db.dispose();
      }
    });

    test('mixed properties query', () async {
      final db = _createDbFromFixture(fixture);
      try {
        _assertExpectation(
          db,
          _expectationByName(byName, 'mixed properties query'),
        );
      } finally {
        await db.dispose();
      }
    });

    test('enum filter and highlight query', () async {
      final db = _createDbFromFixture(fixture);
      try {
        _assertExpectation(
          db,
          _expectationByName(byName, 'enum filter and highlight query'),
        );
      } finally {
        await db.dispose();
      }
    });

    test('properties exclude url yields no hits', () async {
      final db = _createDbFromFixture(fixture);
      try {
        _assertExpectation(
          db,
          _expectationByName(byName, 'properties exclude url yields no hits'),
        );
      } finally {
        await db.dispose();
      }
    });

    test('properties include url yields hit', () async {
      final db = _createDbFromFixture(fixture);
      try {
        _assertExpectation(
          db,
          _expectationByName(byName, 'properties include url yields hit'),
        );
      } finally {
        await db.dispose();
      }
    });

    test('where filter excludes natural match', () async {
      final db = _createDbFromFixture(fixture);
      try {
        _assertExpectation(
          db,
          _expectationByName(byName, 'where filter excludes natural match'),
        );
      } finally {
        await db.dispose();
      }
    });
  });
}
