# Searchlight

[![Pub Version](https://img.shields.io/pub/v/searchlight)](https://pub.dev/packages/searchlight)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)
[![Repository](https://img.shields.io/badge/repository-kingdomseed%2Fsearchlight-24292f)](https://github.com/kingdomseed/searchlight)

Searchlight is an independent pure Dart reimplementation of Orama's in-memory
search and indexing model for Dart and Flutter apps. It gives you
schema-based indexing, scoring, filtering, facets, persistence, and
standalone highlighting without requiring a server.

Searchlight is especially useful when your app already has content available
locally or can download and cache it, and you want fast in-app search over
that data.

## Status

`searchlight` is the core package: indexing, querying, persistence,
highlighting, and a limited create-time extension surface.

Current extension support includes:

- ordered `SearchlightPlugin` registration
- lifecycle hooks via `SearchlightHooks`
- `index` and `sorter` component replacement via `SearchlightComponents`
- restore-time validation that a persisted snapshot is loaded with a
  compatible plugin/component graph

It does not currently include:

- PDF parsing or rendering
- Flutter UI widgets

The extension API is intentionally narrower than Orama today. Searchlight does
not yet expose Orama's full component graph, async plugin initialization, or
every declared hook path.

## Platform Support

`searchlight` is a pure Dart package. It works anywhere Dart runs, including
Flutter mobile, desktop, and web. The core package does not include
platform-channel code or platform-specific subpackages.

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
- A limited create-time extension API for lifecycle hooks and index/sorter
  replacement

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

If your app needs reusable extraction, keep that conversion layer in your app
or in a companion package. For small integrations, simple record-conversion
functions are often enough.

## What Searchlight Can Index

Searchlight indexes schema-shaped records, not raw files.

That means the core package directly supports:

- `Map<String, Object?>` records inserted with `insert()`
- persisted snapshots restored with `restore()` or `fromJson()`
- any source format that your app converts into those records first

The core package does not currently include built-in parsers for:

- Markdown files
- HTML files
- PDF files
- CSV, XML, or other file formats

If you insert raw HTML or Markdown into a `string` field yourself, Searchlight
will tokenize that raw text. It will not strip tags, ignore attributes, or
understand Markdown structure automatically. In practice, that means markup
tokens and link-destination fragments can become searchable unless you clean or
extract the text first.

In this repository specifically:

- the core package accepts records and snapshots only
- the validation example's live folder mode currently reads `.md` files only
- the validation assets are JSON corpus and JSON snapshot files

## Choose the Right Runtime Pattern

There are two common integration modes:

1. Build in memory from records
   - best for tests, small corpora, and validation
   - create `Searchlight`, insert records, search immediately
2. Restore from a persisted snapshot
   - best for production apps with a non-trivial corpus
   - build once, persist, then restore on future launches

The package supports both paths directly.

Document writes are available through:

- `insert()` / `insertMultiple()`
- `update()` / `updateMultiple()`
- `upsert()` / `upsertMultiple()`
- `patch()`
- `remove()` / `removeMultiple()`

## Extensions

Searchlight exposes a Dart-native extension surface inspired by Orama's
create-time plugin model:

- `SearchlightPlugin` is the registration unit
- `SearchlightHooks` provides lifecycle callbacks
- `SearchlightComponents` can replace the active `index` or `sorter`

This is enough to prove real component replacement. The test suite includes
plugin-driven index swaps that force PT15 and QPS behavior through the plugin
path rather than through the top-level `algorithm` flag alone.

Current limits to know before depending on extensions heavily:

- hooks are sync-only in core operations; async hooks fail fast
- component replacement is currently limited to `index` and `sorter`
- conflicting `index` / `sorter` registrations now fail fast instead of using
  last-writer-wins resolution
- `beforeInsertMultiple`, `beforeLoad`, and `afterLoad` remain reserved but
  non-dispatched because the current Orama runtime does not visibly dispatch
  them either

Deeper parity notes live in
`docs/research/searchlight-extension-status.md`.

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

## Choosing a Search Algorithm

Searchlight supports three ranking algorithms:

- `SearchAlgorithm.bm25`: default general-purpose relevance ranking
- `SearchAlgorithm.qps`: proximity-aware scoring optimized for faster search
  and smaller indexes
- `SearchAlgorithm.pt15`: position-aware scoring that can work well when term
  order and early-token placement matter

Choose the algorithm when creating the database:

```dart
final db = Searchlight.create(
  schema: schema,
  algorithm: SearchAlgorithm.qps,
);
```

Or rebuild an existing database with a different algorithm:

```dart
final qpsDb = db.reindex(algorithm: SearchAlgorithm.qps);
```

PT15 has important query limitations:

- `tolerance` is not supported
- `exact` is not supported
- string-field `where` filters are not supported

If you need the broadest query feature support, stay with `bm25`.

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
`inFilter`, `ninFilter`, `filterContainsAll`, `filterContainsAny`,
`geoRadius`, `geoPolygon`, `and`, `or`, and `not`.

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

`FileStorage` is intended for `dart:io` platforms. If you want persisted JSON
instead of CBOR, pass `format: PersistenceFormat.json` to both `persist()` and
`restore()`. On web or in a custom app storage layer, implement your own
`SearchlightStorage` or use `toJson()` and `fromJson()` directly.

Persistence supports reconstructible `Searchlight.create()` tokenizer settings
such as stemming toggles, stop words, duplicate handling, and skip-property
sets. Databases created with an injected `Tokenizer` or custom stemmer callback
must be rebuilt instead of serialized.

If a snapshot was created with plugins or replacement components, restore it
with the same plugin order and compatible component IDs. Searchlight stores
extension compatibility metadata in the snapshot and rejects mismatched restore
graphs instead of silently loading into the wrong runtime shape.

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

- `example/` shows a Flutter validation app for fixture, snapshot, and
  desktop-folder indexing flows
- `example/tool/build_validation_assets.dart` shows a simple
  extraction-to-index flow used by the example

For a fuller walkthrough, see [doc/app-integration.md](doc/app-integration.md).

## PDF Support

`searchlight` is the core indexing engine. It does not currently parse PDF
files. To search PDFs in an app today, you need an extraction step that turns
PDF text into searchable records before inserting them into Searchlight.
If you also need viewer integration or PDF-specific metadata handling, keep
that in your app or in a companion package above the core library.

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

Searchlight is an independent pure Dart reimplementation of Orama.
It is not affiliated with or endorsed by the Orama project.
See [NOTICE](NOTICE) for attribution.
