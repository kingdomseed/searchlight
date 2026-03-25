# Searchlight

A full-text search engine for Dart with BM25/QPS/PT15 scoring, filters, facets, geosearch, and highlighting.

Inspired by [Orama](https://github.com/oramasearch/orama).

## Features

- Full-text search with BM25, QPS, and PT15 scoring algorithms
- Schema-based document indexing (9 leaf types + nested objects)
- Typo tolerance via Levenshtein fuzzy matching
- Filters (eq, gt, lt, between, in, geoRadius, and/or/not)
- Facets, groups, and field-based sorting
- Text highlighting with positions and trim
- JSON and CBOR persistence with format versioning
- 30-language tokenizer with stemming and stop words

## Installation

```yaml
dependencies:
  searchlight: ^0.1.0
```

## Usage

Create a database with a schema, insert documents, and search:

```dart
import 'package:searchlight/searchlight.dart';

final db = Searchlight.create(
  schema: Schema({
    'title': const TypedField(SchemaType.string),
    'description': const TypedField(SchemaType.string),
    'price': const TypedField(SchemaType.number),
    'category': const TypedField(SchemaType.enumType),
    'meta': const NestedField({
      'rating': TypedField(SchemaType.number),
    }),
  }),
);

db.insert({
  'title': 'Noise cancelling headphones',
  'description': 'Comfortable over-ear headphones with active noise cancelling',
  'price': 99.99,
  'category': 'electronics',
  'meta': {'rating': 4.5},
});

db.insert({
  'title': 'Wireless earbuds',
  'description': 'Compact earbuds with noise isolation',
  'price': 49.99,
  'category': 'electronics',
  'meta': {'rating': 4.2},
});

final results = db.search(term: 'noise cancelling');
// results.count == 2
// results.hits[0].document.getString('title') == 'Noise cancelling headphones'
// results.hits[0].score > results.hits[1].score
```

## Supported Types

| SchemaType      | Dart Type       | Description                          |
|-----------------|-----------------|--------------------------------------|
| `string`        | `String`        | Full-text indexed, searchable        |
| `number`        | `num`           | Range filtering, sorting             |
| `boolean`       | `bool`          | Boolean filtering                    |
| `enumType`      | `String`/`num`  | Faceted filtering, aggregation       |
| `geopoint`      | `GeoPoint`      | Radius and polygon geosearch         |
| `stringArray`   | `List<String>`  | Multi-value full-text search         |
| `numberArray`   | `List<num>`     | Multi-value range filtering          |
| `booleanArray`  | `List<bool>`    | Multi-value boolean filtering        |
| `enumArray`     | `List<String>`  | Multi-value faceted filtering        |
| Nested objects  | `NestedField`   | Dot-path access (e.g. `meta.rating`) |

## Filters

```dart
final results = db.search(
  term: 'headphones',
  where: {
    'price': between(20, 100),
    'category': eq('electronics'),
  },
);
```

Supported filter operations: `eq`, `gt`, `gte`, `lt`, `lte`, `between`, `inFilter`, `ninFilter`, `geoRadius`, `geoPolygon`. Combine with `and`, `or`, `not`.

## Facets

```dart
final results = db.search(
  term: 'headphones',
  facets: {'category': const FacetConfig()},
);

// results.facets['category'] contains value counts
```

## Scoring Algorithms

Choose the scoring algorithm at database creation:

```dart
// BM25 (default) -- term frequency + inverse document frequency
final db = Searchlight.create(schema: schema);

// QPS -- scores based on proximity of search terms within documents
final db = Searchlight.create(schema: schema, algorithm: SearchAlgorithm.qps);

// PT15 -- scores based on token position (earlier = higher)
final db = Searchlight.create(schema: schema, algorithm: SearchAlgorithm.pt15);
```

Switch algorithms on an existing database with `reindex`:

```dart
final qpsDb = db.reindex(algorithm: SearchAlgorithm.qps);
```

## Highlighting

```dart
final highlighter = Highlighter();
const text = 'Comfortable over-ear headphones with active noise cancelling';
final result = highlighter.highlight(text, 'noise cancelling');

// result.positions -- [{start: 44, end: 49}, {start: 50, end: 60}]
// result.trim(text, 30) -- "...with active noise cancelling"
```

## Persistence

```dart
// JSON (human-readable)
final json = db.toJson();
final restored = Searchlight.fromJson(json);

// CBOR (compact binary)
final bytes = db.serialize();
final restored = Searchlight.deserialize(bytes);

// File-based storage
final storage = FileStorage(path: 'index.cbor');
await db.persist(storage: storage);
final restored = await Searchlight.restore(storage: storage);
```

## Document IDs

Documents can have user-supplied string IDs or get auto-generated ones:

```dart
db.insert({'id': 'my-custom-id', 'title': 'My Document'});
// Returns 'my-custom-id'

db.insert({'title': 'Auto ID Document'});
// Returns an auto-generated string ID
```

## License

Apache License 2.0. See [LICENSE](LICENSE) for details.

This project is inspired by [Orama](https://github.com/oramasearch/orama) (Apache 2.0, Copyright Orama contributors). Searchlight is an independent pure Dart reimplementation. See [NOTICE](NOTICE) for attribution.
