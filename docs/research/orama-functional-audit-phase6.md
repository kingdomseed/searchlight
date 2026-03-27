# Orama Functional Equivalence Audit: Phase 6

**Date:** 2026-03-25
**Scope:** QPS algorithm, PT15 algorithm, algorithm selection (index manager), where-clause filtering, PT15 limitations, reindex
**Ground truth:** Orama TypeScript source (`plugin-qps`, `plugin-pt15`)
**Implementation:** Searchlight Dart (`scoring/qps.dart`, `scoring/pt15.dart`, `indexing/index_manager.dart`, `core/database.dart`, `search/filters.dart`)

---

## A: QPS Algorithm

### A1: `calculateTokenQuantum`

**Orama** (`algorithm.ts:78-90`):
```ts
const currentCount = count(prevValue)
const currentSentenceMask = bitmask_20(prevValue)
const newSentenceMask = currentSentenceMask | (1 << bit)
return ((currentCount + 1) << 20) | newSentenceMask
```

**Searchlight** (`qps.dart:38-43`):
```dart
final currentCount = countFromPacked(prevValue);
final currentSentenceMask = bitmask20(prevValue);
final newSentenceMask = currentSentenceMask | (1 << bit);
return ((currentCount + 1) << 20) | newSentenceMask;
```

**Divergences:**
- Function/helper naming (`count` -> `countFromPacked`, `bitmask_20` -> `bitmask20`): **ACCEPTABLE** -- Dart naming conventions
- Bit packing formula is identical: **ACCEPTABLE**

### A2: `insertString`

**Orama** (`algorithm.ts:92-131`):
- Splits on `/\.|\?|!/` (sentence boundaries)
- Iterates sentences, tokenizes each
- Tracks `quantumIndex`, `tokenNumber`
- `tokenBitIndex = Math.min(quantumIndex, 20)`
- Calls `calculateTokenQuantum(stats.tokenQuantums[internalId][token], tokenBitIndex)` -- passes `undefined` for new tokens (JS coerces to 0)
- `stats[token] = 0` (line 111-113) -- sets an unused top-level property on the stats object
- Increments `quantumIndex` only if `tokens.length > 1`
- Sets `stats.tokensLength.set(internalId, tokenNumber)`

**Searchlight** (`qps.dart:77-117`):
- Splits on `RegExp('[.?!]')` -- equivalent regex
- Same iteration structure
- Caps `tokenBitIndex` at `19` so overflowed sentences saturate into the last
  representable bit bucket
- Passes `stats.tokenQuantums[internalId]![token] ?? 0` -- explicit null coalescion, functionally identical to JS undefined-to-0
- Omits the `stats[token] = 0` line -- this is dead code in Orama (unused state)
- Same `quantumIndex` increment guard (`tokens.length > 1`)
- Same `tokensLength[internalId] = tokenNumber`

**Divergences:**
- Regex syntax (`/\.|\?|!/` vs `RegExp('[.?!]')`): **ACCEPTABLE** -- both split on `.`, `?`, `!` characters. The Orama regex uses alternation; the Dart uses a character class. Functionally equivalent.
- Quantum overflow saturation (`19` vs Orama's `20`): **HARDENED DIVERGENCE** -- Orama's `Math.min(quantumIndex, 20)` writes the 21st sentence into bit `20`, which is outside the packed 20-bit mask and gets discarded by `bitmask_20`. Searchlight intentionally caps at `19` so late sentences still contribute to proximity scoring.
- `?? 0` vs implicit JS `undefined`-to-`0` coercion: **ACCEPTABLE** -- explicit null safety in Dart
- Omission of `stats[token] = 0`: **ACCEPTABLE** -- this is dead code in Orama; it sets an ad-hoc property on the stats object that is never read by `searchString` or `removeString`
- `string[]` insertion overwrites `tokensLength` per array element in both implementations: **ACCEPTABLE** -- Searchlight's `_insertQpsStringArray` calls `qpsInsertString` once per element, and each call stores only that element's `tokenNumber`. Orama's QPS plugin does the same. This is a parity sharp edge rather than a Searchlight-only bug.

### A3: `searchString`

**Orama** (`algorithm.ts:134-211`):
- Receives `prop` object with `tokens`, `radixNode`, `exact`, `tolerance`, `stats`, `boostPerProp`, `resultMap`, `whereFiltersIDs`
- Iterates tokens, calls `radixNode.find({ term, exact, tolerance })`, merges results with spread
- For each found key/doc pair: `numberOfQuantums = tokensLength.get(docId)!`
- `occurrence = count(tokenQuantumDescriptor)`
- `bitMask = bitmask_20(tokenQuantumDescriptor)`
- Score: `((occurrence * occurrence) / numberOfQuantums + (isExactMatch ? 1 : 0)) * boostPerProp`
- Proximity: `current[0] + numberOfOnes(current[1] & bitMask) * 2 + score`
- Updates combined bitmask: `current[1] = current[1] | bitMask`
- Uses `Map<number, [number, number]>` (mutable tuple)

**Searchlight** (`qps.dart:128-183`):
- Same parameter set (named parameters instead of object)
- Same token iteration and `radixNode.find` call
- Same score formula: `((occurrence * occurrence) / numberOfQuantums + (isExactMatch ? 1 : 0)) * boostPerProp`
- Same proximity: `current.$1 + numberOfOnes(current.$2 & bitMask) * 2 + score`
- Same combined bitmask update: `current.$2 | bitMask`
- Uses `Map<int, (double, int)>` (Dart record)

**Divergences:**
- Orama mutates the tuple in-place (`current[0] = totalScore`); Searchlight creates a new record (`resultMap[docId] = (totalScore, ...)`) : **ACCEPTABLE** -- Dart records are immutable; the replacement achieves the same result
- Orama passes `tolerance` directly to `find`; Searchlight passes `tolerance > 0 ? tolerance : null`: **ACCEPTABLE** -- RadixNode.find interprets `null` tolerance as "no fuzzy", matching Orama's behavior when tolerance is 0
- Score uses `double` in Dart vs `number` in TS: **ACCEPTABLE** -- Dart type system

### A4: `removeString`

**Orama** (`algorithm.ts:231-254`):
- Tokenizes value, iterates tokens
- Calls `radixTree.removeDocumentByWord(token, internalId, true)` -- passes `true` for exact
- Deletes `tokensLength` and `tokenQuantums` entries

**Searchlight** (`qps.dart:192-209`):
- Same tokenization
- Calls `radixTree.removeDocumentByWord(token, internalId)` -- default `exact: true`
- Same cleanup of `tokensLength` and `tokenQuantums`

**Divergences:**
- `exact: true` default vs explicit `true` argument: **ACCEPTABLE** -- same behavior

### A5: `numberOfOnes` (popcount)

**Orama** (`algorithm.ts:220-229`):
```ts
let i = 0
do {
  if (n & 1) { ++i }
} while ((n >>= 1))
return i
```

**Searchlight** (`qps.dart:58-68`):
```dart
var count = 0;
var value = n;
while (value != 0) {
  if (value & 1 == 1) { count++; }
  value >>= 1;
}
return count;
```

**Divergences:**
- `do...while` vs `while`: **ACCEPTABLE** -- The only difference is behavior when `n = 0`. Orama's `do...while` enters the loop once but `0 & 1 == 0` so `i` stays 0, then `(n >>= 1)` evaluates to `0` (falsy), loop exits, returns 0. Searchlight's `while (value != 0)` skips entirely, returns 0. Both return 0 for input 0. For all positive integers, behavior is identical.

### A6: Bit operations

**Divergences:**
- `BIT_MASK_20 = 0b11111111111111111111` vs `bitMask20Value = 0xFFFFF`: **ACCEPTABLE** -- same value (1048575), different literal format
- All shift, AND, OR operations are identical in semantics between Dart and TypeScript for the value ranges used (20-bit masks, counts well within safe integer range)

**Action items:** None.

---

## B: PT15 Algorithm

### B1: `getPosition` / `get_position`

**Orama** (`algorithm.ts:157-163`):
```ts
if (totalLength < MAX_POSITION) { return n }
return Math.floor((n * MAX_POSITION) / totalLength)
```

**Searchlight** (`pt15.dart:35-40`):
```dart
if (totalLength < maxPosition) { return n; }
return (n * maxPosition) ~/ totalLength;
```

**Divergences:**
- `Math.floor` vs `~/` (truncating integer division): **ACCEPTABLE** -- equivalent for non-negative operands (which is always the case here since `n >= 0` and `totalLength > 0`)
- `MAX_POSITION` vs `maxPosition`: **ACCEPTABLE** -- Dart naming convention

### B2: MAX_POSITION

**Orama:** `const MAX_POSITION = 15`
**Searchlight:** `const maxPosition = 15`

**Divergences:**
- Naming convention only: **ACCEPTABLE**

### B3: `insertString`

**Orama** (`algorithm.ts:132-155`):
- Tokenizes value
- For each token at index `i`: `position = MAX_POSITION - get_position(i, tokensLength) - 1`
- For each prefix length `j` from `tokenLength` down to `1`: stores `token.slice(0, j)` -> pushes `internalId`
- Uses `positionStorage[tokenPart] = positionStorage[tokenPart] || []` then `.push(internalId)`

**Searchlight** (`pt15.dart:46-68`):
- Same tokenization
- Same position calc: `maxPosition - getPosition(i, tokensLength) - 1`
- Same prefix loop: `j` from `token.length` down to `1`, `token.substring(0, j)`
- Uses `(positionStorage[tokenPart] ??= []).add(internalId)`

**Divergences:**
- `slice` vs `substring`: **ACCEPTABLE** -- equivalent for these parameters (0 to j, no negative indices)
- `|| []` + `.push` vs `??= []` + `.add`: **ACCEPTABLE** -- Dart idiom, same semantics

### B4: `searchString`

**Orama** (`algorithm.ts:165-199`):
- Tokenizes term (no language/prop passed)
- Returns `Map<number, number>`
- Iterates 15 buckets, checks `positionStorage[token]`, accumulates `score += i * boostPerProp`
- Filters by `whereFiltersIDs`

**Searchlight** (`pt15.dart:78-104`):
- Same tokenization pattern
- Returns `Map<int, double>`
- Same 15-bucket iteration
- Same score formula: `ret[id] = (ret[id] ?? 0) + i * boostPerProp`
- Same `whereFiltersIDs` filtering

**Divergences:**
- `Map<number, number>` vs `Map<int, double>`: **ACCEPTABLE** -- Dart type system (double accommodates boost multiplication)
- Orama uses `Map.has/get/set`; Searchlight uses `[]` operator with `?? 0`: **ACCEPTABLE** -- equivalent semantics

### B5: `removeString`

**Orama** (`algorithm.ts:201-229`):
- Tokenizes, recalculates position for each token
- For each prefix: finds index with `indexOf`, removes with `splice`

**Searchlight** (`pt15.dart:110-138`):
- Same tokenization and position recalculation
- For each prefix: finds index with `indexOf`, removes with `removeAt`

**Divergences:**
- `splice(index, 1)` vs `removeAt(index)`: **ACCEPTABLE** -- equivalent single-element removal

### B6: Multi-property merge logic

**Orama** (`plugin-pt15/index.ts:147-207`):
- Collects `Map<number, number>` per property
- Finds map with largest `.size` (most entries)
- If single map, converts to array directly
- Merges all other maps into the largest base map by summing scores

**Searchlight** (`pt15.dart:149-199`):
- Same collection of per-property maps
- Finds map with largest `.length`
- Same single-map shortcut
- Same merge into largest base map

**Divergences:**
- Orama uses `max.score` (confusingly named, actually tracks `map.size`); Searchlight uses `maxSize`: **ACCEPTABLE** -- clearer naming in Dart
- Orama returns `Array.from(base)` as `[id, score][]`; Searchlight returns `List<TokenScore>` (record list): **ACCEPTABLE** -- type system difference

**Action items:** None.

---

## C: Algorithm Selection (Index Manager)

### C1: String field indexing

**Orama QPS** (`plugin-qps/index.ts:95-107` create, `algorithm.ts:43-73` recursiveCreate):
- String fields: `type: 'Radix'`, `node: new radix.RadixTree()` + `stats[prop]` with `tokenQuantums`/`tokensLength`
- Non-string fields: delegates to standard `Index` (AVL, Bool, Flat, BKD)

**Orama PT15** (`plugin-pt15/algorithm.ts:54-129` recursiveCreate):
- String fields: `type: 'Position'`, `node: [create_obj() x 15]`
- Non-string fields: same standard types

**Searchlight** (`index_manager.dart:837-895` `_buildIndexes`):
- BM25: string -> `TreeType.radix` + RadixTree + BM25 frequency/occurrence data
- QPS: string -> `TreeType.radix` + RadixTree + `QPSStats`
- PT15: string -> `TreeType.position` + `createPositionsStorage()` (15 empty maps)
- Non-string fields: identical across all algorithms (AVL, Bool, Flat, BKD)

**Divergences:**
- Searchlight QPS does not initialize BM25 data (frequencies, tokenOccurrences, avgFieldLength, fieldLengths) for string fields: **ACCEPTABLE** -- matches Orama where QPS's `insertDocumentScoreParameters` throws, meaning BM25 data is never used
- PT15 uses `List.generate(15, ...)` vs Orama's 15 `create_obj()` calls: **ACCEPTABLE** -- same result

### C2: Insert dispatch

**Orama QPS** (`plugin-qps/index.ts:108-153`):
- Non-string: delegates to `Index.insert` (standard)
- String: initializes `stats.tokenQuantums[internalId] = {}`, handles array values, calls `insertString`

**Searchlight** (`index_manager.dart:222-283`):
- `TreeType.radix` + `SearchAlgorithm.qps`: initializes `stats.tokenQuantums[docId] = {}`, calls `qpsInsertString`
- `TreeType.position` (PT15): calls `pt15.insertString`
- Non-string types: standard AVL/Bool/Flat/BKD insert

**Divergences:**
- Array handling in QPS: Orama checks `Array.isArray(value)` and loops; Searchlight handles this at the `_insertScalar` level via the `isArray` check on `IndexTree`: **ACCEPTABLE** -- same behavior, different dispatch point
- Searchlight initializes `stats.tokenQuantums[docId] = {}` before calling `qpsInsertString`, matching Orama's `stats.tokenQuantums[internalId] = {}`: **ACCEPTABLE**

### C3: Search dispatch

**Orama QPS** (`plugin-qps/index.ts:31-81` search):
- Tokenizes term once, iterates properties, calls `searchString` with per-property radix node and stats
- Collects into single `Map`, converts to `[id, score][]`

**Searchlight** (`index_manager.dart:640-694` `_searchQPS`):
- Same: tokenizes once, iterates properties, calls `qpsSearchString` per property
- Collects into single `resultMap`, converts to `List<TokenScore>`, sorts descending

**Orama PT15** (`plugin-pt15/index.ts:147-208` search):
- Validates `tolerance !== 0` throws, `exact === true` throws
- Calls `searchString` per property, collects maps, merges largest

**Searchlight** (`index_manager.dart:700-733` `_searchPT15`):
- Calls `pt15.searchProperties` which does the merge
- Does NOT validate tolerance/exact

**Divergences:**
- QPS search: functionally equivalent: **ACCEPTABLE**
- PT15 search: **missing tolerance/exact validation**: **MUST FIX** -- Orama throws `'Tolerance not implemented yet'` when `tolerance !== 0` and `'Exact not implemented yet'` when `exact === true`. Searchlight silently ignores these parameters because `_searchPT15` does not accept them and the `search` dispatch method does not validate them before calling `_searchPT15`.

### C4: Remove dispatch

**Orama QPS** (`plugin-qps/index.ts:155-192`):
- Non-string: delegates to `Index.remove`
- String: calls `removeString` (handles arrays)

**Orama PT15** (`plugin-pt15/index.ts:93-131`):
- Non-string: delegates to `Index.remove`
- String: calls `removeString` (handles arrays)

**Searchlight** (`index_manager.dart:356-418`):
- `TreeType.radix` + QPS: calls `qpsRemoveString`
- `TreeType.position` (PT15): calls `pt15.removeString`
- Non-string: standard remove

**Divergences:**
- Dispatch structure differs but behavior is equivalent: **ACCEPTABLE**

**Action items:**
1. **MUST FIX**: Add tolerance and exact validation in PT15 search path. When `algorithm == SearchAlgorithm.pt15`, the `search` method (or `_searchPT15`) should throw if `tolerance != 0` or `exact == true`.

---

## D: QPS Where-Clause Filtering

**Orama** (`plugin-qps/index.ts:209-277`):
1. Separates filters into string filters (Radix type) and non-string filters
2. If no string filters, delegates entirely to `Index.searchByWhereClause`
3. For string filters:
   - If filter value is an array: tokenizes each item, takes first token only (`tokenizer.tokenize(item)?.[0]`)
   - If filter value is a string: tokenizes it (gets all tokens)
   - For each token: calls `radixTree.find({ term: token, exact: true })`, looks up `ret[token]` specifically (only exact key)
   - Intersects per-property results across string filters
4. If non-string filters also present: intersects string filter IDs with `Index.searchByWhereClause` results
5. Returns combined intersection

**Searchlight** (`filters.dart:470-495`):
1. Uses a single unified `searchByWhereClause` function for all algorithms
2. For `TreeType.radix` (which QPS string fields use):
   - Only handles `EqFilter` with `String` value
   - Tokenizes the filter value, gets all tokens
   - For each token: calls `node.find(term: t, exact: true)`
   - Iterates over ALL `foundResult.values` (not just the exact key)
   - Unions results into `filtersMap[param]`
3. Intersection across properties happens via the final `_setIntersection` call

**Divergences:**

- **Array filter handling**: Orama QPS handles array filter values (`Array.isArray(filter)`) by tokenizing each item and taking only the first token. Searchlight does not support array filter values for string fields -- it only accepts `EqFilter` with a `String` value: **NEEDS REVIEW** -- If callers never pass array filters on string fields, this is benign. But if Orama's array filter path is exercised (e.g., `where: { title: ['foo', 'bar'] }`), Searchlight would throw an error instead. This may be an edge case not commonly used.

- **Exact key lookup vs all values**: Orama looks up only `ret[token]` (the exact key matching the search token) from the find results. Searchlight iterates over all `foundResult.values`. Since `find` is called with `exact: true`, the result map should only contain exact matches, so the iteration over all values should be equivalent. However, if `RadixNode.find(exact: true)` returns multiple keys (e.g., the token itself plus the token as a word in the tree), this could differ: **NEEDS REVIEW** -- Verify that `RadixNode.find(exact: true)` returns at most the single exact-match key. If it can return multiple keys, Searchlight may include extra document IDs that Orama would not.

- **Non-string filter delegation**: Orama QPS separates string and non-string filters, delegates non-string to `Index.searchByWhereClause`, and intersects. Searchlight's unified function handles all filter types in a single pass and intersects at the end via `_setIntersection`: **ACCEPTABLE** -- Same result: per-property filter sets are intersected. The unified approach correctly handles mixed filter types.

- **Orama passes full `filters` object (including string filters) to `Index.searchByWhereClause` for non-string handling**: This means Orama's standard `searchByWhereClause` would process string filters too, but since they would be `Radix` type, the standard handler would apply its own string filter logic. The QPS plugin then intersects its own string filter results with the standard results. This is subtly different from Searchlight, where the Radix case is handled once: **NEEDS REVIEW** -- In Orama, when there are mixed string + non-string filters, `Index.searchByWhereClause` receives ALL filters (including string ones) and processes non-Radix types while likely ignoring Radix types (since the standard `searchByWhereClause` handles Radix differently). The net behavior should be equivalent, but the double-processing of the filter map is worth verifying.

**Action items:**
1. **NEEDS REVIEW**: Verify whether array filter values on QPS string fields are a supported use case. If so, implement array handling in the Radix filter path.
2. **NEEDS REVIEW**: Verify that `RadixNode.find(exact: true)` returns only the single exact-key entry, making the iteration over all values equivalent to Orama's single-key lookup.
3. **NEEDS REVIEW**: Verify that the unified filter function produces the same results as Orama's split string/non-string approach when mixed filters are present.

---

## E: PT15 Where-Clause Filtering

**Orama** (`plugin-pt15/index.ts:209-226`):
```ts
const stringFiltersList = Object.entries(filters).filter(
  ([propName]) => index.indexes[propName].type === 'Position'
)
if (stringFiltersList.length !== 0) {
  throw new Error('String filters are not supported')
}
return Index.searchByWhereClause(index as Index.Index, tokenizer, filters, language)
```

**Searchlight** (`filters.dart:497-501`):
```dart
case TreeType.position:
  throw QueryException(
    "String filters are not supported for PT15 field '$param'.",
  );
```

**Divergences:**
- Orama checks all filters upfront and throws if any are Position type; Searchlight throws per-field as it encounters a Position-type filter: **ACCEPTABLE** -- same user-facing behavior (error on string filter for PT15). Searchlight's approach is actually stricter since it provides the specific field name in the error message.
- Error message includes field name in Searchlight: **ACCEPTABLE** -- improvement

**Action items:** None.

---

## F: PT15 Limitations

**Orama** (`plugin-pt15/index.ts:160-165`):
```ts
if (tolerance !== 0) {
  throw new Error('Tolerance not implemented yet')
}
if (exact === true) {
  throw new Error('Exact not implemented yet')
}
```

**Searchlight** (`index_manager.dart:499-506`):
```dart
case SearchAlgorithm.pt15:
  return _searchPT15(
    term: term,
    tokenizer: tokenizer,
    propertiesToSearch: propertiesToSearch,
    boost: boost,
    whereFiltersIDs: whereFiltersIDs,
  );
```

The `_searchPT15` method does not accept `exact` or `tolerance` parameters, and the `search` method does not validate them before dispatching to `_searchPT15`.

**Divergences:**
- **Missing tolerance validation**: Searchlight silently ignores `tolerance` for PT15 searches. Orama throws: **MUST FIX**
- **Missing exact validation**: Searchlight silently ignores `exact` for PT15 searches. Orama throws: **MUST FIX**

**Action items:**
1. **MUST FIX**: In `SearchIndex.search()`, before dispatching to `_searchPT15`, add:
   ```dart
   if (tolerance != 0) {
     throw QueryException('Tolerance is not supported for PT15 algorithm.');
   }
   if (exact) {
     throw QueryException('Exact matching is not supported for PT15 algorithm.');
   }
   ```

---

## G: Reindex

**Orama**: Does not have a built-in `reindex` function. The algorithm is selected at creation time via plugin architecture. Switching algorithms requires creating a new Orama instance with a different plugin and re-inserting all documents.

**Searchlight** (`database.dart:795-817`):
```dart
Searchlight reindex({required SearchAlgorithm algorithm}) {
  final newDb = Searchlight.create(
    schema: schema,
    algorithm: algorithm,
    language: language,
  );
  for (final entry in _internalToExternal.entries) {
    final internalId = entry.key;
    final doc = _documents[internalId];
    if (doc == null) continue;
    final data = <String, Object?>{
      ...doc.toMap(),
      'id': entry.value,
    };
    newDb.insert(data);
  }
  return newDb;
}
```

**Divergences:**
- Searchlight provides a convenience `reindex` method that Orama does not have: **ACCEPTABLE** -- This is a Searchlight-specific addition that correctly creates a new instance with the target algorithm, preserves schema/language, and re-inserts all documents with their original external IDs. The original instance is left unmodified. This is the correct approach for algorithm switching and does not conflict with Orama's plugin architecture.
- Document iteration uses `_internalToExternal.entries` which preserves insertion order: **ACCEPTABLE** -- Documents are re-inserted with their original external IDs via `'id': entry.value`

**Action items:** None.

---

## Summary Table

| ID | Area | Issue | Classification | Detail |
|----|------|-------|---------------|--------|
| F1 | F (PT15 Limitations) | Missing `tolerance != 0` validation | **MUST FIX** | Orama throws when tolerance is non-zero for PT15; Searchlight silently ignores it |
| F2 | F (PT15 Limitations) | Missing `exact == true` validation | **MUST FIX** | Orama throws when exact is true for PT15; Searchlight silently ignores it |
| C1 | C (Algorithm Selection) | Same as F1/F2 -- search dispatch | **MUST FIX** | The validation should be added in the `search()` method before dispatching to `_searchPT15` |
| D1 | D (QPS Where-Clause) | Array filter values not handled | **NEEDS REVIEW** | Orama QPS handles `Array.isArray(filter)` on string fields; Searchlight only handles `EqFilter(String)` |
| D2 | D (QPS Where-Clause) | `find(exact: true)` result iteration | **NEEDS REVIEW** | Searchlight iterates all result values; Orama looks up only the exact token key |
| D3 | D (QPS Where-Clause) | Mixed filter delegation | **NEEDS REVIEW** | Orama splits string/non-string and intersects; Searchlight uses unified pass. Verify equivalence with mixed filters. |

### MUST FIX items: 2 (unique; F1/F2 and C1 are the same underlying issue)

Add PT15 tolerance and exact validation in `SearchIndex.search()` before the `_searchPT15` dispatch:
```dart
case SearchAlgorithm.pt15:
  if (tolerance != 0) {
    throw QueryException(
      'Tolerance is not supported for the PT15 algorithm.',
    );
  }
  if (exact) {
    throw QueryException(
      'Exact matching is not supported for the PT15 algorithm.',
    );
  }
  return _searchPT15( ... );
```

### NEEDS REVIEW items: 3

All in the QPS where-clause filtering area (D). These are edge cases in how string filters are processed during `searchByWhereClause` for QPS mode. The core search and scoring paths are functionally equivalent.

### ACCEPTABLE items: All remaining except the explicit hardening in A2

The QPS and PT15 algorithm implementations are functionally equivalent to Orama's TypeScript source except for Searchlight's intentional QPS overflow hardening in A2. Other differences are limited to Dart naming conventions, type system adaptations, and idiomatic Dart patterns.
