# Searchlight App Integration Guide

This guide shows how to integrate `searchlight` into a real Dart or Flutter
application.

## What Searchlight Owns

Searchlight owns:

- indexing structured records
- querying those records
- persistence and restore
- standalone highlight helpers

Your app owns:

- loading or downloading source content
- extracting source content into records
- deciding when indexes are built or refreshed
- rendering results in UI

That separation is intentional. It keeps the core package portable and makes it
easy to reuse with local assets, remote content, or user-imported files.

At the `Searchlight` database level, `Searchlight.create()` supports both the
core database configuration (`schema`, `algorithm`, `language`) and the built-in
tokenizer configuration (`stemming`, `stemmer`, `stopWords`,
`useDefaultStopWords`, `allowDuplicates`, `tokenizeSkipProperties`, and
`stemmerSkipProperties`).

By default, stemming is off, matching Orama's default tokenizer behavior.
Persisted snapshots can restore those built-in tokenizer settings. Injected
`Tokenizer` instances and custom stemmer callbacks must be recreated by the
app instead of serialized.

## Recommended Record Shape

Use a small, explicit record shape first. For content-heavy apps, this is a
good baseline:

```dart
{
  'id': 'ember-lance',
  'url': '/spells/ember-lance',
  'title': 'Ember Lance',
  'content': 'A focused lance of heat that ignites dry brush.',
  'type': 'spell',
  'group': 'fire',
}
```

Recommended schema:

```dart
final schema = Schema({
  'url': const TypedField(SchemaType.string),
  'title': const TypedField(SchemaType.string),
  'content': const TypedField(SchemaType.string),
  'type': const TypedField(SchemaType.enumType),
  'group': const TypedField(SchemaType.enumType),
});
```

This shape maps well to docs, glossaries, bestiaries, notes, and extracted PDF
pages.

If you want a reusable extraction layer, keep it in your app or in a companion
package and have it return record maps in your schema shape. If your extraction
logic is small and app-specific, ad hoc conversion functions are often
simpler.

## Build the Index

Create the database once, then insert records as they are prepared.

```dart
final db = Searchlight.create(schema: schema);

for (final record in records) {
  db.insert(record);
}
```

Searchlight indexes records during `insert()`. You do not need a separate
"build index" command inside the database itself.

## Restore Instead of Rebuilding at Runtime

For production apps, do the heavier indexing work once, persist the result, and
restore it on later launches.

```dart
Future<void> persistAndRestore(Searchlight db) async {
  final storage = FileStorage(path: 'search-index.cbor');

  await db.persist(storage: storage);

  final restored = await Searchlight.restore(storage: storage);
  await restored.dispose();
}
```

`FileStorage` is a good default on desktop and mobile. If you want persisted
JSON instead of CBOR, use `format: PersistenceFormat.json` with both
`persist()` and `restore()`. For web or for custom cache layers, use
`toJson()` and `fromJson()` directly or provide your own
`SearchlightStorage` implementation.

A common pattern is:

1. first launch or content refresh: build and persist
2. normal launch: restore and search

## Repository Pattern

Keep Searchlight behind a small service or repository instead of wiring it
directly into widgets.

```dart
final class SearchRepository {
  SearchRepository(this._db);

  final Searchlight _db;

  SearchResult search(String query) {
    return _db.search(
      term: query,
      properties: const ['title', 'content'],
      limit: 10,
    );
  }
}
```

This makes it easier to swap data sources, rebuild indexes, or move from raw
records to persisted snapshots later.

## Render Search Results

Searchlight returns `SearchHit` objects with the external ID, score, and
document.

```dart
final result = repository.search('ember');

for (final hit in result.hits) {
  final title = hit.document.getString('title');
  final content = hit.document.getString('content');
}
```

If you want snippets or marked ranges, use `Highlighter` after search:

```dart
final highlighter = Highlighter();

String buildExcerpt(SearchHit hit, String query) {
  final content = hit.document.getString('content');
  final result = highlighter.highlight(content, query);
  return result.trim(content, 180);
}
```

## Choose When to Reindex

Typical triggers:

- app receives fresh remote content
- user imports a new file
- app updates a local content bundle
- search schema changes between app versions

If your app caches source content locally, a good rule is:

- rebuild when source content changes
- otherwise restore the last saved snapshot

## Working with PDFs

Today, `searchlight` does not parse or render PDFs.

To search PDF content in an app, you need a PDF extraction layer that produces
records with enough metadata for your viewer. A practical page-level record
shape looks like this:

```dart
{
  'id': 'rules-p12',
  'documentId': 'rules',
  'page': 12,
  'title': 'Rules Reference',
  'content': 'Extracted text from page 12...',
}
```

If you want to filter or sort on `documentId` or `page`, declare those fields
in the schema. Only schema-declared fields participate in indexing, filtering,
faceting, grouping, and sorting.

For example:

```dart
final pdfSchema = Schema({
  'documentId': const TypedField(SchemaType.enumType),
  'page': const TypedField(SchemaType.number),
  'title': const TypedField(SchemaType.string),
  'content': const TypedField(SchemaType.string),
});
```

Then:

1. extract text and page metadata from the PDF
2. insert page records into Searchlight
3. search against `title` and `content`
4. map the selected hit back to the PDF viewer

If you also need exact text rectangles for in-view highlights, the extraction
layer must preserve that PDF positioning data. That work belongs in PDF-
specific app code or in a future companion package above the core library.

## Validation Workflow in This Repository

This repository includes a validation setup you can study or reuse:

- `example/tool/build_validation_assets.dart`: simple corpus extraction and
  snapshot generation
- `example/`: Flutter validation app that loads either raw records or a saved
  snapshot
- `test/integration/search_fixture_integration_test.dart`: realistic corpus
  assertions

Use those as implementation references when wiring Searchlight into your app.
