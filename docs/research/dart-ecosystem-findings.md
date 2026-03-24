# Full-Text Search Engine in Pure Dart: Research Findings

## 1. Data Structure Libraries in Dart

### Built-in (dart:collection)

| Structure | Class | Complexity | Notes |
|-----------|-------|-----------|-------|
| Hash map | `HashMap`, `LinkedHashMap` (default `Map`) | O(1) avg lookup | Uses bucket array, chaining for collisions. Initial capacity 8. Keys must have consistent `==` and `hashCode`. |
| Sorted map | `SplayTreeMap` | O(log n) amortized | Self-balancing, moves frequently-accessed nodes to root. Good for range queries. |
| Sorted set | `SplayTreeSet` | O(log n) amortized | Same splay tree backing. Supports custom comparators. |
| Queue | `Queue`, `ListQueue`, `DoubleLinkedQueue` | O(1) add/remove ends | Useful for BFS in graph traversals. |

**Key insight**: `LinkedHashMap` (Dart's default `Map`) preserves insertion order with O(1) lookups. For an inverted index, this is typically the right default -- you get fast term lookups without needing sorted order.

### Trie / Prefix Tree Packages

| Package | Version | Last Updated | Approach | Notes |
|---------|---------|-------------|----------|-------|
| `itrie` | 0.0.2 | Jan 2024 | Immutable ternary search trie | Stack-safe, path-copying for immutability. API: `insert`, `get`, `withPrefix`, `keysWithPrefix`, `longestPrefixOf`. Extends `Iterable`. 140 pub points. |
| `radix_tree` | 2.2.0 | Feb 2025 | Compressed trie (radix tree) | Map-based API. `getValuesWithPrefix('pa')`. Single dep (`meta`). 150 pub points. Actively maintained. |
| `basic_trie` | — | — | Simple trie | Set/get values, removal, renaming. |
| `trie_search` | 0.0.2 | — | Basic trie | Insert, prefix search, clear. |
| `retrieval` | — | — | Standard trie | Autocomplete-focused. |

**Recommendation**: `radix_tree` is the best maintained and most memory-efficient for prefix autocomplete. `itrie` is interesting for its immutability guarantees. For a search engine, you may want a custom trie optimized for your token set representation (see lunr's `TokenSet` below).

### Tree Structures

| Package | Version | Last Updated | Type | Notes |
|---------|---------|-------------|------|-------|
| `r_tree` | 3.0.2 | ~Feb 2025 | R-tree (spatial) | Published by Workiva. 2D spatial indexing, configurable branch factor. 30k downloads. Useful for geosearch bounding-box queries. |
| `rbtree` | — | — | Red-black tree | Basic implementation. |
| `binary_tree` | — | — | AVL tree | Self-balancing, implements `Iterable`. |
| `tree_structures` | — | — | Red-black tree | Educational, Graphviz output. |

**Key finding**: No B-tree implementation exists on pub.dev. For disk-backed indexes, you'd need to build one. For in-memory, `SplayTreeMap` or custom structures suffice.

---

## 2. String Processing and Tokenization in Dart

### Core Dart String APIs

- **`String.split(Pattern)`**: Basic splitting by delimiter or regex. `split(RegExp(r'\s+'))` for whitespace tokenization.
- **`String.codeUnits`**: UTF-16 code units (fast, but not Unicode-safe for surrogate pairs).
- **`String.runes`**: Unicode code points as `Runes` (Iterable<int>). Handles emoji and non-BMP characters correctly.
- **`String.toLowerCase()` / `toUpperCase()`**: Locale-unaware by default.
- **`String.replaceAll(Pattern, String)`**: Regex-powered character filtering.
- **`String.substring(start, end)`**: O(1) for the VM (strings are backed by flat arrays).

### Unicode-Aware RegExp

Dart RegExp supports ECMAScript-style Unicode property escapes when the `unicode` flag is enabled:

```dart
// Match any Unicode letter (all scripts)
RegExp(r'\p{L}+', unicode: true)

// Match letters + numbers + marks (comprehensive word characters)
RegExp(r'[\p{L}\p{Nd}\p{M}]+', unicode: true)

// Custom word boundary that is Unicode-aware
RegExp(r'(?<=\P{L})(?=\p{L})|(?<=\p{L})(?=\P{L})', unicode: true)
```

This is critical for multi-language tokenization. Unlike `\w` (which only matches ASCII word characters), `\p{L}` matches letters in any script (Arabic, CJK, Cyrillic, Devanagari, etc.).

### Grapheme Cluster Support

- **`characters` package** (official Dart team): Exposes `String.characters` as grapheme cluster iterable. Based on Unicode 16.0. Essential for emoji-safe string operations.
- **`Runes` class**: Code point level, not grapheme level. A flag emoji (e.g., 🇺🇸) is 2 code points but 1 grapheme cluster.

### Tokenizer Packages

| Package | Approach | Notes |
|---------|----------|-------|
| `string_tokenizer_1` | Delimiter-based streaming | `nextToken()` API, can change delimiters mid-stream. |
| `token_parser` | Grammar-based lexical analysis | Define lexemes as regex patterns, combine with operators. Overkill for search. |

### Tokenization Patterns from lunr (Dart port)

The lunr tokenizer is simple and effective (see source analysis in Section 5):
1. Convert to lowercase
2. Split on `[\s\-]+` (whitespace and hyphens)
3. Track position metadata (offset, length, index) per token
4. Return `List<Token>` where `Token` wraps string + metadata

**For a custom search engine, the recommended tokenization pipeline is:**
1. Unicode normalization (NFC via `unorm_dart`)
2. Lowercase (`String.toLowerCase()`)
3. Split on Unicode-aware non-letter boundaries (`RegExp(r'[^\p{L}\p{Nd}]+', unicode: true)`)
4. Filter stop words
5. Stem (via `snowball_stemmer` or `stemmer`)

---

## 3. In-Memory Indexing Patterns in Dart

### Pattern A: Inverted Index (HashMap-based)

The dominant pattern. Used by lunr, text_indexing, and free_text_search.

**Structure:**
```
Map<String, Map<String, List<int>>>
     ^term       ^docId     ^positions
```

Or more efficiently:
```
Map<String, PostingList>
```

Where `PostingList` contains document references, term frequencies, and optionally field-level positions.

**lunr's approach** (from source analysis):
- `InvertedIndex` extends `MapBase<dynamic, Posting>` — wraps a `Map<Token, Posting>`
- `Posting` extends `MapBase<String, dynamic>` — stores `_index` (term's position in vector space) plus per-field posting data
- `Vector` class — sparse vector using a flat `List<num>` with alternating [index, value] pairs and binary search for position lookup
- `FieldRef` — compound key `"fieldName/docRef"` for field-scoped vectors
- BM25 scoring with tunable `b` (field length normalization, default 0.75) and `k1` (term frequency saturation, default 1.2)

**text_indexing's approach** (GM Consult):
- Three separate hashmaps: dictionary, k-gram index, postings
- `InMemoryIndex` for small corpora (~0.68ms per document indexing)
- `AsyncCallbackIndex` for hybrid storage (dictionary in memory, postings on disk)
- ~22ms query latency on 20K documents

### Pattern B: Pipeline Architecture

lunr uses a `Pipeline` class — a chain of `PipelineFunction` callbacks that transform tokens:
1. `trimmer` — strip non-word characters
2. `stopWordFilter` — remove common words
3. `stemmer` — reduce to root form

Separate pipelines for indexing vs. searching (search pipeline can differ).

### Pattern C: TokenSet (Finite State Automaton)

lunr's `TokenSet` is a particularly clever structure — it's essentially a minimized finite automaton:
- `edges: Map<String, TokenSet>` — character transitions
- `isFinal: bool` — marks end of valid term
- `fromFuzzyString(str, editDistance)` — builds an NFA that accepts strings within `editDistance` edits
- `intersect(other)` — computes intersection of two automata (used for wildcard + fuzzy matching)

This is more memory-efficient than storing all terms in a flat set and supports fuzzy matching natively.

### Pattern D: Field Vectors for Cosine Similarity

lunr stores TF-IDF vectors per field per document:
- Sparse vector format: `List<num>` with `[termIndex, weight, termIndex, weight, ...]`
- Binary search for element access (`positionForIndex`)
- `dot(other)` and `similarity(other)` for cosine similarity scoring
- IDF formula: `log(1 + abs((N - n + 0.5) / (n + 0.5)))` (BM25 variant)

### Isolate Considerations

For large indexes:
- **Index building** should run in an isolate (CPU-intensive)
- **Querying** is typically fast enough for the main thread (sub-millisecond for moderate corpora)
- Use `TransferableTypedData` for large binary index transfers between isolates (avoids O(n) copy)
- `Isolate.run` for one-off tasks; long-lived isolates with `ReceivePort`/`SendPort` for persistent index workers
- Serialized indexes (JSON/binary) transfer more efficiently than live object graphs

---

## 4. Serialization of Complex Data Structures

### JSON (dart:convert)

| Aspect | Detail |
|--------|--------|
| Built-in | `jsonEncode` / `jsonDecode` in `dart:convert` |
| Performance | Fast for moderate sizes, but string-heavy and verbose |
| Index size | ~2-3x larger than binary formats |
| Compatibility | Universal, human-readable, debuggable |
| Limitations | No native Uint8List support (must base64-encode), no typed numbers (everything is num) |

lunr serializes its entire index to/from JSON, including the inverted index, field vectors, and token set. This proves JSON is viable for moderate-sized indexes.

### Binary Serialization Options

| Format | Package | Version | Updated | Pros | Cons |
|--------|---------|---------|---------|------|------|
| **CBOR** | `cbor` | 6.5.1 | Feb 2025 | RFC8949 compliant, typed arrays, auto-optimizes int/float sizes, semantic types. 73K downloads, 160 pub points. | Less tooling than JSON |
| **MessagePack** | `messagepack` | 0.2.1 | Apr 2021 | Streaming Packer/Unpacker API, compact. | Stale (4+ years), unverified publisher. Only handles primitives, maps, lists. |
| **Protocol Buffers** | `protobuf` | 6.0.0 | Nov 2025 | Google-maintained, 1.4M downloads, schema-driven, cross-language. 45% smaller than JSON. | Requires .proto files + code gen. Schema overhead for index structures. |
| **FlatBuffers** | `flat_buffers` | 25.9.23 | Nov 2025 | Zero-copy reads (fastest deserialization), good for read-heavy indexes. | Schema + code gen required. Larger serialized size. |
| **Custom binary** | `binarize` | 2.0.0 | Feb 2025 | BinaryContract for typed classes, PayloadWriter/PayloadReader, no offset math. 160 pub points. | Smaller community. |

### Raw Binary (dart:typed_data)

For maximum performance and control:

- **`ByteData`**: Random access to fixed-width ints/floats at specific offsets. Explicit endianness.
- **`BytesBuilder`**: Mutable builder for constructing byte sequences. `add()` for Uint8List chunks, `toBytes()` to finalize.
- **`Uint8List`**: Fixed-length byte array. View of `ByteBuffer`. Can share buffer with `Int32List`, `Float64List` etc.
- **Typed arrays**: `Float32List`, `Int32List`, `Uint16List` etc. "For long lists, this implementation can be considerably more space- and time-efficient than the default List implementation."

**Recommended serialization strategy for a search index:**

1. **Development/debugging**: JSON — human-readable, easy to inspect
2. **Production/compact**: CBOR — good balance of compactness, speed, and maintained package quality
3. **Maximum performance**: Custom binary via `ByteData`/`BytesBuilder` with a documented format spec
4. **Cross-language interop**: Protocol Buffers if the index needs to be consumed by other languages

### Extension Types for Zero-Cost Wrappers

Dart 3.3+ extension types enable wrapping `int`, `Uint8List`, etc. with type-safe APIs and zero runtime overhead:

```dart
extension type DocId(int _id) {
  // Type-safe document ID, compiles to raw int at runtime
  bool get isValid => _id >= 0;
}
```

This is highly relevant for search indexes where you want type safety for document IDs, term IDs, posting offsets, etc. without the memory cost of wrapper objects.

---

## 5. Existing Full-Text Search Implementations

### lunr (Dart port of lunr.js)

| Aspect | Detail |
|--------|--------|
| Version | 2.3.10 |
| Updated | ~3 years ago |
| Publisher | hornmicro.com (verified) |
| Architecture | Inverted index + BM25 + field vectors + pipeline |
| Deps | collection, intl |

**Architecture (from source analysis):**

```
lib/
├── builder.dart       — Index construction (BM25 params, field config, document ingestion)
├── index.dart         — InvertedIndex (Map<Token, Posting>), query execution, scoring
├── pipeline.dart      — Chainable PipelineFunction transforms (trimmer, stopwords, stemmer)
├── tokenizer.dart     — Split on [\s\-]+, lowercase, position tracking
├── token.dart         — String + metadata wrapper
├── token_set.dart     — Finite automaton for term matching (fuzzy, wildcard, prefix)
├── token_set_builder.dart — Builds minimized automaton from sorted term list
├── vector.dart        — Sparse TF-IDF vector (alternating index/value List<num>)
├── field_ref.dart     — "field/docRef" compound key
├── idf.dart           — IDF: log(1 + abs((N - n + 0.5) / (n + 0.5)))
├── query.dart         — Query clauses with boost, wildcard, edit distance
├── query_lexer.dart   — Tokenizes query strings
├── query_parser.dart  — Parses query tokens into Query objects
├── stemmer.dart       — Porter stemmer integration
├── stop_word_filter.dart — English stop word list
├── trimmer.dart       — Strip non-word chars
├── set.dart           — Set operations (union, intersect) for document matching
├── match_data.dart    — Per-result match metadata
└── utils.dart         — Helpers
```

**Key design decisions:**
- BM25 with tunable `b=0.75` and `k1=1.2`
- Sparse vector cosine similarity for ranking
- TokenSet automaton for wildcard/fuzzy queries (edit distance via NFA construction)
- JSON serialization for index persistence
- Pipeline pattern separates index-time and search-time text processing

**Strengths:** Well-architected, proven design (port of battle-tested JS library). Full BM25 scoring. Fuzzy matching via automaton.
**Weaknesses:** No isolate support. No binary serialization. No multi-language support (English-only stemmer/stopwords). 3 years without updates.

### text_search

| Aspect | Detail |
|--------|--------|
| Version | 1.0.2 |
| Updated | May 2024 |
| Publisher | flutterflow.io (verified) |
| Approach | Simple fuzzy matching |
| Downloads | 75K |

Simple in-memory fuzzy search. `TextSearchItem.fromTerms()` + `TextSearch().search()`. No inverted index — linear scan with fuzzy matching. Good for small datasets (< 1000 items), not scalable.

### free_text_search

| Aspect | Detail |
|--------|--------|
| Version | 0.0.1-beta.5 |
| Updated | Sep 2022 |
| Approach | Positional inverted index |

Supports Google-like query modifiers (`"phrase"`, `+term`, `-term`, `OR`). Async dictionary/postings interface. `QueryParser` produces `QueryTerm` objects. Beta quality, not actively maintained.

### text_indexing (GM Consult)

| Aspect | Detail |
|--------|--------|
| Version | 1.0.0 |
| Updated | Nov 2022 |
| Approach | Positional + zoned inverted index with k-gram support |

The most feature-complete indexing library:
- Dictionary (term -> frequency)
- K-gram index (character n-grams -> terms, for fuzzy matching)
- Positional postings (term -> doc -> positions + zones)
- `InMemoryIndex` and `AsyncCallbackIndex` implementations
- Benchmarked at 0.68ms/doc indexing, 22ms/query on 20K docs
- Depends on `text_analysis` for tokenization/stemming

**Weaknesses:** Pre-release status. 3 years old. Complex dependency tree (rxdart, etc.).

### text_analysis (GM Consult)

| Aspect | Detail |
|--------|--------|
| Version | 1.0.0+2 |
| Updated | Nov 2022 |
| Features | Tokenization, n-grams, RAKE keyword extraction, Flesch readability, similarity metrics |

Companion to text_indexing. Provides:
- `TextAnalyzer` interface with `LatinLanguageAnalyzer` mixin
- English analyzer with Porter2 stemmer (via `porter_2_stemmer`)
- Term similarity: Damerau-Levenshtein, edit similarity, Jaccard
- `TextDocument` class for full document analysis

### Summary Comparison

| Package | Scalability | Scoring | Fuzzy | Multi-lang | Maintained | Best For |
|---------|------------|---------|-------|------------|------------|----------|
| lunr | Medium | BM25 | Yes (automaton) | No | Stale | Reference architecture |
| text_search | Small | Simple | Yes | No | Recent | Quick prototype |
| free_text_search | Medium | Custom | No | No | Stale | Query parsing patterns |
| text_indexing | Medium-Large | Custom | K-gram | No | Stale | Indexing patterns |

**Conclusion:** No package is both feature-complete and actively maintained. lunr has the best architecture to study. Building a new implementation is justified.

---

## 6. Unicode / Internationalization / Multi-language Stemming

### Unicode Normalization

| Package | Version | Updated | Features |
|---------|---------|---------|----------|
| `unorm_dart` | 0.3.2 | Oct 2025 | NFC, NFD, NFKC, NFKD. Unicode 17.0. 143K downloads. |

**Critical for search**: Always normalize to NFC before indexing. Otherwise, identical-looking strings (e.g., "é" as single code point vs. "e" + combining accent) won't match.

### Stemming

| Package | Version | Updated | Languages | Algorithm |
|---------|---------|---------|-----------|-----------|
| `snowball_stemmer` | 0.1.0 | Oct 2021 | **29 languages**: Arabic, Armenian, Basque, Catalan, Danish, Dutch, English, Finnish, French, German, Greek, Hindi, Hungarian, Indonesian, Irish, Italian, Lithuanian, Nepali, Norwegian, Porter, Portuguese, Romanian, Russian, Serbian, Spanish, Swedish, Tamil, Turkish, Yiddish | Snowball compiled stemmers |
| `stemmer` | 3.2.0 | Oct 2025 | English | Porter + Snowball. Actively maintained. 150 pub points. |
| `porter_2_stemmer` | — | — | English | Porter2 (99.66% accuracy vs Snowball test vocabulary) |

**Recommendation:** `snowball_stemmer` for multi-language support (29 languages from the official Snowball project). `stemmer` for English-only (more actively maintained).

### Stop Words

- lunr includes a built-in English stop word filter
- `sherlock` package exposes `RemoveStopWords` extension on String
- For multi-language, you'll likely need to bundle your own stop word lists (they're just static `Set<String>` per language)

### Grapheme and Character Support

- **`characters` package** (Dart team): Unicode 16.0 grapheme clusters. Essential for emoji-safe string length/iteration.
- **`unicode` package**: Additional Unicode utilities.
- **Dart RegExp with `unicode: true`**: Supports `\p{L}` (any letter), `\p{Nd}` (digits), `\p{M}` (marks), etc. This is the correct way to tokenize multi-language text.

### Fuzzy Matching / Edit Distance

| Package | Version | Updated | Algorithms |
|---------|---------|---------|------------|
| `fuzzywuzzy` | 1.2.0 | Aug 2024 | Levenshtein distance, partial ratio, token sort/set. 70K downloads. Actively maintained. |
| `edit_distance` | 0.4.1 | 6 years ago | Levenshtein, Damerau-Levenshtein, LCS, Jaro-Winkler, Jaccard n-gram. **Not Dart 3 compatible** (only null-safety prerelease). |

**Note:** No BK-tree implementation exists in Dart. lunr's `TokenSet.fromFuzzyString` approach (building an NFA that accepts terms within edit distance) is the most practical alternative.

### Multi-Language Tokenization Strategy

```
Input text
  → Unicode normalize (NFC via unorm_dart)
  → Lowercase
  → Split on non-letter/digit boundaries (RegExp with \p{L}\p{Nd}, unicode: true)
  → Language detection (optional)
  → Stop word removal (language-specific list)
  → Stemming (snowball_stemmer with detected language)
  → Output tokens
```

---

## 7. Haversine / Geosearch in Dart

### Distance Calculation Packages

| Package | Version | Updated | Features | Status |
|---------|---------|---------|----------|--------|
| `geobase` | 1.5.0 | Mar 2025 | **Comprehensive**: Vincenty (ellipsoidal) + spherical geodesy, UTM, MGRS, ECEF, GeoJSON/WKT/WKB, projections, tiling. | Actively maintained. Best choice. |
| `geodesy` | 0.10.2 | Nov 2023 | Haversine distance, bearing, destination, bounding box, geofencing. | Moderate maintenance. |
| `haversine_distance` | 1.2.1 | Mar 2021 | Simple distance calc: KM, MILE, METER, NMI. | Stale but functional. |
| `haversine` | 1.0.2 | Feb 2018 | Basic great-circle distance. | **Dart 3 incompatible.** |
| `flutter_map_math` | — | — | Haversine-based distance calculations. | Flutter-specific. |

### Spatial Indexing for Geosearch

| Package | Version | Updated | Features |
|---------|---------|---------|----------|
| `r_tree` | 3.0.2 | Feb 2025 | R-tree for 2D spatial indexing. Rectangle-based queries. Configurable branch factor. Published by Workiva. 30K downloads. |
| `route_spatial_index` | — | — | Two-level R-tree (segment + cluster) for route nearest-point queries. |

### Implementing Geosearch in a Search Engine

The Haversine formula itself is trivial (~10 lines of Dart):

```dart
import 'dart:math';
double haversine(double lat1, double lon1, double lat2, double lon2) {
  const R = 6371.0; // Earth radius in km
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a = sin(dLat/2) * sin(dLat/2) +
            cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
            sin(dLon/2) * sin(dLon/2);
  return R * 2 * atan2(sqrt(a), sqrt(1-a));
}
```

But for a **search engine with geosearch**, you need spatial indexing to avoid O(n) distance calculations:

**Recommended approach:**
1. **Bounding box pre-filter**: Compute a bounding box around the search center at the desired radius. Use simple lat/lon range comparisons to eliminate distant documents. This is O(1) per document if stored in a sorted structure.
2. **R-tree index** (`r_tree` package): For complex spatial queries (nearest-k, within-polygon). O(log n) queries.
3. **Geohash-based bucketing**: Encode lat/lon as geohash strings, use prefix matching for proximity. Integrates naturally with a text-based inverted index (geohash prefixes become indexable terms).
4. **Final ranking**: Apply Haversine on the candidate set for exact distance, blend with text relevance score.

`geobase` is the recommended package — it provides both Vincenty (ellipsoidal, more accurate) and spherical calculations, plus GeoJSON support, bounding boxes, and projections.

---

## Cross-Cutting Recommendations

### Architecture for a Pure Dart Search Engine

```
┌─────────────────────────────────────────────────┐
│                   Public API                     │
│  SearchEngine / IndexBuilder / QueryBuilder      │
├─────────────────┬───────────────────────────────┤
│  Text Pipeline  │   Query Engine                │
│  ┌───────────┐  │  ┌───────────────────────┐    │
│  │ Normalize  │  │  │ Query Parser          │    │
│  │ Tokenize   │  │  │ (terms, phrases,      │    │
│  │ Filter     │  │  │  modifiers, fuzzy)    │    │
│  │ Stem       │  │  ├───────────────────────┤    │
│  └───────────┘  │  │ Scorer (BM25)         │    │
│                 │  │ Matcher (bool, phrase) │    │
│                 │  └───────────────────────┘    │
├─────────────────┴───────────────────────────────┤
│                 Index Layer                      │
│  ┌────────────┐ ┌──────────┐ ┌──────────────┐  │
│  │ Inverted   │ │ TokenSet │ │ Field        │  │
│  │ Index      │ │ (FSA)    │ │ Vectors      │  │
│  │ (HashMap)  │ │          │ │ (sparse)     │  │
│  └────────────┘ └──────────┘ └──────────────┘  │
│  ┌────────────┐ ┌──────────┐                    │
│  │ Geo Index  │ │ Facet    │                    │
│  │ (R-tree /  │ │ Index    │                    │
│  │  geohash)  │ │          │                    │
│  └────────────┘ └──────────┘                    │
├─────────────────────────────────────────────────┤
│              Serialization Layer                 │
│  JSON (debug) | CBOR (production) | Binary      │
├─────────────────────────────────────────────────┤
│              Isolate Bridge (optional)           │
│  Index building / large queries in background    │
└─────────────────────────────────────────────────┘
```

### Recommended Dependencies (Minimal)

| Purpose | Package | Justification |
|---------|---------|---------------|
| Unicode normalization | `unorm_dart` | NFC normalization before indexing |
| Stemming (multi-lang) | `snowball_stemmer` | 29 languages, Snowball project |
| Stemming (English) | `stemmer` or `porter_2_stemmer` | Actively maintained, high accuracy |
| Grapheme clusters | `characters` | Emoji-safe string operations |
| Spatial indexing | `r_tree` | Workiva-maintained, R-tree for geosearch |
| Geodesy | `geobase` | Haversine + Vincenty, comprehensive |
| Serialization | `cbor` | RFC-compliant, well-maintained, compact |
| Fuzzy matching | `fuzzywuzzy` | Levenshtein, actively maintained |

### What to Build Custom

- **Inverted index**: The core HashMap<String, PostingList> is simple enough to own
- **BM25 scorer**: ~30 lines of Dart, too central to delegate
- **TokenSet / automaton**: lunr's approach is excellent to study but tightly coupled to its Token type
- **Text pipeline**: Composable function chain, project-specific
- **Stop word lists**: Static sets per language, trivially bundled
- **Geohash encoding**: ~50 lines if you want index-integrated geosearch

### Performance Considerations

1. **Use `Uint8List` / typed arrays** for any large numeric data (posting lists, term frequency arrays)
2. **Extension types** (Dart 3.3+) for zero-cost type wrappers on IDs and offsets
3. **`BytesBuilder`** for constructing binary serialization without offset math errors
4. **`SplayTreeMap`** if you need sorted term iteration (for range queries, prefix scans)
5. **`HashMap` (default `Map`)** for the inverted index — O(1) lookups dominate search workload
6. **Isolates** for index building only; queries should be fast enough for main thread
7. **`TransferableTypedData`** for shipping binary indexes between isolates without copying

### Anti-Patterns to Avoid

- **Linear scan search** (text_search approach): Does not scale beyond ~1000 items
- **Reflection-based serialization**: Use code generation or manual toJson/fromJson
- **Ignoring Unicode normalization**: Will cause "identical" strings to not match
- **`String.codeUnits` for character iteration**: Breaks on surrogate pairs (emoji, CJK supplementary)
- **Mutable global state in index**: Makes isolate usage and testing difficult
- **Over-relying on JSON for large indexes**: Consider CBOR or custom binary for > 10MB indexes
