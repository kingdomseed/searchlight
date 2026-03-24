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
- Schema definition and validation via type-safe `SchemaField` hierarchy
- Document indexing (insert, update, replace, remove, batch operations with error reporting)
- Full-text search with BM25, QPS, and PT15 scoring algorithms
- Tokenization pipeline with Unicode NFC normalization and stemming (29 languages)
- Filters (via sealed `Filter` type), facets, sorting, grouping, geosearch
- Typo tolerance via Levenshtein-based fuzzy matching
- Configurable search mode (match all terms, match any term, prefix)
- Standalone highlight engine with optional pipeline integration
- Index persistence via JSON (debugging) and CBOR (production) with format versioning
- Pluggable storage interface
- Document adapter interface for extensibility
- Isolate-safe design for large index operations
- Sealed exception hierarchy for all error conditions

### searchlight_flutter

Depends on `searchlight` + Flutter SDK.

**Capabilities:**
- `HighlightedText` widget — renders search results with styled match spans
- `TextSpan` builder extensions from highlight positions
- Convenience widgets for common search UI patterns (future)

### searchlight_pdf

Depends on `searchlight` + a pure Dart PDF parsing library (e.g., `pdf` package).

**Capabilities:**
- Implements `DocumentAdapter<Uint8List>` interface
- Extracts text from PDF bytes, splits into indexable chunks by page
- Preserves page number and metadata for result attribution
- Configurable: split by page, max content length, metadata extraction

**Note:** PDF dependency must be pure Dart (no Flutter SDK dependency) to keep this package usable outside Flutter.

---

## 2. Type System

### Schema Definition

Schemas are defined using a type-safe `SchemaField` sealed hierarchy — not raw maps:

```dart
sealed class SchemaField {}

final class TypedField extends SchemaField {
  final SchemaType type;
  const TypedField(this.type);
}

final class NestedField extends SchemaField {
  final Map<String, SchemaField> children;
  const NestedField(this.children);
}
```

**Usage:**

```dart
final schema = Schema({
  'title': TypedField(SchemaType.string),
  'body': TypedField(SchemaType.string),
  'price': TypedField(SchemaType.number),
  'active': TypedField(SchemaType.boolean),
  'category': TypedField(SchemaType.enumType),
  'tags': TypedField(SchemaType.stringArray),
  'location': TypedField(SchemaType.geopoint),
  'meta': NestedField({
    'rating': TypedField(SchemaType.number),
    'author': TypedField(SchemaType.string),
  }),
});
```

**Convenience:** A `Schema.from()` factory may accept shorthand notation for ergonomics, but the canonical representation is the typed hierarchy.

### Document Type

Documents use a typed wrapper — not raw `Map<String, dynamic>`:

```dart
extension type DocId(int id) implements int {
  bool get isValid => id >= 0;
}

final class Document {
  final Map<String, Object?> _data;
  const Document(this._data);

  /// Typed accessors with runtime validation.
  String getString(String field) => _data[field]! as String;
  num getNumber(String field) => _data[field]! as num;
  bool getBool(String field) => _data[field]! as bool;
  List<String> getStringList(String field) => (_data[field]! as List).cast<String>();
  GeoPoint getGeoPoint(String field) => _data[field]! as GeoPoint;
  Document getNested(String field) => Document(_data[field]! as Map<String, Object?>);

  /// Nullable variants for optional fields.
  String? tryGetString(String field) => _data[field] as String?;
  num? tryGetNumber(String field) => _data[field] as num?;
  // ... etc.

  /// Raw map access (escape hatch).
  Map<String, Object?> toMap() => Map.unmodifiable(_data);

  /// Schema validation on construction.
  factory Document.validated(Map<String, Object?> data, {required Schema schema}) {
    // Validates all fields match schema types, throws DocumentValidationException
  }
}
```

### Core Result Types

```dart
final class SearchResult {
  final List<SearchHit> hits;
  final int count;
  final Duration elapsed;
  final Map<String, List<FacetValue>>? facets;
  final Map<String, List<SearchHit>>? groups;
}

final class SearchHit {
  final DocId id;
  final double score;
  final Document document;
}

final class FacetValue {
  final String value;
  final int count;
}

final class GeoPoint {
  final double lat;
  final double lon;
  const GeoPoint({required this.lat, required this.lon});
}
```

### Filter Type Hierarchy

```dart
sealed class Filter {}
final class EqFilter extends Filter { final Object value; const EqFilter(this.value); }
final class RangeFilter extends Filter { final num? min; final num? max; const RangeFilter({this.min, this.max}); }
final class GtFilter extends Filter { final num value; const GtFilter(this.value); }
final class LtFilter extends Filter { final num value; const LtFilter(this.value); }
final class GteFilter extends Filter { final num value; const GteFilter(this.value); }
final class LteFilter extends Filter { final num value; const LteFilter(this.value); }
final class InListFilter extends Filter { final List<Object> values; const InListFilter(this.values); }
final class GeoRadiusFilter extends Filter {
  final double lat;
  final double lon;
  final double radius; // meters
  const GeoRadiusFilter({required this.lat, required this.lon, required this.radius});
}

// Convenience constructors (top-level functions)
Filter eq(Object value) => EqFilter(value);
Filter between(num min, num max) => RangeFilter(min: min, max: max);
Filter gt(num value) => GtFilter(value);
Filter lt(num value) => LtFilter(value);
Filter gte(num value) => GteFilter(value);
Filter lte(num value) => LteFilter(value);
Filter inList(List<Object> values) => InListFilter(values);
Filter geoRadius({required double lat, required double lon, required double radius}) =>
    GeoRadiusFilter(lat: lat, lon: lon, radius: radius);
```

---

## 3. Core API

### Database Lifecycle

```dart
// Create
final db = Searchlight.create(
  schema: schema,
  algorithm: SearchAlgorithm.bm25,  // default; also .qps, .pt15
  language: 'en',                    // stemmer/tokenizer language
);

// Lifecycle
int get count;                              // total documents indexed
bool get isEmpty;                           // count == 0
Document? getById(DocId id);                // retrieve without searching
void clear();                               // remove all documents, reset indexes
Future<void> dispose();                     // flush pending writes, release resources
```

### Document Operations

```dart
// Insert — validates document against schema, returns assigned ID.
// Throws DocumentValidationException on schema mismatch.
DocId insert(Map<String, Object?> data);

// Batch insert — returns result with success/failure details.
BatchResult insertMultiple(
  List<Map<String, Object?>> documents, {
  int batchSize = 500,
});

final class BatchResult {
  final List<DocId> insertedIds;
  final List<BatchError> errors; // [{index, error}]
  bool get hasErrors;
}

// Replace — full document replacement. Removes old index entries, re-indexes.
// Throws DocumentNotFoundException if ID doesn't exist.
void replace(DocId id, Map<String, Object?> data);

// Patch — merge partial fields into existing document. Re-indexes affected fields.
// Throws DocumentNotFoundException if ID doesn't exist.
void patch(DocId id, Map<String, Object?> fields);

// Remove
void remove(DocId id);
void removeMultiple(List<DocId> ids);
```

### Search

```dart
final results = db.search(
  term: 'wireless headphone',
  properties: ['title', 'body'],       // which fields to search
  mode: SearchMode.matchAll,            // .matchAll (AND), .matchAny (OR), .prefix
  where: {
    'price': between(50, 150),
    'active': eq(true),
    'category': inList(['electronics', 'audio']),
    'location': geoRadius(lat: 40.71, lon: -74.00, radius: 5000),
  },
  sortBy: SortBy(field: 'price', order: SortOrder.asc),
  facets: {
    'category': FacetConfig(limit: 10),
    'tags': FacetConfig(limit: 5),
  },
  groupBy: GroupBy(field: 'category', limit: 3),
  tolerance: 1,                         // typo tolerance (edit distance)
  threshold: 0.0,                       // minimum relevance score (0.0–1.0)
  boost: {'title': 2.0},                // field-level boosting
  offset: 0,
  limit: 10,
);
```

### Search Modes

| Mode | Behavior |
|------|----------|
| `SearchMode.matchAll` | All terms must appear (AND). Default. |
| `SearchMode.matchAny` | Any term can match (OR with ranking). |
| `SearchMode.prefix` | Last term is treated as a prefix (autocomplete). |

### Search Result Structure

All types formally defined as immutable classes (see Section 2).

```dart
results.hits       // → List<SearchHit> with .id, .score, .document
results.count      // → int total match count
results.elapsed    // → Duration
results.facets     // → Map<String, List<FacetValue>>?
results.groups     // → Map<String, List<SearchHit>>?
```

---

## 4. Schema Types

All 10 types supported:

| SchemaType | Dart Type | Index Type | Capabilities |
|------------|-----------|------------|-------------|
| `string` | `String` | Inverted index (HashMap + radix tree) | Full-text search, prefix matching, boosting |
| `number` | `num` | SplayTreeMap | Range filtering, sorting |
| `boolean` | `bool` | Bitset | Boolean filtering |
| `enumType` | `String` | Facet index | Faceted filtering, aggregation |
| `geopoint` | `GeoPoint` | Geohash + R-tree | Radius filtering, distance sorting |
| `stringArray` | `List<String>` | Inverted index | Multi-value full-text search |
| `numberArray` | `List<num>` | SplayTreeMap | Multi-value range filtering |
| `booleanArray` | `List<bool>` | Bitset | Multi-value boolean filtering |
| `enumArray` | `List<String>` | Facet index | Multi-value faceted filtering |
| Nested objects | `NestedField` | Per-field indexes | Dot-path access (`meta.rating`) |

---

## 5. Search Algorithms

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

### Implementation — Sealed Scorer Hierarchy

```dart
sealed class Scorer {
  void indexDocument(DocId id, String field, List<String> tokens);
  double score(String term, DocId id, String field);
  void removeDocument(DocId id);
  Map<String, dynamic> serialize();
}

final class Bm25Scorer extends Scorer {
  final double k1;
  final double b;
  Bm25Scorer({this.k1 = 1.2, this.b = 0.75});
  // ...
}

final class QpsScorer extends Scorer { /* ... */ }
final class Pt15Scorer extends Scorer { /* ... */ }

// Deserialization uses exhaustive switch on discriminator field:
Scorer deserializeScorer(Map<String, dynamic> data) => switch (data['type']) {
  'bm25' => Bm25Scorer.fromMap(data),
  'qps' => QpsScorer.fromMap(data),
  'pt15' => Pt15Scorer.fromMap(data),
  _ => throw SerializationException('Unknown scorer type: ${data['type']}'),
};
```

### Algorithm Migration

Changing algorithm requires re-indexing from raw documents. Since all documents are stored in the serialized format, migration is supported:

```dart
final newDb = db.reindex(algorithm: SearchAlgorithm.qps);
```

This creates a new database, copies all documents, and re-indexes with the new algorithm.

---

## 6. Error Handling

### Exception Hierarchy

```dart
sealed class SearchlightException implements Exception {
  final String message;
  const SearchlightException(this.message);
}

/// Schema definition errors (invalid types, invalid nesting).
final class SchemaValidationException extends SearchlightException {
  const SchemaValidationException(super.message);
}

/// Document does not match schema (wrong field types, missing required fields).
final class DocumentValidationException extends SearchlightException {
  final String? field;
  const DocumentValidationException(super.message, {this.field});
}

/// Document not found for update/patch/remove.
final class DocumentNotFoundException extends SearchlightException {
  final DocId id;
  const DocumentNotFoundException(this.id) : super('Document not found: $id');
}

/// Serialization or deserialization failure (corrupt data, version mismatch).
final class SerializationException extends SearchlightException {
  const SerializationException(super.message);
}

/// Storage operation failure (file I/O, permission errors).
final class StorageException extends SearchlightException {
  final Object? cause;
  const StorageException(super.message, {this.cause});
}

/// Search query references invalid field or uses incompatible filter.
final class QueryException extends SearchlightException {
  const QueryException(super.message);
}
```

### Error Contracts

| Operation | Error Condition | Exception |
|-----------|----------------|-----------|
| `Searchlight.create` | Invalid schema definition | `SchemaValidationException` |
| `insert` | Document doesn't match schema | `DocumentValidationException` |
| `replace` / `patch` | DocId doesn't exist | `DocumentNotFoundException` |
| `search` | Field not in schema, incompatible filter | `QueryException` |
| `deserialize` | Corrupt data, version mismatch | `SerializationException` |
| `restore` | Storage read failure | `StorageException` |
| `persist` | Storage write failure | `StorageException` |

---

## 7. Internal Architecture

### File Structure

```
lib/
└── src/
    ├── core/
    │   ├── database.dart          # Searchlight class — create, CRUD, search, lifecycle
    │   ├── schema.dart            # SchemaField sealed hierarchy, Schema class, validation
    │   ├── document.dart          # Document wrapper, DocId extension type
    │   ├── types.dart             # SearchResult, SearchHit, FacetValue, GeoPoint, etc.
    │   └── exceptions.dart        # SearchlightException sealed hierarchy
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
    │   ├── scorer.dart            # Sealed Scorer hierarchy + deserializeScorer
    │   ├── bm25.dart              # Bm25Scorer (k1=1.2, b=0.75)
    │   ├── qps.dart               # QpsScorer
    │   └── pt15.dart              # Pt15Scorer
    │
    ├── text/
    │   ├── pipeline.dart          # Composable token pipeline (index-time vs search-time)
    │   ├── tokenizer.dart         # Unicode-aware (\p{L}\p{Nd})
    │   ├── normalizer.dart        # NFC via unorm_dart
    │   ├── stemmer.dart           # Language-aware via snowball_stemmer
    │   ├── stop_words.dart        # Per-language stop word sets (29 languages)
    │   └── fuzzy.dart             # Levenshtein-based typo tolerance
    │
    ├── search/
    │   ├── engine.dart            # Query execution orchestrator
    │   ├── filters.dart           # Filter sealed hierarchy + convenience functions
    │   ├── facets.dart            # Facet aggregation and counting
    │   ├── grouping.dart          # Group results by field
    │   └── boost.dart             # Field-level boosting
    │
    ├── highlight/
    │   ├── highlighter.dart       # Standalone Highlighter class
    │   └── positions.dart         # HighlightMatch, HighlightPosition, trim
    │
    ├── persistence/
    │   ├── serializer.dart        # Serialization with format versioning
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
- **Facet index:** `HashMap<String, int>` counting per category value
- **DocId:** Dart extension type wrapping `int` for zero-cost type safety

### Tokenization Pipeline

Separate pipelines for index-time and search-time:

**Index-time:** NFC normalize → lowercase → split on `[^\p{L}\p{Nd}]+` → remove stop words → stem

**Search-time:** NFC normalize → lowercase → split on `[^\p{L}\p{Nd}]+` → stem (no stop word removal for phrase matching)

---

## 8. Highlight API

### Core (searchlight)

The highlighter operates in two modes:

**Standalone mode** — simple substring matching, no pipeline:

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

**Pipeline-aware mode** — uses the same tokenizer/stemmer as the search engine, so stemmed terms match:

```dart
final highlighter = Highlighter.withPipeline(
  pipeline: db.searchPipeline,  // uses the DB's tokenizer + stemmer
);

// Now highlight('running quickly', 'run') will match because
// the stemmer reduces both 'running' and 'run' to the same root.
final result = highlighter.highlight(
  'The runners were running quickly',
  'run',
);
// Matches: 'runners' (positions 4-10), 'running' (positions 17-23)
```

The `search()` method also returns pre-computed highlight data for convenience:

```dart
final results = db.search(term: 'brown fox', properties: ['title', 'body']);
for (final hit in results.hits) {
  // Highlight positions are available per searched field
  hit.highlights['title']?.positions  // positions in title field
  hit.highlights['body']?.positions   // positions in body field
}
```

### Flutter (searchlight_flutter)

```dart
// Widget
HighlightedText(
  text: document.getString('body'),
  positions: hit.highlights['body']?.positions ?? [],
  style: TextStyle(color: Colors.black87),
  matchStyle: TextStyle(
    backgroundColor: Colors.amber.shade200,
    fontWeight: FontWeight.bold,
  ),
  maxLines: 2,
  overflow: TextOverflow.ellipsis,
)

// Lower-level
final spans = positions.toTextSpans(
  text: document.getString('body'),
  matchStyle: TextStyle(backgroundColor: Colors.amber.shade200),
);
```

---

## 9. Persistence & Serialization

### Format Versioning

Every serialized index includes a format version header:

```dart
const currentFormatVersion = 1;

// Serialized structure:
// { "formatVersion": 1, "algorithm": "bm25", "schema": {...}, "data": {...} }
```

On deserialization, the version is checked first. Incompatible versions throw `SerializationException` with a clear message indicating the version mismatch and expected version.

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

// Built-in: file-based (available on mobile/desktop, not web)
final db = Searchlight.create(
  schema: schema,
  storage: FileStorage(path: '/path/to/index.cbor'),
);

await db.persist();  // manual save

final db = await Searchlight.restore(
  storage: FileStorage(path: '/path/to/index.cbor'),
);
// Throws StorageException if load fails
// Throws SerializationException if data is corrupt or version mismatch
```

### What Gets Serialized

- Format version
- Schema, algorithm choice, language/tokenizer config
- All documents (raw data)
- All indexes (inverted, facet, numeric, boolean, geo)
- Scoring metadata (TF/IDF for BM25, proximity for QPS, positions for PT15)

### What Does Not Get Serialized

- Transient query state, isolate workers, storage config, auto-persist timers

---

## 10. Document Adapters

```dart
abstract class DocumentAdapter<T> {
  /// Convert a source object into one or more indexable documents.
  List<Document> toDocuments(T source);
}
```

### searchlight_pdf

```dart
class PdfAdapter implements DocumentAdapter<Uint8List> {
  final PdfExtractionConfig config;
  const PdfAdapter({this.config = const PdfExtractionConfig()});

  @override
  List<Document> toDocuments(Uint8List pdfBytes) { ... }
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

## 11. Dependencies

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

| Purpose | Package | Notes |
|---------|---------|-------|
| Core search | `searchlight` | |
| PDF parsing | `pdf` (pure Dart, Apache 2.0) | Must be pure Dart — no Flutter SDK dependency |

### Built In-House

- Inverted index, BM25/QPS/PT15 scoring, tokenizer pipeline
- Radix tree, typo tolerance (Levenshtein), filter engine
- Facet aggregation, highlight engine
- Stop word lists per language, geohash encoding

---

## 12. Code Quality

- **Lint base:** `very_good_analysis` (~100 strict rules)
- **CI gate:** `dart analyze` with zero warnings
- **Documentation:** `public_member_api_docs` enforced on all public API
- **Future:** `dart_code_metrics` for complexity/maintainability metrics

---

## 13. Implementation Strategy

### TDD Vertical Slices

Each slice delivers a working, testable feature via strict red-green-refactor cycles. No horizontal slicing (all tests first, then all implementation).

| # | Slice | What's Testable After |
|---|-------|----------------------|
| 1 | Schema + exceptions + empty database | Create DB, validate/reject schemas, exception types, `count`, `isEmpty`, `dispose` |
| 2 | Insert + retrieve + remove | `insert`, `getById`, `remove`, `removeMultiple`, `clear`, DocId, `DocumentValidationException` |
| 3 | Batch insert | `insertMultiple` with `BatchResult`, partial failure reporting |
| 4 | Replace + patch | `replace` (full), `patch` (merge), `DocumentNotFoundException` |
| 5 | Basic full-text search (BM25) | Insert docs, search by term, ranked results, `SearchMode.matchAll` vs `.matchAny` |
| 6 | Tokenizer pipeline | NFC → lowercase → split → stem → verify tokens |
| 7 | Typo tolerance | Fuzzy matching with misspellings, tolerance parameter |
| 8 | Search threshold + prefix | Minimum relevance filtering, `SearchMode.prefix` |
| 9 | Number fields + filtering | `between()`, `gt()`, `lt()`, `gte()`, `lte()` with `Filter` types |
| 10 | Boolean fields + filtering | `eq(true/false)` |
| 11 | Enum fields + facets | Facet counts, enum filtering, `FacetValue` |
| 12 | Array fields | `string[]`, `number[]`, `boolean[]`, `enum[]` |
| 13 | Nested objects | Dot-path indexing (`meta.rating`), `NestedField` |
| 14 | Compound filters | Multiple `where` conditions (AND semantics), edge cases |
| 15 | Sorting | Sort by numeric/string fields, multi-field sort |
| 16 | Grouping | Group results by field |
| 17 | Field boosting | Boosted fields rank higher |
| 18 | Geopoint + geosearch | Radius filtering, `GeoPoint`, `GeoRadiusFilter` |
| 19 | Highlighter (standalone) | Positions, trim, case sensitivity, whole words |
| 20 | Highlighter (pipeline-aware) | Stemmed matching, `SearchHit.highlights` |
| 21 | QPS scoring | Proximity-based ranking |
| 22 | PT15 scoring | Position-based ranking |
| 23 | Algorithm migration | `db.reindex(algorithm:)` |
| 24 | JSON persistence | Serialize → deserialize round-trip, format version validation |
| 25 | CBOR persistence | Binary round-trip, corrupt data handling |
| 26 | Storage interface | FileStorage save/load lifecycle, `StorageException` |
| 27 | Multi-language | Non-English stemming + stop words |
| 28 | Isolate support | Background index building |
| 29 | Edge cases | Empty DB search, empty string search, duplicate docs, re-index on update |

### Per-Slice Cycle

1. **Red** — write one test that fails
2. **Green** — minimal implementation to pass
3. **Refactor** — clean up while green
4. **Commit** — each cycle is a committable unit
5. Repeat within the slice

---

## 14. Performance Considerations

- `Uint8List` / typed arrays for large numeric data (posting lists, term frequency arrays)
- Extension types (Dart 3.3+) for zero-cost `DocId`, `TermId` wrappers
- `HashMap` (default `Map`) for inverted index — O(1) lookups dominate search workload
- `SplayTreeMap` for sorted numeric indexes supporting range queries
- Isolate support for index building on large datasets (>10K documents)
- `TransferableTypedData` for shipping binary indexes between isolates without copying
- Avoid linear scan — every query path uses indexed structures
- CBOR for production persistence (smaller, faster than JSON)

---

## 15. Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| `snowball_stemmer` is 4 years old | Snowball algorithms are stable; fork if issues arise |
| No existing Dart BM25 to reuse | Well-documented algorithm; reference lunr's IDF formula |
| Large index isolate transfer | Design for `TransferableTypedData`; benchmark early in slice 28 |
| QPS/PT15 are Orama-specific algorithms | Study Orama docs; implement from algorithm descriptions |
| PDF parsing library choice | Require pure Dart; evaluate `pdf` package first |
| Serialization format evolution | Format version header from day 1; migration logic per version |

---

## 16. Future Considerations (v2+)

Features deliberately deferred from v1:

- **Polygon-based geosearch** — radius is sufficient for v1
- **Result pinning / merchandising** — pin specific docs to top of results
- **Query analytics** — instrument query patterns, popular terms, zero-result queries
- **Cursor-based pagination** — for efficient deep pagination on large result sets
- **`autoPersist` debounce tuning** — configurable debounce duration, flush-on-dispose
- **Vector search / hybrid mode** — explicitly out of scope
- **AI/NLP query interpretation** — explicitly out of scope

---

## Attribution

This project is inspired by [Orama](https://github.com/oramasearch/orama) (Apache 2.0, Copyright Orama contributors). Searchlight is an independent pure Dart reimplementation — not a direct port. A NOTICE file will be included per Apache 2.0 requirements.
