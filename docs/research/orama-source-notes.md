# Orama Source Code Notes

Observations from reading the actual Orama TypeScript source at `reference/orama/`.

## Error Handling (errors.ts)

- Flat error code map with `sprintf`-style formatting (not class hierarchy)
- Each error has a unique string code like `DOCUMENT_DOES_NOT_EXIST`
- Error messages are very descriptive — include expected types, property names, and links to docs
- `createError(code, ...args)` wraps `Error` with a `.code` property

**Takeaway for Searchlight:** Our sealed exception hierarchy is more Dart-idiomatic, but we should match the descriptive quality of their error messages. Include field names, expected vs actual types, etc.

## Schema & Types (types.ts)

- Schema types are string literals: `'string'`, `'number'`, `'boolean'`, `'enum'`, `'geopoint'`, `'string[]'`, etc.
- Heavy TypeScript type gymnastics with `Flatten<T>` to support dot-path nested access at compile time
- `SearchableType` = scalar | array union types
- `BM25Params` has `k`, `b`, `d` (d is a third parameter we didn't see in spec docs)
- Documents have a string `id` field (not auto-generated int)
- `enum` type accepts `string | number` values

**Takeaway for Searchlight:** Our `SchemaField` sealed hierarchy is cleaner than string literals. Note that Orama's enum accepts both string and number — we should consider this. Also note Orama uses string document IDs vs our auto-increment DocId.

## Create Method (methods/create.ts)

- Heavy use of plugin/component hooks (beforeInsert, afterInsert, etc.)
- Components are swappable: tokenizer, index, documentsStore, sorter
- Creates internal data structures on creation: `index.create()`, `docs.create()`, `sorting.create()`
- Plugins can provide components (with conflict detection)
- Each database instance gets a unique ID

**Takeaway for Searchlight:** Our design is simpler (no plugin hooks, no component swapping). This is fine for v1 — YAGNI. But the internal data initialization pattern (creating index/docs/sorting structures in create) is worth following.

## Insert Method (methods/insert.ts)

- Validates schema first, then stores document, then indexes
- Has both sync and async paths (we can be sync-only for v1)
- `getDocumentIndexId(doc)` extracts/generates the doc ID
- Loops over indexable properties, validates each value against expected type
- Separate `indexAndSortDocument` function handles the actual indexing
- `insertMultiple` with `batchSize` uses `sleep(0)` between batches to yield the event loop

**Takeaway for Searchlight:** Our validation-then-store-then-index flow matches. The `sleep(0)` between batches is a JS pattern for yielding — in Dart we'd use isolates instead.

## Tokenizer (components/tokenizer/)

- Per-language regex splitters (31 languages, explicit character ranges)
- Normalization cache: `Map<"lang:prop:token", normalizedToken>` — avoids re-stemming
- Pipeline: `lowercase → split(langRegex) → normalizeToken(stopWords → stem → replaceDiacritics) → trim → dedup`
- English stemmer is built-in; others must be imported from `@orama/stemmers`
- `allowDuplicates` flag controls whether duplicate tokens in a document are preserved
- `tokenizeSkipProperties` and `stemmerSkipProperties` allow per-field customization
- Separate `replaceDiacritics` function (not just NFC normalization)

**Takeaway for Searchlight:**
1. We should add a normalization cache to our pipeline (significant perf win)
2. Consider diacritics stripping as an option (é→e), separate from NFC normalization
3. Our `\p{L}` regex approach is more universal than per-language char ranges
4. `allowDuplicates` is useful — affects whether TF counts or deduplicates
5. Per-property tokenizer/stemmer skip is a nice extensibility feature for later

## Languages (tokenizer/languages.ts)

- 31 supported languages with explicit regex splitters per language
- Stemmers are mapped to language codes (ar, en, de, etc.)
- The `SPLITTERS` object shows each language has its own regex for word boundaries
- Some languages share similar patterns (Dutch/English/Italian use same regex)

**Takeaway for Searchlight:** Our `\p{L}\p{Nd}` Unicode regex is equivalent to these per-language regexes but more universal. We don't need to maintain 31 separate regexes unless we find edge cases where `\p{L}` behaves differently.

## Search (methods/search.ts)

- Dispatches to fullTextSearch, searchVector, or hybridSearch based on mode
- `fetchDocuments` handles pagination (offset/limit loop)
- `fetchDocumentsWithDistinct` handles deduplication by field value
- Results are `[InternalDocumentID, score][]` tuples, sorted by score
- Documents are fetched from the store only for the paginated window (efficient)

**Takeaway for Searchlight:** The pattern of scoring first (producing ID+score tuples) then fetching documents only for the result window is efficient and we should follow it.

## Key Patterns

1. **Internal vs External IDs**: Orama has a mapping layer (`InternalDocumentIDStore`) between string user-facing IDs and integer internal IDs. This is for performance — internal indexes use ints, but the API uses strings.

2. **Component architecture**: Everything is swappable — index, tokenizer, document store, sorter. For v1 Searchlight, we don't need this but it's good architecture to keep in mind.

3. **Normalization cache**: Token normalization (stem + diacritics) is cached per language/property/token triple. This avoids redundant computation on repeated inserts/searches.

4. **Sync/Async dual path**: Each method has both sync and async implementations. In Dart, we can start sync and add async (isolate) support later.
