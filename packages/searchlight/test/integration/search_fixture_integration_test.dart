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

void main() {
  const integrationTestName =
      'fixture expectations validate search, filters, highlights, '
      'and JSON persistence';

  test(
    integrationTestName,
    () async {
      final fixture = await loadSearchFixture();
      final db = _createDbFromFixture(fixture);

      try {
        for (final query in fixture.expectations) {
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
      } finally {
        await db.dispose();
      }
    },
  );
}
