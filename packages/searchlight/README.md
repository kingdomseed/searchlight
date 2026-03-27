# Searchlight

[![Pub Version](https://img.shields.io/pub/v/searchlight)](https://pub.dev/packages/searchlight)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)
[![Repository](https://img.shields.io/badge/repository-kingdomseed%2Fsearchlight-24292f)](https://github.com/kingdomseed/searchlight)

Searchlight is a pure Dart reimplementation of Orama-style in-memory search
and indexing for Dart and Flutter apps. It gives you schema-based indexing,
scoring, filtering, facets, persistence, and standalone highlighting without
requiring a server.

Searchlight is especially useful when your app already has content available
locally or can download and cache it, and you want fast in-app search over
that data.

Inspired by [Orama](https://github.com/oramasearch/orama).

## Start Here

- Read [doc/app-integration.md](doc/app-integration.md) for the recommended
  app architecture.
- Read [doc/validation-workflow.md](doc/validation-workflow.md) for the local
  validation loop.
- Open [example/README.md](example/README.md) for the Flutter validation app.

## What It Provides

- Full-text indexing for structured documents
- BM25, QPS, and PT15 ranking algorithms
- Typed filters, sorting, grouping, and facets
- JSON and CBOR persistence for cached indexes
- Standalone highlighter utilities for excerpts and marked ranges
- Standalone tokenizer utilities with language support, stemming, and optional
  stop words

`Searchlight.create()` also exposes tokenizer-related configuration for the
built-in database tokenizer, including `stemming`, `stemmer`, `stopWords`,
`useDefaultStopWords`, `allowDuplicates`, `tokenizeSkipProperties`, and
`stemmerSkipProperties`.

By default, stemming is off, matching Orama's default tokenizer behavior.
Built-in tokenizer settings round-trip through persistence. Injected
`Tokenizer` instances and custom stemmer callbacks do not serialize.

## Installation

```bash
dart pub add searchlight
```

## Quick Start

```dart
import 'package:searchlight/searchlight.dart';

Future<void> main() async {
  final db = Searchlight.create(
    schema: Schema({
      'url': const TypedField(SchemaType.string),
      'title': const TypedField(SchemaType.string),
      'content': const TypedField(SchemaType.string),
      'type': const TypedField(SchemaType.enumType),
    }),
  );

  db.insert({
    'id': 'ember-lance',
    'url': '/spells/ember-lance',
    'title': 'Ember Lance',
    'content': 'A focused lance of heat that ignites dry brush.',
    'type': 'spell',
  });

  db.insert({
    'id': 'iron-boar',
    'url': '/creatures/iron-boar',
    'title': 'Iron Boar',
    'content': 'A plated beast known for explosive charges.',
    'type': 'monster',
  });

  final results = db.search(
    term: 'ember',
    properties: const ['title', 'content'],
  );

  for (final hit in results.hits) {
    print('${hit.score.toStringAsFixed(2)} ${hit.document.getString('title')}');
  }

  await db.dispose();
}
```

## Core Workflow

Searchlight does not extract your source data for you. Your app or tooling is
responsible for turning content into records, and Searchlight handles the
indexing and querying.

The common integration flow is:

1. Read or receive source content.
2. Convert it into structured records.
3. Insert those records into a `Searchlight` database.
4. Persist the built index if you want fast startup later.
5. Restore the persisted index and query it at runtime.

This applies equally to:

- App-bundled JSON or markdown content
- Remote content downloaded and cached on device
- User-imported files such as PDFs after text extraction

If you want a reusable extraction layer, implement `DocumentAdapter<T>` for
your source type. If your extraction logic is small and app-specific, simple
record-conversion functions are often enough.

## Choose the Right Runtime Pattern

There are two common integration modes:

1. Build in memory from records
   - best for tests, small corpora, and validation
   - create `Searchlight`, insert records, search immediately
2. Restore from a persisted snapshot
   - best for production apps with a non-trivial corpus
   - build once, persist, then restore on future launches

The package supports both paths directly.

## Defining a Schema

Every database is created from a schema. String fields are searchable by full
text. Other field types support filtering, grouping, sorting, or geosearch.

| SchemaType | Dart type | Primary use |
| --- | --- | --- |
| `string` | `String` | Full-text search |
| `number` | `num` | Range filters and sorting |
| `boolean` | `bool` | Boolean filters |
| `enumType` | `String` or `num` | Facets and exact-match filters |
| `geopoint` | `GeoPoint` | Geo radius and polygon filters |
| `stringArray` | `List<String>` | Full-text search over multiple values |
| `numberArray` | `List<num>` | Numeric filtering |
| `booleanArray` | `List<bool>` | Boolean filtering |
| `enumArray` | `List<String>` or `List<num>` | Facets and filters |
| `NestedField` | nested object | Dot-path access such as `meta.rating` |

## Searching

Searchlight supports full-text search with optional filters and result shaping.

```dart
final result = db.search(
  term: 'ember lance',
  properties: const ['title', 'content'],
  tolerance: 1,
  limit: 10,
  offset: 0,
  where: {
    'type': eq('spell'),
  },
  sortBy: const SortBy(field: 'title', order: SortOrder.asc),
);
```

Useful search options:

- `properties`: limit search to specific string fields
- `where`: apply typed filters
- `tolerance`: allow fuzzy term matches
- `exact`: require whole-word matches after scoring
- `limit` and `offset`: paginate
- `sortBy`: sort on sortable fields
- `facets`: collect counts for enum and numeric fields
- `groupBy`: group matching hits by one or more fields

## Filtering, Facets, and Grouping

```dart
final result = db.search(
  term: 'boar',
  where: {
    'type': eq('monster'),
  },
  facets: {
    'type': const FacetConfig(),
  },
  groupBy: const GroupBy(field: 'type', limit: 5),
);
```

Supported filters include `eq`, `gt`, `gte`, `lt`, `lte`, `between`,
`inFilter`, `ninFilter`, `geoRadius`, `geoPolygon`, `and`, `or`, and `not`.

## Persistence

If you have a non-trivial corpus, build the index once and persist it.
Restoring a saved index is usually the right runtime path for production apps.

```dart
Future<void> example(Searchlight db) async {
  final storage = FileStorage(path: 'search-index.cbor');

  await db.persist(storage: storage);

  final restored = await Searchlight.restore(storage: storage);
  final result = restored.search(term: 'ember');
  await restored.dispose();
}
```

`FileStorage` is intended for `dart:io` platforms. On web or in a custom app
storage layer, use `toJson()` and `fromJson()` or implement your own
`SearchlightStorage`.

Persistence supports reconstructible `Searchlight.create()` tokenizer settings
such as stemming toggles, stop words, duplicate handling, and skip-property
sets. Databases created with an injected `Tokenizer` or custom stemmer callback
must be rebuilt instead of serialized.

You can also work directly with JSON-compatible maps:

```dart
void example(Searchlight db) {
  final json = db.toJson();
  final restored = Searchlight.fromJson(json);
  restored.dispose();
}
```

## Highlighting and Excerpts

The `Highlighter` is a standalone utility. It does not change how documents are
indexed. Use it after search to build excerpts or render marked matches.

```dart
String buildExcerpt(SearchHit hit) {
  final highlighter = Highlighter();
  final text = hit.document.getString('content');
  final highlight = highlighter.highlight(text, 'ember');
  return highlight.trim(text, 160);
}
```

This is a good fit for:

- Search result snippets
- Inline `<mark>` or `TextSpan` rendering
- Page-level excerpt generation in Flutter UI

## App Integration Pattern

For most apps, you will want a small indexing layer that sits above
Searchlight.

Example pattern:

1. Define the record shape your app will search.
2. Convert your content into that shape.
3. Build or restore the index in a repository/service.
4. Query from your UI layer.
5. Use `Highlighter` to render excerpts.

The package includes a practical reference implementation:

- `example/` shows a Flutter web validation app
- `example/tool/build_validation_assets.dart` shows a simple
  extraction-to-index flow used by the example

For a fuller walkthrough, see [doc/app-integration.md](doc/app-integration.md).

## PDF Support

`searchlight` is the core indexing engine. It does not currently parse PDF
files. To search PDFs in an app today, you need an extraction step that turns
PDF text into searchable records before inserting them into Searchlight.

Planned package boundaries:

- `searchlight`: core indexing, querying, persistence, highlighting
- `searchlight_flutter`: Flutter UI helpers and widgets
- `searchlight_pdf`: PDF extraction and PDF-specific indexing helpers

## Validation Example

The package includes a validation workflow with:

- Public-safe fixture data under `test/fixtures/`
- An example-owned local-only `.local/` corpus flow for private validation
- A Flutter example app that can load either raw records or a persisted
  snapshot

See:

- [example/README.md](example/README.md)
- [test/fixtures/README.md](test/fixtures/README.md)
- [doc/README.md](doc/README.md)
- [doc/validation-workflow.md](doc/validation-workflow.md)

## License

Apache License 2.0. See [LICENSE](LICENSE).

Searchlight is an independent pure Dart implementation inspired by Orama.
See [NOTICE](NOTICE) for attribution.
