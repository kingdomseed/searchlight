# Searchlight — Design Specification

A pure Dart full-text search engine inspired by [Orama](https://github.com/oramasearch/orama), providing full-text search, filtering, facets, geosearch, highlighting, and index persistence for Dart and Flutter applications.

**License:** Apache 2.0 with NOTICE file crediting Orama as inspiration.

---

## 1. Package Architecture

Monorepo with three packages:

```
searchlight/
├── packages/
│   ├── searchlight/              # Core search engine (pure Dart)
│   ├── searchlight_flutter/      # Flutter widgets & TextSpan helpers
│   └── searchlight_pdf/          # PDF text extraction adapter
```

### searchlight (pure Dart)

Zero Flutter dependency. Targets `dart:core` plus minimal pub.dev dependencies.

**Capabilities:**
- Schema definition and validation
- Document indexing (insert, update, remove, batch operations)
- Full-text search with BM25, QPS, and PT15 scoring algorithms
- Tokenization pipeline with Unicode NFC normalization and stemming (29 languages)
- Filters, facets, sorting, grouping, geosearch
- Typo tolerance via Levenshtein-based fuzzy matching
- Standalone highlight engine returning match positions and trimmed excerpts
- Index persistence via JSON (debugging) and CBOR (production)
- Pluggable storage interface
- Document adapter interface for extensibility
- Isolate-safe design for large index operations

### searchlight_flutter

Depends on `searchlight` + Flutter SDK.

**Capabilities:**
- `HighlightedText` widget — renders search results with styled match spans
- `TextSpan` builder extensions from highlight positions
- Convenience widgets for common search UI patterns (future)

### searchlight_pdf

Depends on `searchlight` + a PDF parsing library.

**Capabilities:**
- Implements `DocumentAdapter<Uint8List>` interface
- Extracts text from PDF bytes, splits into indexable chunks by page
- Preserves page number and metadata for result attribution
- Configurable: split by page, max content length, metadata extraction

---

## 2. Core API

### Database Lifecycle

```dart
// Create
final db = Searchlight.create(
  schema: {
    'title': SchemaType.string,
    'body': SchemaType.string,
    'price': SchemaType.number,
    'active': SchemaType.boolean,
    'category': SchemaType.enumType,
    'tags': SchemaType.stringArray,
    'location': SchemaType.geopoint,
    'meta': {
      'rating': SchemaType.number,
      'author': SchemaType.string,
    },
  },
  algorithm: SearchAlgorithm.bm25,  // default; also .qps, .pt15
  language: 'en',                    // stemmer/tokenizer language
);
```

### Document Operations

```dart
final id = db.insert({'title': 'Wireless Headphones', 'price': 99.99, ...});
db.insertMultiple(documents, batchSize: 500);
db.update(id, {'price': 79.99});
db.remove(id);
```

### Search

```dart
final results = db.search(
  term: 'wireless headphone',
  properties: ['title', 'body'],
  where: {
    'price': between(50, 150),
    'active': eq(true),
    'category': inList(['electronics', 'audio']),
    'location': geoRadius(lat: 40.71, lon: -74.00, radius: 5000),
  },
  sortBy: SortBy('price', order: SortOrder.asc),
  facets: {
    'category': FacetConfig(limit: 10),
    'tags': FacetConfig(limit: 5),
  },
  groupBy: GroupBy('category', limit: 3),
  tolerance: 1,
  boost: {'title': 2.0},
  offset: 0,
  limit: 10,
);
```

### Search Results Structure

```dart
results.hits     // → List<SearchHit> (document + score + id)
results.count    // → total match count
results.elapsed  // → Duration
results.facets   // → Map<String, List<FacetValue>>
results.groups   // → Map<String, List<SearchHit>>?
```

### Filter DSL

Composable, type-safe helper functions:
- `eq(value)` — exact match
- `between(min, max)` — numeric range (inclusive)
- `gt(value)`, `lt(value)`, `gte(value)`, `lte(value)` — numeric comparison
- `inList(values)` — match any of the provided values
- `geoRadius(lat:, lon:, radius:)` — within radius in meters

---

## 3. Schema Types

All 10 types supported:

| SchemaType | Dart Type | Index Type | Capabilities |
|------------|-----------|------------|-------------|
| `string` | `String` | Inverted index (HashMap + radix tree) | Full-text search, prefix matching, boosting |
| `number` | `num` | SplayTreeMap | Range filtering, sorting |
| `boolean` | `bool` | Bitset | Boolean filtering |
| `enumType` | `String` | Facet index | Faceted filtering, aggregation |
| `geopoint` | `GeoPoint` (lat/lon) | Geohash + R-tree | Radius filtering, distance sorting |
| `stringArray` | `List<String>` | Inverted index | Multi-value full-text search |
| `numberArray` | `List<num>` | SplayTreeMap | Multi-value range filtering |
| `booleanArray` | `List<bool>` | Bitset | Multi-value boolean filtering |
| `enumArray` | `List<String>` | Facet index | Multi-value faceted filtering |
| Nested objects | `Map<String, dynamic>` | Per-field indexes | Dot-path access (`meta.rating`) |

---

## 4. Search Algorithms

Chosen at database creation time. Each stores different metadata in the index.

### BM25 (Default)

- Scores based on term frequency, inverse document frequency, and document length normalization
- Tunable parameters: `k1` (term frequency saturation, default 1.2), `b` (length normalization, default 0.75)
- Best for general-purpose search across varied document lengths

### QPS (Quantum Proximity Scoring)

- Scores based on proximity of search terms within documents
- Higher scores when terms appear close together
- Smaller index footprint than BM25 (no TF/IDF metadata)
- Best for documentation, e-commerce, content search

### PT15 (Positional Token 15)

- Scores based on token position — earlier positions score higher
- 15 fixed position buckets with scaling for longer documents
- Best for structured text where position matters (titles, headings)

### Implementation

Abstract `Scorer` interface:

```dart
abstract class Scorer {
  void indexDocument(DocId id, String field, List<String> tokens);
  double score(String term, DocId id, String field);
  void removeDocument(DocId id);
  Map<String, dynamic> toJson();
  factory Scorer.fromJson(Map<String, dynamic> json);
}
```

BM25, QPS, and PT15 each implement this interface.

---

## 5. Internal Architecture

### File Structure

```
lib/
└── src/
    ├── core/
    │   ├── database.dart          # Searchlight class
    │   ├── schema.dart            # SchemaType enum, validation
    │   ├── document.dart          # Document storage, DocId extension type
    │   └── types.dart             # SearchResult, SearchHit, FacetValue, GeoPoint
    │
    ├── indexing/
    │   ├── index.dart             # InvertedIndex — HashMap<String, PostingList>
    │   ├── posting_list.dart      # Per-term: doc refs, frequencies, positions
    │   ├── radix_tree.dart        # Prefix tree for autocomplete/prefix matching
    │   ├── facet_index.dart       # Enum/category aggregation
    │   ├── numeric_index.dart     # SplayTreeMap for range queries
    │   ├── boolean_index.dart     # Bitset for true/false filtering
    │   ├── geo_index.dart         # Geohash encoding + R-tree for spatial queries
    │   └── sorter.dart            # Field-based sort index
    │
    ├── scoring/
    │   ├── algorithm.dart         # SearchAlgorithm enum + abstract Scorer
    │   ├── bm25.dart              # BM25 (k1=1.2, b=0.75)
    │   ├── qps.dart               # Quantum Proximity Scoring
    │   └── pt15.dart              # Positional Token 15
    │
    ├── text/
    │   ├── pipeline.dart          # Composable token pipeline
    │   ├── tokenizer.dart         # Unicode-aware (\p{L}\p{Nd})
    │   ├── normalizer.dart        # NFC via unorm_dart
    │   ├── stemmer.dart           # Language-aware via snowball_stemmer
    │   ├── stop_words.dart        # Per-language stop word sets
    │   └── fuzzy.dart             # Levenshtein-based typo tolerance
    │
    ├── search/
    │   ├── engine.dart            # Query execution orchestrator
    │   ├── filters.dart           # eq(), between(), inList(), geoRadius()
    │   ├── facets.dart            # Facet aggregation and counting
    │   ├── grouping.dart          # Group results by field
    │   └── boost.dart             # Field-level boosting
    │
    ├── highlight/
    │   ├── highlighter.dart       # Standalone Highlighter class
    │   └── positions.dart         # HighlightMatch, HighlightPosition, trim
    │
    ├── persistence/
    │   ├── serializer.dart        # Abstract serialization interface
    │   ├── json_serializer.dart   # JSON format
    │   └── cbor_serializer.dart   # CBOR format
    │
    └── isolate/
        ├── worker.dart            # Isolate-based index building
        └── transfer.dart          # TransferableTypedData helpers
```

### Key Data Structures

- **Inverted index:** `HashMap<String, PostingList>` — O(1) term lookup
- **PostingList:** per-term document references, term frequencies, field positions
- **Radix tree:** compressed prefix trie for autocomplete and prefix matching
- **SplayTreeMap:** sorted numeric index for range queries
- **R-tree:** spatial index for geosearch bounding-box queries (via `r_tree` package)
- **Geohash:** encode lat/lon as string prefixes for proximity bucketing
- **Facet index:** HashMap<String, int> counting per category value
- **DocId:** Dart extension type wrapping `int` for zero-cost type safety

### Tokenization Pipeline

Separate pipelines for index-time and search-time:

**Index-time:** NFC normalize → lowercase → split on `[^\p{L}\p{Nd}]+` → remove stop words → stem

**Search-time:** NFC normalize → lowercase → split on `[^\p{L}\p{Nd}]+` → stem (no stop word removal for phrase matching)

---

## 6. Highlight API

### Core (searchlight)

```dart
final highlighter = Highlighter(
  caseSensitive: false,
  wholeWords: false,
);

final result = highlighter.highlight(
  'The quick brown fox jumps over the lazy dog',
  'brown fox jump',
);

result.positions  // → [HighlightPosition(start: 10, end: 15), ...]
result.tokens     // → ['brown', 'fox', 'jumps']
result.trim(40)   // → "...quick brown fox jumps over..."
```

The highlighter is standalone — no dependency on the search engine. Takes `(text, query)`, returns positions.

### Flutter (searchlight_flutter)

```dart
// Widget
HighlightedText(
  text: document.content,
  positions: result.positions,
  style: TextStyle(color: Colors.black87),
  matchStyle: TextStyle(
    backgroundColor: Colors.amber.shade200,
    fontWeight: FontWeight.bold,
  ),
  maxLines: 2,
  overflow: TextOverflow.ellipsis,
)

// Lower-level
final spans = result.positions.toTextSpans(
  text: document.content,
  matchStyle: TextStyle(backgroundColor: Colors.amber.shade200),
);
```

---

## 7. Persistence & Serialization

### Formats

- **CBOR** (default binary) — compact, fast, production use via `cbor` package
- **JSON** — human-readable, debugging/inspection, built-in `dart:convert`

### API

```dart
// Binary (CBOR)
final Uint8List bytes = db.serialize();
final restored = Searchlight.deserialize(bytes);

// JSON
final Map<String, dynamic> json = db.toJson();
final restored2 = Searchlight.fromJson(json);
```

### Pluggable Storage

```dart
abstract class SearchlightStorage {
  Future<void> save(Uint8List data);
  Future<Uint8List?> load();
}

// Built-in: file-based
final db = Searchlight.create(
  schema: schema,
  storage: FileStorage(path: '/path/to/index.cbor'),
);

await db.persist();  // manual save

final db = await Searchlight.restore(
  storage: FileStorage(path: '/path/to/index.cbor'),
);
```

Optional `autoPersist: true` debounces writes after mutations.

### What Gets Serialized

- Schema, all documents, all indexes (inverted, facet, numeric, boolean, geo)
- Scoring metadata, tokenizer config, algorithm choice

### What Does Not Get Serialized

- Transient query state, isolate workers, storage config

---

## 8. Document Adapters

```dart
abstract class DocumentAdapter<T> {
  List<Map<String, dynamic>> toDocuments(T source);
}
```

### searchlight_pdf

```dart
class PdfAdapter implements DocumentAdapter<Uint8List> {
  final PdfExtractionConfig config;
  const PdfAdapter({this.config = const PdfExtractionConfig()});

  @override
  List<Map<String, dynamic>> toDocuments(Uint8List pdfBytes) { ... }
}

class PdfExtractionConfig {
  final bool splitByPage;
  final int? maxContentLength;
  final bool extractMetadata;
  const PdfExtractionConfig({
    this.splitByPage = true,
    this.maxContentLength,
    this.extractMetadata = true,
  });
}
```

Future adapter packages (not in scope for v1):
- `searchlight_html`, `searchlight_epub`, `searchlight_csv`, `searchlight_markdown`

---

## 9. Dependencies

### Core Package (searchlight)

| Purpose | Package | Version | Notes |
|---------|---------|---------|-------|
| Unicode normalization | `unorm_dart` | ^0.3.2 | NFC normalization before indexing |
| Stemming (29 langs) | `snowball_stemmer` | ^0.1.0 | Snowball algorithms, stable despite age |
| Spatial indexing | `r_tree` | ^3.0.2 | Workiva-maintained R-tree |
| Geodesy | `geobase` | ^1.5.0 | Haversine + Vincenty distance |
| Binary serialization | `cbor` | ^6.5.1 | RFC8949 CBOR format |

### Flutter Package (searchlight_flutter)

| Purpose | Package |
|---------|---------|
| Core search | `searchlight` |
| Flutter SDK | `flutter` |

### PDF Package (searchlight_pdf)

| Purpose | Package |
|---------|---------|
| Core search | `searchlight` |
| PDF parsing | TBD (evaluate `syncfusion_flutter_pdf`, `pdf_text`, or similar) |

### Built In-House

- Inverted index, BM25/QPS/PT15 scoring, tokenizer pipeline
- Radix tree, typo tolerance (Levenshtein), filter engine
- Facet aggregation, highlight engine
- Stop word lists per language, geohash encoding

---

## 10. Code Quality

- **Lint base:** `very_good_analysis` (~100 strict rules)
- **CI gate:** `dart analyze` with zero warnings
- **Documentation:** `public_member_api_docs` enforced on all public API
- **Future:** `dart_code_metrics` for complexity/maintainability metrics

---

## 11. Implementation Strategy

### TDD Vertical Slices

Each slice delivers a working, testable feature via strict red-green-refactor cycles. No horizontal slicing (all tests first, then all implementation).

| # | Slice | What's Testable After |
|---|-------|----------------------|
| 1 | Schema + empty database | Create DB, validate/reject schemas |
| 2 | Insert + retrieve string docs | CRUD lifecycle, DocId |
| 3 | Basic full-text search (BM25) | Insert docs, search by term, ranked results |
| 4 | Tokenizer pipeline | NFC → lowercase → split → stem → verify tokens |
| 5 | Typo tolerance | Fuzzy matching with misspellings |
| 6 | Number fields + filtering | `between()`, `gt()`, `lt()` |
| 7 | Boolean fields + filtering | `eq(true/false)` |
| 8 | Enum fields + facets | Facet counts, enum filtering |
| 9 | Array fields | `string[]`, `number[]`, `boolean[]`, `enum[]` |
| 10 | Nested objects | Dot-path indexing (`meta.rating`) |
| 11 | Sorting | Sort by numeric/string fields |
| 12 | Grouping | Group results by field |
| 13 | Field boosting | Boosted fields rank higher |
| 14 | Geopoint + geosearch | Radius filtering, distance |
| 15 | Highlighter | Positions, trim, case sensitivity, whole words |
| 16 | QPS scoring | Proximity-based ranking |
| 17 | PT15 scoring | Position-based ranking |
| 18 | JSON persistence | Serialize → deserialize round-trip |
| 19 | CBOR persistence | Binary round-trip |
| 20 | Storage interface | FileStorage save/load lifecycle |
| 21 | Multi-language | Non-English stemming + stop words |
| 22 | Isolate support | Background index building |

### Per-Slice Cycle

1. **Red** — write one test that fails
2. **Green** — minimal implementation to pass
3. **Refactor** — clean up while green
4. **Commit** — each cycle is a committable unit
5. Repeat within the slice

---

## 12. Performance Considerations

- `Uint8List` / typed arrays for large numeric data (posting lists, term frequency arrays)
- Extension types (Dart 3.3+) for zero-cost `DocId`, `TermId` wrappers
- `HashMap` (default `Map`) for inverted index — O(1) lookups dominate search workload
- `SplayTreeMap` for sorted numeric indexes supporting range queries
- Isolate support for index building on large datasets (>10K documents)
- `TransferableTypedData` for shipping binary indexes between isolates without copying
- Avoid linear scan — every query path uses indexed structures
- CBOR for production persistence (smaller, faster than JSON)

---

## 13. Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| `snowball_stemmer` is 4 years old | Snowball algorithms are stable; fork if issues arise |
| No existing Dart BM25 to reuse | Well-documented algorithm; reference lunr's IDF formula and Orama's implementation |
| Large index isolate transfer | Design for `TransferableTypedData`; benchmark early in slice 22 |
| QPS/PT15 are Orama-specific algorithms | Study Orama source and documentation; implement from algorithm descriptions |
| PDF parsing library choice | Evaluate options during searchlight_pdf development; keep adapter interface stable |

---

## Attribution

This project is inspired by [Orama](https://github.com/oramasearch/orama) (Apache 2.0, Copyright Orama contributors). Searchlight is an independent pure Dart reimplementation — not a direct port. A NOTICE file will be included per Apache 2.0 requirements.
