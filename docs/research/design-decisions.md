# Searchlight Design Decisions Log

Decisions made during brainstorming, with rationale.

## Package Identity

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Name | `searchlight` | Available on pub.dev. Evokes "shining light on results" and ties to highlight feature. |
| License | Apache 2.0 | Matches Orama's license. Must include NOTICE file crediting Orama as inspiration. |
| Trademark | Cannot use "Orama" in package name | Apache 2.0 explicitly excludes trademark rights. |

## Scope

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Approach | Pure Dart reimplementation (not a port) | Zero native dependencies, works everywhere Dart runs. Inspired by Orama's feature set. |
| Vector search | Excluded | Out of scope per user. Focus on full-text + filtering. |
| Schema types | All 10 (string, number, boolean, enum, geopoint, + array variants, + nested objects) | Complete feature set for pub.dev consumers. |
| PDF support | Separate adapter package (`searchlight_pdf`) | Keeps core dependency-free. Plugin architecture for extensibility. |

## Architecture

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Package structure | Monorepo: `searchlight`, `searchlight_flutter`, `searchlight_pdf` | Core stays pure Dart. Flutter widgets separate. PDF adapter optional. |
| Search algorithms | BM25 (default), QPS, PT15 — pluggable | Match Orama's offering. Chosen at database creation time. |
| Persistence | Both in-memory and serializable (JSON + CBOR) | JSON for debugging, CBOR for production. Persistence is optional. |
| Highlight API | Positions-based (core), TextSpan helpers (Flutter package) | Core returns match positions. Flutter package converts to styled TextSpan trees. |
| Indexing | Runtime (not build-time) | Flutter apps with user-generated content need runtime index creation. |

## Dependencies (Planned)

| Purpose | Package | Version | Justification |
|---------|---------|---------|---------------|
| Unicode normalization | `unorm_dart` | 0.3.2 | NFC normalization before indexing — non-negotiable for correctness |
| Stemming (multi-lang) | `snowball_stemmer` | 0.1.0 | 29 languages, official Snowball algorithms (stable despite age) |
| Spatial indexing | `r_tree` | 3.0.2 | Workiva-maintained, R-tree for geosearch |
| Geodesy | `geobase` | 1.5.0 | Haversine + Vincenty, comprehensive geo calculations |
| Serialization | `cbor` | 6.5.1 | RFC-compliant binary format for production persistence |

### Build Ourselves
- Inverted index (HashMap-backed)
- BM25/QPS/PT15 scoring
- Tokenizer pipeline (Unicode-aware regex)
- Radix tree for prefix/autocomplete
- Typo tolerance (Levenshtein-based fuzzy matching)
- Filter engine
- Facet aggregation
- Highlight engine
- Stop word lists (static sets per language)
- Geohash encoding

## Performance Considerations
- Use `Uint8List` / typed arrays for large numeric data
- Extension types (Dart 3.3+) for zero-cost type wrappers on IDs
- Isolate support for index building on large datasets
- `TransferableTypedData` for isolate transfers
- Avoid linear scan — inverted index is O(1) term lookup

## Implementation Process

| Decision | Choice | Rationale |
|----------|--------|-----------|
| TDD approach | ACT vertical-slice TDD | One failing test → minimal implementation → refactor → commit. No horizontal slicing. |
| Slice ordering | Schema → CRUD → BM25 search → tokenizer → fuzzy → filters → facets → arrays → nested → sorting → grouping → boosting → geo → highlight → QPS → PT15 → persistence → multi-lang → isolates | Each slice delivers a testable end-to-end feature. Later slices build on earlier ones. |
| Test scope | Public interfaces only | No testing private methods or mocking internals. |
| Commit granularity | Each red-green-refactor cycle is committable | Small, reviewable increments. |

## Code Quality

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Lint base | `very_good_analysis` | VGV's strict rule set — ~100 rules covering immutability, type safety, docs, style |
| Future consideration | `dart_code_metrics` | Additional complexity/maintainability metrics for later |
| CI gate | `dart analyze` with zero warnings | No warnings allowed in CI |
| Documentation | `public_member_api_docs` enforced | All public API must be documented (included in VGV) |

## Risks
- `snowball_stemmer` is 4 years old — may need forking if issues arise
- No existing Dart BM25 implementation to reuse — must build from scratch
- Large index isolate transfer needs careful design
