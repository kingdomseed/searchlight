# Orama Functional Equivalence Audit -- Phase 2

**Date:** 2026-03-25
**Auditor:** Claude (Opus 4.6)
**Ground Truth:** Orama TypeScript source (`reference/orama/packages/orama/src/`)
**Subject:** Searchlight Dart implementation (`packages/searchlight/lib/src/`)

---

## A. Tokenizer Pipeline

### Orama Flow (`tokenizer/index.ts`)
1. If `prop` is in `tokenizeSkipProperties`, normalize the raw input as a single token
2. Otherwise: `input.toLowerCase().split(SPLITTERS[language]).map(normalizeToken).filter(Boolean)`
3. `trim()` -- strip leading/trailing empty strings
4. Deduplicate via `new Set()` when `!allowDuplicates`

### Searchlight Flow (`text/tokenizer.dart`)
1. If `property` is in `tokenizeSkipProperties`, normalize the raw input as a single token
2. Otherwise: `input.toLowerCase().split(splitters[language]!).map(normalizeToken).where(isNotEmpty).toList()`
3. `_trim()` -- strip leading/trailing empty strings
4. Deduplicate via `tokens.toSet().toList()` when `!allowDuplicates`

**Divergences:**

- **Orama `filter(Boolean)` vs Searchlight `.where((t) => t.isNotEmpty)`**: ACCEPTABLE -- In JS, `filter(Boolean)` removes falsy values (empty strings). In Dart, `.where((t) => t.isNotEmpty)` is the exact equivalent for strings. Functionally identical.

- **normalizeToken pipeline order matches**: Both follow: cache check -> stop word check -> stemming -> diacritics replacement -> cache store. ACCEPTABLE -- Identical.

- **Orama `tokenize()` accepts `language` parameter and throws if mismatched; Searchlight ignores language at tokenize time**: NEEDS REVIEW -- Orama validates `language && language !== this.language` and throws. Searchlight ignores the `language` parameter in the `tokenize` signature entirely. In practice, Orama never calls `tokenize` with a different language in the search pipeline, so this is a defensive check that Searchlight omits. Low risk but a behavioral gap.

- **Orama `typeof input !== 'string'` guard returns `[input]`; Searchlight has no such guard**: ACCEPTABLE -- Dart's type system enforces `String input` at compile time, making this JS runtime check unnecessary.

- **Stemming: Orama only has a built-in English stemmer and throws for other languages; Searchlight uses `snowball_stemmer` package for all languages**: NEEDS REVIEW -- Orama's `createTokenizer` throws `MISSING_STEMMER` when `stemming: true` for non-English without a custom stemmer. Searchlight silently provides Snowball stemmers for all supported languages. This means Searchlight produces stemmed tokens for non-English languages where Orama would error. The search behavior will differ for non-English stemming scenarios.

- **Language splitter regexes**: All regexes in `languages.dart` are Unicode-escape equivalents of the literal characters in `languages.ts`. Verified character-by-character. ACCEPTABLE.

- **Diacritics mapping**: The `_charcodeReplaceMapping` in `diacritics.dart` has 197 entries matching `CHARCODE_REPLACE_MAPPING` in `diacritics.ts` (196 entries). The Dart version has one extra entry at the end (`null` -> kept from Orama uses `|| charCode` fallback). Both use charcode range 192-383. ACCEPTABLE -- Functionally equivalent via the fallback logic.

**Action items:**
- Consider adding language parameter validation to `tokenize()` for parity (low priority).
- Document the stemming divergence: Searchlight provides broader stemmer coverage than Orama.

---

## B. Radix Tree

### insert()
Both implementations follow identical logic:
1. Iterative traversal matching characters
2. Common prefix detection between edge label and remaining word
3. Edge splitting creating intermediate nodes when prefix diverges
4. New leaf creation for unmatched suffixes

**Divergences:**

- **Children container: Orama uses `Map<string, RadixNode>`, Searchlight uses `Map<String, RadixNode>` (Dart linked HashMap)**: ACCEPTABLE -- Both provide O(1) key lookup. Dart's `Map` default (LinkedHashMap) preserves insertion order; JS `Map` also preserves insertion order. Identical behavior.

- **Document IDs: Orama uses `Set<InternalDocumentID>`, Searchlight uses `Set<int>`**: ACCEPTABLE -- Type-safe Dart equivalent.

### find() (prefix/exact search)
Both implementations follow the same edge-following logic with identical edge-label comparison, partial match handling, and terminal node collection via `findAllWords`.

**Divergences:**

- **None found**: The prefix/exact find logic is line-for-line equivalent.

### findAllWords() (DFS collection)
Both use stack-based DFS. The logic for collecting end-of-word nodes is functionally identical.

**Divergences:**

- **Orama `getOwnProperty(output, w) !== null` vs Searchlight `!output.containsKey(w)`**: NEEDS REVIEW -- Orama's first check `getOwnProperty(output, w) !== null` is checking if the key does NOT exist (returns `null` when property is absent, but `undefined` when it exists but has the value... actually, looking more carefully: Orama uses `!== null` on the first check which means "key not present" since `getOwnProperty` returns `undefined` for existing keys. Wait -- re-reading: `getOwnProperty` returns `undefined` if key is NOT an own property. So `!== null` is always true unless the value is explicitly `null`. This is a guard against JS prototype pollution. The Dart `!output.containsKey(w)` is the correct semantic equivalent since Dart maps don't have prototype chains. ACCEPTABLE.

- **Orama passes `tolerance` as positional boolean `0` in `_findLevenshtein` -> `findAllWords(output, term, false, 0)`; Searchlight's `_findLevenshtein` calls `findAllWords(output, term)` without tolerance**: NEEDS REVIEW -- In Orama's `_findLevenshtein`, when `node.w.startsWith(term)`, it calls `node.findAllWords(output, term, false, 0)` with `tolerance=0`, which means it collects all words in the subtree without Levenshtein filtering. Searchlight calls `node.findAllWords(output, term)` without tolerance, which also collects all words without filtering. Functionally equivalent because `tolerance: null` in Searchlight's `findAllWords` triggers the non-tolerance path. ACCEPTABLE.

### _findLevenshtein() (fuzzy search)
Both use stack-based traversal with the same three operations (match, delete, insert/substitute).

**Divergences:**

- **None found**: The fuzzy search logic with the Levenshtein-based DFS traversal is structurally identical. Same operations pushed to the stack in the same order.

### removeWord()
Both traverse the tree to find the target word, clear document IDs and end marker, then clean up empty nodes by walking back up the stack.

**Divergences:**

- **Orama loop: `for (let i = 0; i < termLength; i++)` with `i += childNode.s.length - 1`; Searchlight loop: `for (var i = 0; i < termLength;)` with `i += childNode.subword.length`**: ACCEPTABLE -- Orama increments `i` in the for-loop header AND adds `childNode.s.length - 1` inside, net effect: `i += childNode.s.length`. Searchlight manually increments `i += childNode.subword.length` with no auto-increment. Same result.

### removeDocumentByWord()
Both traverse the tree following the word's characters and remove the document ID from matching nodes.

**Divergences:**

- **Same loop increment difference as removeWord()**: ACCEPTABLE -- Same explanation as above.

**Action items:** None.

---

## C. AVL Tree

### insert() with deferred rebalancing
Both implementations use iterative insertion with path tracking. Key algorithm match:
1. BST insertion following key comparison
2. Path recorded for backtracking
3. Deferred rebalancing based on `insertCount % rebalanceThreshold === 0`
4. Standard AVL rotations (LL, LR, RL, RR cases)

**Divergences:**

- **Orama uses `<` and `>` operators directly on keys; Searchlight uses `key.compareTo(current.key)`**: ACCEPTABLE -- Dart's `Comparable.compareTo` is the standard way to compare generic types. Semantically identical.

- **Orama initializes AVL tree for number fields with `new AVLTree<number, InternalDocumentID>(0, [])` (root node with key=0); Searchlight creates `AVLTree<num, int>()` (empty root=null)**: MUST FIX -- Orama's number index starts with a root node at key=0, while Searchlight starts with null root. This means the first insertion in Orama adds the value to the existing node if key=0, while Searchlight always creates a new root. This could cause divergent behavior for documents with value 0 in number fields, and affects the tree structure for all subsequent insertions.

### rangeSearch / greaterThan / lessThan
Both use iterative in-order or reverse in-order traversal with early termination.

**Divergences:**

- **Orama uses `>=`, `<=`, `>`, `<` operators; Searchlight uses `.compareTo()` with `>= 0`, `<= 0`, etc.**: ACCEPTABLE.

- **Return type: Orama returns `Set<V>`; Searchlight returns `Set<V>`**: ACCEPTABLE -- Identical.

### remove()
Both use path-tracked iterative removal with in-order successor for two-child nodes, followed by rebalancing walk-back.

**Divergences:**

- **Orama's `removeNode` may access `current.l!` or `current.r!` without null check during path traversal; Searchlight uses `current.left == null` check returning `rootNode`**: ACCEPTABLE -- Both handle the "key not found" case, just with different guard styles.

### removeDocument()
Both find the node by key, then either remove the entire node (single value) or filter out the specific value from the set.

**Divergences:**

- **None found**: Logic is functionally identical.

**Action items:**
- **MUST FIX**: Change Searchlight's AVL tree creation for number fields to match Orama's initial root node with key=0: `AVLTree<num, int>(key: 0, values: [])`.

---

## D. BKD Tree

### Haversine formula
Both implementations:
1. Convert degrees to radians: `P = PI / 180`
2. Compute `deltaLat`, `deltaLon`
3. Standard Haversine `a = sin^2(dLat/2) + cos(lat1)*cos(lat2)*sin^2(dLon/2)`
4. `c = 2 * atan2(sqrt(a), sqrt(1-a))`
5. `EARTH_RADIUS * c`

**Divergences:**

- **Earth radius constant: Both use `6371e3`**: ACCEPTABLE -- Identical.

### Vincenty formula
Both implementations use the same WGS84 ellipsoid constants and iterative calculation.

**Divergences:**

- **Constants: Both use `a=6378137`, `f=1/298.257223563`, `b=(1-f)*a`**: ACCEPTABLE -- Identical.
- **Iteration limit: Both use `1000`**: ACCEPTABLE -- Identical.
- **Convergence threshold: Both use `1e-12`**: ACCEPTABLE -- Identical.
- **NaN handling: Orama returns `NaN`; Searchlight returns `double.nan`**: ACCEPTABLE -- Same value.

### searchByRadius
Both use stack-based traversal of all tree nodes, computing distance and filtering by radius.

**Divergences:**

- **Default sort: Orama defaults `sort='asc'`; Searchlight defaults `sort=SortOrder.asc`**: ACCEPTABLE -- Same default.

### searchByPolygon
Both use stack-based traversal with ray-casting point-in-polygon test.

**Divergences:**

- **Default sort: Orama defaults `sort=null`; Searchlight defaults `sort=null` (via named parameter)**: ACCEPTABLE -- Identical.

### isPointInPolygon (ray casting)
Both implementations use the same ray-casting algorithm with identical logic.

**Divergences:**

- **None found**: Line-for-line equivalent.

### calculatePolygonCentroid
Both use the same shoelace formula with identical math.

**Divergences:**

- **None found**: Line-for-line equivalent.

### convertDistanceToMeters
Orama (utils.ts): `distance * ratio` where `cm: 0.01, m: 1, km: 1000, ft: 0.3048, yd: 0.9144, mi: 1609.344`
Searchlight: switch-case with `cm: distance / 100, m: distance, km: distance * 1000, mi: distance * 1609.344, yd: distance * 0.9144, ft: distance * 0.3048`

**Divergences:**

- **cm conversion: Orama `distance * 0.01` vs Searchlight `distance / 100`**: ACCEPTABLE -- Mathematically identical.

**Action items:** None.

---

## E. Index Manager

### create() -- schema type to tree type mapping
Orama (`index.ts:138-212`):
- `'boolean'` / `'boolean[]'` -> `Bool` node
- `'number'` / `'number[]'` -> `AVL` tree (initialized with key=0)
- `'string'` / `'string[]'` -> `Radix` tree + BM25 structures
- `'enum'` / `'enum[]'` -> `Flat` tree
- `'geopoint'` -> `BKD` tree

Searchlight (`index_manager.dart:565-643`):
- `SchemaType.boolean` / `booleanArray` -> `Bool` node
- `SchemaType.number` / `numberArray` -> `AVL` tree (initialized empty)
- `SchemaType.string` / `stringArray` -> `Radix` tree + BM25 structures
- `SchemaType.enumType` / `enumArray` -> `Flat` tree
- `SchemaType.geopoint` -> `BKD` tree

**Divergences:**

- **AVL initialization**: See C above. MUST FIX.

- **Orama's `isArray` detection uses regex `/\[/`; Searchlight uses explicit enum matching**: ACCEPTABLE -- Same result, type-safe approach.

### insertDocument -- per-type dispatch

**Divergences:**

- **Orama calls `insertDocumentScoreParameters` inside `insertScalarBuilder` for Radix (once per scalar value); Searchlight now applies BM25 score bookkeeping once per `string[]` property using all array tokens**: HARDENED DIVERGENCE -- Current Orama behavior overwrites `avgFieldLength` and `fieldLengths` per array element, and its remove path repeats the same per-element bookkeeping. Searchlight intentionally diverges here to keep BM25 metadata consistent on both insert and remove for `string[]` fields. This changes relevance scoring relative to current Orama, but avoids corrupted stats after deletions.

- **Orama passes `false` for `withCache` in Radix insert tokenization (`tokenizer.tokenize(value, language, prop, false)`); Searchlight does not pass `withCache: false`**: NEEDS REVIEW -- Orama explicitly disables the normalization cache during indexing by passing `false`. Searchlight uses the default `withCache: true`. This means Searchlight's index-time tokenization uses cached results, which is correct for repeated tokens but diverges from Orama's explicit no-cache behavior during insert. The functional impact is minimal since the cache would return the same result, but it could cause subtle differences if the cache state matters for correctness.

### BM25 parameter maintenance
Both track: `avgFieldLength`, `fieldLengths`, `frequencies`, `tokenOccurrences`.

**Divergences:**

- **`insertDocumentScoreParameters` uses `docsCount` parameter in Orama vs `_docsCount` field in Searchlight**: ACCEPTABLE -- Both reflect the current document count. Orama passes it as a parameter; Searchlight reads from the instance field.

- **`tokenOccurrences` document frequency hardening**: HARDENED DIVERGENCE -- Orama increments `tokenOccurrences[prop][token]` once per token emission during insert and decrements once per emission during remove. That means repeated tokens in a single document can inflate BM25 `matchingCount`, including for duplicates spread across `string[]` elements. Searchlight now increments and decrements `tokenOccurrences` once per unique token per document while still computing TF from the full token stream. This intentionally diverges from Orama so BM25 IDF reflects document frequency instead of raw term repetitions inside one document.

- **`removeDocumentScoreParameters` -- Orama sets `avgFieldLength[prop] = undefined` when docsCount==1; Searchlight sets to `0`**: NEEDS REVIEW -- When removing the last document, Orama sets avgFieldLength to `undefined` (which becomes `NaN` in subsequent calculations). Searchlight sets it to `0`. This only matters when the index goes from 1 to 0 documents and then gets queried or has new documents inserted. Setting to 0 is arguably more correct and prevents NaN propagation, but diverges from Orama.

- **`removeDocumentScoreParameters` -- Orama sets `fieldLengths[prop][internalId] = undefined` and `frequencies[prop][internalId] = undefined`; Searchlight removes the keys**: ACCEPTABLE -- Dart doesn't have `undefined`. Removing the key is the correct Dart equivalent since lookups on missing keys return `null`.

### removeDocument
Both iterate searchable properties, resolve values, and dispatch per type.

**Divergences:**

- **None beyond the scoring parameter differences noted above**: ACCEPTABLE.

### search() (tokenize -> find -> score -> threshold)
Both follow the same flow:
1. Tokenize the search term
2. For each property, for each token, find in the radix tree
3. Calculate BM25 scores per matching document
4. Apply threshold filtering

**Divergences:**

- **Orama throws `WRONG_SEARCH_PROPERTY_TYPE` for non-Radix properties; Searchlight silently `continue`s**: NEEDS REVIEW -- If a non-string property somehow ends up in `propertiesToSearch`, Orama throws while Searchlight silently skips it. The database layer validates properties before calling search, so this is a defense-in-depth difference.

- **Orama throws `INVALID_BOOST_VALUE` for boost <= 0; Searchlight does not validate boost values**: NEEDS REVIEW -- Missing validation for zero or negative boost values.

- **Threshold filtering logic matches**: Both implement the same three-case logic: threshold=1 returns all, threshold=0 requires all keywords, partial threshold returns full matches + percentage of remaining. ACCEPTABLE.

**Action items:**
- **MUST FIX (or document)**: AVL tree initialization for number fields.
- **NEEDS REVIEW**: String array BM25 scoring divergence -- verify if Searchlight's combined-tokens approach produces meaningfully different scores.
- **NEEDS REVIEW**: Missing boost value validation.

---

## F. BM25 Scoring

### Formula
Orama (`algorithms.ts:116-126`):
```
idf = log(1 + (docsCount - matchingCount + 0.5) / (matchingCount + 0.5))
return (idf * (d + tf * (k + 1))) / (tf + k * (1 - b + (b * fieldLength) / averageFieldLength))
```

Searchlight (`scoring/bm25.dart:45-52`):
```dart
idf = log(1 + (docsCount - matchingCount + 0.5) / (matchingCount + 0.5))
return (idf * (params.d + tf * (params.k + 1))) / (tf + params.k * (1 - params.b + (params.b * fieldLength) / averageFieldLength))
```

**Divergences:**

- **None**: Formula is identical.

### Defaults
Orama (`search-fulltext.ts:254-258`): `k=1.2, b=0.75, d=0.5`
Searchlight (`scoring/bm25.dart:14`): `k=1.2, b=0.75, d=0.5`

**Divergences:**

- **None**: Defaults are identical.

**Action items:** None.

---

## G. prioritizeTokenScores

### 1.5x multi-match multiplier
Orama (`algorithms.ts:25-33`):
```ts
if (oldScore !== undefined) {
  tokenScoresMap.set(token, [oldScore * 1.5 + boostScore, ...])
}
```

Searchlight (`scoring/algorithms.dart:37-43`):
```dart
if (existing != null) {
  tokenScoresMap[token] = (existing.$1 * 1.5 + boostScore, existing.$2 + 1);
}
```

**Divergences:**

- **None**: The 1.5x multiplier logic is identical.

### Threshold filtering
Both implement the same three-tier logic:
1. `threshold == 1`: return all results
2. `threshold == 0, keywordsCount == 1`: return all results
3. Otherwise: Sort by keyword count descending, then by score. Find `lastTokenWithAllKeywords`, slice based on threshold percentage.

**Divergences:**

- **None**: The threshold calculation `lastTokenWithAllKeywords + ceil(threshold * 100 * (allResults - lastTokenWithAllKeywords) / 100)` is identical in both.

**NOTE**: The `prioritizeTokenScores` function in Searchlight exists but is NOT called in the current search flow. Searchlight's `SearchIndex.search()` handles threshold filtering directly within the search method, while Orama's `search-fulltext.ts` also handles it directly within `index.search()`. The `prioritizeTokenScores` function appears to be unused dead code in Searchlight that was ported for completeness. This is not a divergence since the threshold logic in `SearchIndex.search()` matches Orama's `index.search()`.

**Action items:** Consider removing `prioritizeTokenScores` if it's dead code, or document why it exists.

---

## H. Filters (searchByWhereClause)

### Logical operators (and/or/not)

**Divergences:**

- **AND**: Orama uses `setIntersection(...results)`; Searchlight uses `_setIntersection(results)`. Both compute the intersection of all sub-filter results. ACCEPTABLE.

- **OR**: Orama uses `results.reduce((acc, set) => setUnion(acc, set), new Set())`; Searchlight uses `results.reduce((acc, s) => acc.union(s))`. ACCEPTABLE -- Same result.

- **NOT**: Orama builds `allDocs` from `docsStore.internalIdToId.length`; Searchlight builds from `1..totalDocs`. NEEDS REVIEW -- Orama iterates `i = 1; i <= docsStore.internalIdToId.length`, which represents all documents ever allocated (including deleted ones that still have entries in the ID store). Searchlight uses `1..totalDocs` where `totalDocs = _nextInternalId - 1`, which also includes all ever-allocated IDs since `_nextInternalId` is never decremented. ACCEPTABLE -- Functionally equivalent since both use the same ID space.

### Per-type dispatch

**Divergences:**

- **Bool filter: Orama evaluates `operation ? idx.true : idx.false` (JS truthiness); Searchlight requires `EqFilter` with explicit `bool` value**: ACCEPTABLE -- Dart's type system makes the API more explicit. Same behavior for `true`/`false` values.

- **Radix (string) filter: Orama supports string/array where-clause filters on Radix fields by tokenizing and finding exact matches; Searchlight throws `QueryException`**: MUST FIX -- Orama's `searchByWhereClause` handles `type === 'Radix'` with string values by tokenizing the filter value and performing exact find operations on the radix tree. Searchlight throws an error saying "String fields cannot be used in where filters." This is a missing feature.

- **Flat filter: Orama determines array vs scalar operations via `isArray` flag; Searchlight uses the same pattern with `indexTree.isArray`**: ACCEPTABLE.

- **AVL filter: Both support gt, gte, lt, lte, eq, between**: ACCEPTABLE.

- **BKD filter: Both support radius and polygon**: ACCEPTABLE.

- **Multiple operation keys: Orama throws `INVALID_FILTER_OPERATION` when `operationKeys.length > 1`; Searchlight uses sealed class pattern so this is handled at the type level**: ACCEPTABLE -- Dart's sealed class prevents multiple operation keys by design.

**Action items:**
- **MUST FIX**: Implement Radix (string) field where-clause filtering to match Orama.

---

## I. Facets

### String facet computation
Orama: Per-document counting with sort and slice: `Object.entries(values).sort(predicate).slice(offset, limit)`
Searchlight: Same approach with `sorted.skip(offset).take(limit)`

**Divergences:**

- **Orama `slice(offset, limit)` takes start and end index; Searchlight `skip(offset).take(limit)` takes offset and count**: MUST FIX -- Orama's `slice(stringFacetDefinition.offset ?? 0, stringFacetDefinition.limit ?? 10)` uses `offset` as start index and `limit` as end index (not count). This means with `offset=2, limit=5`, Orama returns items at indices 2,3,4 (3 items), while Searchlight returns 5 items starting at offset 2. The Orama behavior treats `limit` as an end-index, not a page size. **Wait** -- re-reading Orama's code: `slice(stringFacetDefinition.offset ?? 0, stringFacetDefinition.limit ?? 10)`. With defaults, this is `slice(0, 10)` = first 10 items. With `offset=2, limit=10`, it's `slice(2, 10)` = items 2-9 (8 items). Searchlight with `skip(2).take(10)` returns 10 items starting at position 2. These produce different results when both offset and limit are non-default. MUST FIX.

- **Orama sorts only string facets by count; Searchlight also only sorts string facets by count**: ACCEPTABLE.

### Number facet computation
Both use the same range-bucketing logic: for each value, check if it falls in each range and increment the bucket count.

**Divergences:**

- **Orama pre-initializes number ranges with 0 counts; Searchlight does not pre-initialize**: NEEDS REVIEW -- Orama creates `values = Object.fromEntries(ranges.map(r => ['from-to', 0]))` before counting, ensuring all ranges appear in the output even if empty. Searchlight only creates range keys when values match, so empty ranges are absent from the output. This is a behavioral divergence in facet output shape.

- **Orama uses `alreadyInsertedValues` Set for array types to prevent double-counting within a single document; Searchlight does not**: MUST FIX -- For `number[]` and `string[]`/`boolean[]`/`enum[]` array fields, Orama tracks `alreadyInsertedValues` per document to ensure a value is only counted once per document per facet range. Searchlight counts each array element independently, which can lead to over-counting. For example, a document with `tags: ["a", "a"]` would count "a" twice in Searchlight but only once in Orama.

### Boolean facet computation
Both convert to string (`"true"` / `"false"`) and count.

**Divergences:**

- **None**: Identical.

**Action items:**
- **MUST FIX**: Fix facet `offset`/`limit` semantics to match Orama's `slice(offset, limit)` behavior.
- **MUST FIX**: Implement `alreadyInsertedValues` deduplication for array-type facets.
- **NEEDS REVIEW**: Pre-initialize empty number range buckets.

---

## J. Groups

### Grouping logic
Orama (`groups.ts`): Supports multiple `properties` for multi-property grouping with Cartesian product combinations. Uses `reduce` function for custom aggregation.
Searchlight (`grouping.dart`): Supports single `field` grouping only. Uses direct document-to-group mapping.

**Divergences:**

- **Multi-property grouping: Orama supports `properties: string[]` with Cartesian product of values; Searchlight supports single `field: String`**: MUST FIX -- Orama's grouping can combine multiple properties (e.g., group by both `category` AND `status`), producing groups for each combination. Searchlight only supports grouping by a single field.

- **Custom reduce function: Orama supports `reduce` parameter for custom aggregation; Searchlight does not**: NEEDS REVIEW -- Orama's `getGroups` accepts a `reduce` parameter that allows custom aggregation of grouped results. Searchlight's grouping always returns the full list of `SearchHit` objects per group. Missing feature but low priority for v1.

- **Orama `maxResult` from `groupBy.maxResult`; Searchlight `maxResult` from `groupBy.limit`**: ACCEPTABLE -- Different naming, same concept.

- **Orama validates that group properties exist and are of allowed types (`string`, `number`, `boolean`); Searchlight does not validate**: NEEDS REVIEW -- Missing validation could lead to runtime errors on invalid property types.

**Action items:**
- **MUST FIX**: Add multi-property grouping support.
- **NEEDS REVIEW**: Add group property validation.

---

## K. Sorter

### Insert-time indexing
Orama: Creates `PropertySort` per sortable field (string, number, boolean). On insert, appends to `orderedDocs` array and records position in `docs` map. Uses lazy deletion with `orderedDocsToRemove`.

Searchlight: Same approach with `_PropertySort`. On insert, appends `(docId, value)` to `orderedDocs` and records position in `docs`. Uses lazy deletion with `orderedDocsToRemove`.

**Divergences:**

- **Orama sorts globally when any property is accessed (`ensureIsSorted` iterates all properties); Searchlight sorts per-property on demand**: NEEDS REVIEW -- Orama's `ensureIsSorted` marks a global `isSorted` flag and sorts ALL properties when first accessed. Searchlight's `_ensurePropertyIsSorted` sorts only the requested property. This means Orama may do more work upfront but ensures all properties are sorted together. Searchlight is lazier but functionally equivalent for the property being sorted on.

- **String sort: Orama uses `localeCompare(a, b, locale)` with language locale; Searchlight uses `compareTo` without locale**: NEEDS REVIEW -- Orama's string sorting is locale-aware (e.g., German umlauts sort correctly), while Searchlight's `String.compareTo` uses lexicographic ordering. This can produce different sort orders for non-ASCII strings.

- **Boolean sort: Orama's `booleanSort` returns `d[1] ? -1 : 1`; Searchlight now returns `0` for equal values before ordering `false < true`**: HARDENED DIVERGENCE -- The previous Searchlight comparator matched Orama's ordering for unequal booleans, but violated the comparator contract for equal pairs (`false,false` and `true,true`). Searchlight now intentionally hardens this by returning `0` for equality so repeated sorts remain deterministic for duplicate boolean values.

### sortBy with asc/desc
Both use position-based sorting: look up each document's position in the sorted `orderedDocs` array, then compare positions with optional inversion for descending.

**Divergences:**

- **Orama operates on `[DocumentID, number][]` (external IDs); Searchlight operates on `List<TokenScore>` (internal IDs)**: ACCEPTABLE -- Searchlight uses internal IDs consistently, converting at the database layer.

- **Unindexed documents sorting**: Both place unindexed documents at the end. ACCEPTABLE.

**Action items:**
- **NEEDS REVIEW**: Consider adding locale-aware string sorting for sort index.

---

## L. Highlighter

Orama's highlighter is in a separate package (`@orama/highlight`) not directly in the core search code. Searchlight has its own implementation.

**Divergences:**

- **This is a Searchlight-specific implementation**: ACCEPTABLE -- Since `@orama/highlight` is a separate package and not part of the core search flow, Searchlight's highlight implementation is an independent feature. The core search flow in Orama does not call the highlighter.

**Action items:** None -- the highlighter is not part of the core Orama search flow.

---

## M. Full Search Flow (database.dart search())

### Orama flow (`search-fulltext.ts` + `innerFullTextSearch`):
1. Resolve properties: filter to string-type properties, validate requested properties
2. Evaluate `where` filters -> `whereFiltersIDs`
3. If term or properties: call `index.search()` with threshold (default=1)
4. If no term + filters: check for geo-only query with distance scoring, else return filtered IDs with score 0
5. If no term + no filters: return all document IDs with score 0
6. Apply sortBy (function or field-based) or default sort by score
7. Apply pinning rules
8. Paginate with `offset` and `limit` (default: offset=0, limit=10)
9. Fetch documents for the page
10. Compute facets on full result set
11. Compute groups on full result set
12. Return `{ hits, count, elapsed, facets?, groups? }`

### Searchlight flow (`database.dart search()`):
1. Resolve properties: filter to string-type properties, validate requested properties
2. Evaluate `where` filters -> `whereFiltersIDs`
3. If term is not empty: call `_index.search()` with threshold (default=1.0)
4. If term is empty + filters: return filtered IDs with score 0
5. If term is empty + no filters: return all document IDs with score 0
6. Apply sortBy or default sort by score
7. Total count before pagination
8. Paginate with `offset` and `limit` (default: offset=0, limit=10)
9. Fetch documents for the page
10. Compute facets on full result set
11. Compute groups on full result set
12. Return `SearchResult(hits, count, elapsed, facets?, groups?)`

**Divergences:**

- **Default threshold: Orama defaults to `1` (see `search-fulltext.ts:69`); Searchlight defaults to `1.0` (see `database.dart:518`)**: ACCEPTABLE -- Same value.

- **Orama checks `if (term || properties)` to decide whether to search; Searchlight checks `if (term.isNotEmpty)`**: NEEDS REVIEW -- In Orama, passing `properties` without a `term` still triggers `index.search()`, which returns results based on the empty token `['']` pushed when `tokens.length === 0 && !term`. In Searchlight, an empty string `term` skips the search entirely. However, looking at Orama more carefully: `term || ''` is always truthy for the empty string path, and the condition `if (term || properties)` would be `false` only when `term` is `undefined`/`null`/`''` AND `properties` is `undefined`/`null`. In practice, Orama's `fullTextSearch` always calls `innerFullTextSearch` which has `term` defaulting to `''`. So when `term=''` and `properties=undefined`, Orama goes to the else branch (all docs with score 0). When `term=''` and `properties=['title']`, Orama searches. Searchlight always goes to the else branch when `term.isEmpty`. MUST FIX -- Searchlight does not handle the case where `properties` is specified without a term (should trigger the search path to return matching property documents).

- **Geo-only query with distance scoring: Orama has `searchByGeoWhereClause` that creates scored results for geo-only queries; Searchlight does not**: NEEDS REVIEW -- When the only filter is a geo filter and there's no text search term, Orama produces results with distance-based scores (closer = higher score). Searchlight returns geo-filtered results with score 0. This affects result ordering for geo-only queries.

- **Exact term post-filtering: Orama has post-search exact-term filtering (`if (params.exact && term)`) that checks original document text for case-sensitive whole-word matches; Searchlight does not**: NEEDS REVIEW -- This is a newer Orama feature that adds an additional filter after scoring. Missing from Searchlight, but this appears to be a recently-added Orama enhancement.

- **Pinning rules: Orama applies `applyPinningRules` after sorting; Searchlight does not have pinning**: ACCEPTABLE -- Pinning is a separate feature not in scope for Phase 2.

- **distinctOn: Orama supports `distinctOn` parameter for deduplication; Searchlight does not**: ACCEPTABLE -- Not in scope for Phase 2.

- **Default limit=10, offset=0 in both**: ACCEPTABLE -- Identical.

**Action items:**
- **MUST FIX**: Handle the case where `properties` is specified without a search `term` (should trigger search, not return all docs).
- **NEEDS REVIEW**: Consider implementing geo-only distance scoring.
- **NEEDS REVIEW**: Consider implementing exact-term post-filtering.

---

## Summary Table: All MUST FIX Items

| # | Area | Description | Impact |
|---|------|-------------|--------|
| 1 | C (AVL Tree) | AVL tree for number fields initialized empty instead of with root key=0 | Tree structure divergence for all number field indexes; affects insertion order and BM25 scoring edge cases |
| 2 | H (Filters) | Radix (string) field where-clause filtering not implemented; Searchlight throws instead | Users cannot filter on string fields using where-clauses |
| 3 | I (Facets) | Facet `offset`/`limit` semantics diverge from Orama's `slice(offset, limit)` | Incorrect pagination of string facet values when offset > 0 |
| 4 | I (Facets) | Missing `alreadyInsertedValues` deduplication for array-type facets | Over-counting of duplicate values in array fields |
| 5 | J (Groups) | Only single-field grouping supported; Orama supports multi-property grouping | Missing feature for multi-dimensional grouping |
| 6 | M (Search Flow) | Empty term with explicit `properties` does not trigger search path | Divergent behavior when searching specific properties without a term |

## Summary Table: All NEEDS REVIEW Items

| # | Area | Description | Risk |
|---|------|-------------|------|
| 1 | A (Tokenizer) | Searchlight provides Snowball stemmers for all languages; Orama only has English built-in | Different stemming results for non-English languages |
| 2 | A (Tokenizer) | Missing language parameter validation in tokenize() | Low -- defense-in-depth only |
| 3 | E (Index Manager) | String array BM25 scoring: Searchlight intentionally hardens metadata updates while Orama overwrites per-element | Different relevance scores from current Orama, but avoids corrupted BM25 stats |
| 4 | E (Index Manager) | Orama disables normalization cache during insert; Searchlight uses cache | Minimal impact -- cache returns same result |
| 5 | E (Index Manager) | avgFieldLength set to 0 vs undefined when last doc removed | Edge case when index empties and refills |
| 6 | E (Index Manager) | Missing boost value validation (boost <= 0) | Could produce incorrect scores silently |
| 7 | K (Sorter) | Boolean comparator returns `0` for equality instead of mirroring Orama's contract violation | Intentional hardening for deterministic duplicate-boolean sorts |
| 8 | E (Index Manager) | Non-Radix property in search: Orama throws, Searchlight skips | Defense-in-depth difference |
| 9 | H (Filters) | NOT filter all-docs set construction | Functionally equivalent but uses different source |
| 10 | I (Facets) | Number ranges not pre-initialized with 0 counts | Missing empty ranges in output |
| 11 | J (Groups) | Missing custom reduce function for group aggregation | Feature gap, low priority for v1 |
| 12 | J (Groups) | Missing group property type validation | Could cause runtime errors |
| 13 | K (Sorter) | String sort not locale-aware | Different sort order for non-ASCII strings |
| 14 | M (Search Flow) | Geo-only queries return score 0 instead of distance-based scores | Affects ordering of geo-only results |
| 14 | M (Search Flow) | Missing exact-term post-filtering for case-sensitive whole-word matching | Feature gap, recently added to Orama |
