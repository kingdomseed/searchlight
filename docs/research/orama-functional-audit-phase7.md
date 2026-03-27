# Phase 7 Functional Equivalence Audit: Serialization & Persistence

**Date:** 2026-03-25
**Scope:** JSON/CBOR serialization, FileStorage, persist/restore
**Ground truth:** Orama TypeScript source (`serialization.ts`, `documents-store.ts`, `internal-document-id-store.ts`, `sorter.ts`, `index.ts`, `plugin-data-persistence/src/index.ts`)

---

> **Update — 2026-03-27:** This audit captured the pre-parity persistence
> implementation. Searchlight now serializes and restores `index` and
> `sorting` component state directly, with reinsertion retained only as a
> compatibility fallback for older snapshots that do not contain those
> payloads. Treat the old A1/A2/B6/C2/C3/C5/D1/H1/I3d notes below as
> historical context, not the current package status. The live source of truth
> is [orama-divergence-ledger.md](orama-divergence-ledger.md).

## A. Save/Load Data Structure

### Orama `save()` returns `RawData`:
```typescript
interface RawData {
  internalDocumentIDStore: unknown  // { internalIdToId: string[] }
  index: unknown                    // full index trees + scoring stats
  docs: unknown                     // { docs: Record<InternalDocumentID, AnyDocument>, count: number }
  sorting: unknown                  // full sorter state
  pinning: unknown                  // pinning rules
  language: Language                // tokenizer language string
}
```

### Searchlight `toJson()` returns:
```dart
{
  'formatVersion': int,                    // NOT in Orama
  'algorithm': String,                     // NOT in Orama (implicit in index)
  'language': String,                      // matches Orama's language
  'schema': Map<String, Object?>,          // NOT in Orama
  'internalDocumentIDStore': {             // structure differs
    'idToInternalId': Map<String, int>,    // saved but not in Orama's save
    'internalIdToId': Map<String, String>, // Map vs Orama's Array
    'nextId': int,                         // NOT in Orama
    'nextGeneratedId': int,                // NOT in Orama
  },
  'documents': Map<String, Object?>,       // partial match (no count field)
}
```

### Divergences

| # | Area | Orama | Searchlight | Classification |
|---|------|-------|-------------|----------------|
| A1 | `index` in save data | Full index trees serialized (radix toJSON, AVL toJSON, bool toJSON, flat toJSON, BKD toJSON) + frequencies, tokenOccurrences, avgFieldLength, fieldLengths | **NOT serialized.** Index is rebuilt by re-inserting documents during `fromJson`. | **NEEDS REVIEW** |
| A2 | `sorting` in save data | Full sorter state serialized (orderedDocs, docs map, types, language, sortableProperties) | **NOT serialized.** Sort index is rebuilt by re-inserting documents during `fromJson`. | **NEEDS REVIEW** |
| A3 | `pinning` in save data | Pinning rules serialized as array of `[id, PinRule]` tuples | **Not implemented.** Searchlight has no pinning feature. | **ACCEPTABLE** |
| A4 | `schema` in save data | NOT saved. Orama's restore creates a placeholder `{__placeholder: 'string'}` schema; the real schema is implicit in the restored index structure. | Saved explicitly in the serialized output. Restored from JSON and used to create a fresh database. | **ACCEPTABLE** |
| A5 | `formatVersion` in save data | NOT present. | Added by Searchlight for forward-compatibility. | **ACCEPTABLE** |
| A6 | `algorithm` in save data | NOT saved. Orama restores with whatever plugins are installed. | Saved explicitly. Restored from JSON and used to create the database with the correct algorithm. | **ACCEPTABLE** |
| A7 | `docs.count` field | Orama's document store save includes `{ docs, count }`. | Searchlight saves only the documents map, not a count field. Count is derived from map length after re-insertion. | **ACCEPTABLE** |

### Analysis of A1 and A2

Searchlight does NOT serialize the index trees or sort index. Instead, `fromJson` calls `Searchlight.create(...)` to create a fresh database, then re-inserts all documents in internal ID order. This means:

- The index trees are rebuilt from scratch via normal `insert()` calls.
- The sort index is rebuilt from scratch via `_insertSortableValues()` during `insert()`.
- BM25 scoring statistics (frequencies, tokenOccurrences, avgFieldLength, fieldLengths) are recomputed from the re-inserted documents.
- QPS stats (tokenQuantums) are recomputed from the re-inserted documents.
- PT15 position data is recomputed from the re-inserted documents.

This is a **valid alternative approach** — re-insertion produces semantically identical results because:
1. All tree structures are deterministic given the same insertion order.
2. BM25 statistics are computed from the same document data.
3. The sort index is populated identically from the same field values.

However, see section B for edge cases where this could diverge.

---

## B. Index Serialization: Direct Restore vs Re-insertion

### Orama approach
Orama serializes index trees directly using each tree's `toJSON()` / `fromJSON()` methods:
- `RadixTree.fromJSON(node)` — restores the trie structure
- `AVLTree.fromJSON(node)` — restores the balanced tree
- `BoolNode.fromJSON(node)` — restores boolean sets
- `FlatTree.fromJSON(node)` — restores flat enum maps
- `BKDTree.fromJSON(node)` — restores the spatial tree

Additionally, Orama saves and restores all BM25 scoring metadata:
- `frequencies` (per-property, per-document, per-token TF values)
- `tokenOccurrences` (per-property, per-token document counts)
- `avgFieldLength` (per-property average token counts)
- `fieldLengths` (per-property, per-document token counts)

### Searchlight approach
Searchlight re-inserts documents, which rebuilds everything from scratch.

### Divergences

| # | Area | Impact | Classification |
|---|------|--------|----------------|
| B1 | BM25 statistics after round-trip | Re-insertion recomputes all BM25 stats identically. `insertDocumentScoreParameters` is called in the same order with the same tokens. Since docs are sorted by internal ID before re-insertion, the running averages are computed in the same order. **Result: Identical.** | **ACCEPTABLE** |
| B2 | QPS statistics after round-trip | Re-insertion calls `qpsInsertString` for each document, rebuilding `tokenQuantums` identically. | **ACCEPTABLE** |
| B3 | PT15 positions after round-trip | Re-insertion calls `pt15.insertString` for each document, rebuilding position buckets identically. | **ACCEPTABLE** |
| B4 | Radix tree structure | Radix tree shape depends on insertion order. Since Searchlight re-inserts in sorted internal ID order (same as original), the trie structure is identical. | **ACCEPTABLE** |
| B5 | AVL tree balance | AVL tree rotations depend on insertion order. Re-insertion in sorted order may produce a different tree shape than the original (which had arbitrary insertion patterns). However, AVL tree query results are order-independent (range queries, equality). Search results are **functionally identical**. | **ACCEPTABLE** |
| B6 | Performance of re-insertion vs direct restore | Re-insertion is O(n * m) where n = docs, m = fields. Direct tree restoration is O(data_size). For large databases, re-insertion will be significantly slower. | **NEEDS REVIEW** |
| B7 | GeoPoint fields and BKD tree | BKD tree is rebuilt by re-inserting GeoPoints. The tree structure may differ (BKD inserts are order-dependent), but search results (radius/polygon queries) are functionally identical. | **ACCEPTABLE** |

### Note on B6 (Performance)
This is not a correctness issue — search results are identical after round-trip. However, for databases with tens of thousands of documents, the re-insertion approach will be measurably slower than direct tree restoration. This is a known trade-off: simpler implementation at the cost of restore performance. A future optimization could add `toJson`/`fromJson` to each tree type to enable direct restoration.

---

## C. Document ID Store

### Orama
- **Saves:** `{ internalIdToId: string[] }` — only the array mapping internal IDs to external IDs. The array is 0-indexed; internal IDs are 1-based (accessed as `internalIdToId[internalId - 1]`).
- **Loads:** Rebuilds `idToInternalId` Map from the array. Clears existing state. Iterates the array and sets `idToInternalId.set(item, i + 1)`.
- The internal ID counter is implicit: it equals `internalIdToId.length + 1` for the next insertion.

### Searchlight
- **Saves:** Both maps (`idToInternalId` as `Map<String, int>`, `internalIdToId` as `Map<String, String>`) plus explicit counters (`nextId`, `nextGeneratedId`).
- **Loads:** Restores the maps directly from serialized component state for
  current snapshots. Legacy snapshots without `index`/`sorting` still use the
  older reinsertion fallback.

### Divergences

| # | Area | Impact | Classification |
|---|------|--------|----------------|
| C1 | ID mapping representation | Orama uses array (0-indexed) for `internalIdToId`. Searchlight uses `Map<String, String>` keyed by string representation of internal ID. | **ACCEPTABLE** (Dart type safety) |
| C2 | Saving both maps vs one | Orama saves only `internalIdToId` and rebuilds `idToInternalId` on load. Searchlight still saves both maps. The extra `idToInternalId` data is redundant but harmless. | **ACCEPTABLE** |
| C3 | Counter restoration | Orama's counter is implicit (array length). Searchlight saves and restores explicit `nextId` and `nextGeneratedId` counters, with a defensive lower bound to avoid duplicate IDs from corrupted data. | **ACCEPTABLE** |
| C4 | External ID preservation | Searchlight restores the external ID mapping directly from `internalIdToId` rather than reconstructing it through public `insert()`. | **ACCEPTABLE** |
| C5 | Sparse internal IDs after delete | Current snapshots preserve sparse internal IDs directly because documents, index, sorter, and ID maps are restored from serialized state rather than normalized through reinsertion. | **RESOLVED** |

### Detailed Analysis of C3

The counter restoration logic (lines 181-182 of `database.dart`) is:
```dart
if (nextId != null) db._nextInternalId = nextId;
if (nextGeneratedId != null) db._nextGeneratedId = nextGeneratedId;
```

For current snapshots this now runs after direct document/ID-store restore, not
after reinsertion. Searchlight also clamps `nextId` to at least
`documents.length + 1` so corrupted save data cannot create duplicate internal
IDs on the next insert.

**Potential issue:** If the saved `nextId` is less than N+1 (shouldn't happen in normal operation), subsequent inserts could create duplicate internal IDs. However, this would only occur with manually corrupted data.

**For `nextGeneratedId`:** The saved value still restores the correct
auto-generation counter. This remains **correct**.

---

## D. Sorter State

### Orama
Saves full sorter state:
```typescript
{
  language: string,
  sortableProperties: string[],
  sortablePropertiesWithTypes: Record<string, SortType>,
  sorts: Record<string, {
    docs: Record<string, number>,     // docId -> position (Map serialized to object)
    orderedDocs: [InternalDocumentID, value][],
    type: SortType
  }>,
  enabled: boolean,
  isSorted: boolean
}
```

### Searchlight
Serializes the sort index and restores it directly for current snapshots.
Legacy snapshots without serialized sorter payloads still rebuild it through the
reinsertion fallback.

### Divergences

| # | Area | Impact | Classification |
|---|------|--------|----------------|
| D1 | Sort index serialization | Current snapshots serialize and restore sorter state directly, which now matches Orama much more closely. Legacy snapshots still rebuild sortable state through the compatibility fallback. | **RESOLVED** |
| D2 | Sort order after restore | The `isSorted` flag starts as `true` for each `_PropertySort`, then is set to `false` on the first `insert()`. The sort index is lazily sorted on first `sortBy()` call. This matches Orama's pattern. | **ACCEPTABLE** |

---

## E. Format Versioning

### Orama
No format versioning. Orama's `RawData` interface has no version field. Schema compatibility is assumed.

### Searchlight
`currentFormatVersion = 1` (defined in `format.dart`). Checked in `fromJson`:
```dart
final version = json['formatVersion'];
if (version is! int || version != currentFormatVersion) {
  throw SerializationException(...);
}
```

### Divergences

| # | Area | Impact | Classification |
|---|------|--------|----------------|
| E1 | Format version check | Searchlight addition. Strict equality check (`version != currentFormatVersion`). This means: (a) null/missing version is rejected, (b) future versions are rejected, (c) past versions are rejected. | **ACCEPTABLE** |
| E2 | No migration path | The strict equality check means there is no upgrade/migration path for older format versions. When `currentFormatVersion` is bumped, all existing persisted data becomes unreadable. | **NEEDS REVIEW** |
| E3 | Version in serialized data | The version is included in the serialized JSON/CBOR output. This is extra data not present in Orama. | **ACCEPTABLE** |

### Note on E2
This is a design trade-off. For v1, strict version checking is appropriate since there are no older versions to migrate from. However, when `currentFormatVersion` is bumped to 2, a migration strategy should be implemented (or documented as "re-index from source data"). A forward-compatibility note in `format.dart` would be helpful.

---

## F. JSON Format

### Orama
`persist(db, 'json')` calls `JSON.stringify(save(db))`, producing a JSON string of the `RawData` structure.

### Searchlight
`toJson()` produces a `Map<String, Object?>` that is JSON-encodable. The caller can `jsonEncode(map)` to get a string.

### Divergences

| # | Area | Impact | Classification |
|---|------|--------|----------------|
| F1 | Top-level structure | Orama: `{ internalDocumentIDStore, index, docs, sorting, pinning, language }`. Searchlight: `{ formatVersion, algorithm, language, schema, internalDocumentIDStore, documents }`. Completely different key names and structure. | **ACCEPTABLE** |
| F2 | Not wire-compatible | Searchlight JSON cannot be loaded by Orama, and vice versa. | **ACCEPTABLE** |
| F3 | JSON encodability | Searchlight's `toJson()` output passes through `jsonEncode`/`jsonDecode` round-trip (tested in `json_serializer_test.dart`). | **ACCEPTABLE** |

### Analysis
Wire compatibility with Orama was never a goal. Searchlight's JSON format is self-contained (includes schema, algorithm, language) and versioned. Orama's format is not self-contained (relies on the host application to know the schema and plugins). Searchlight's approach is more robust for standalone persistence.

---

## G. Binary Format

### Orama
Uses `@msgpack/msgpack` library. The `persist(db, 'binary')` flow:
1. `save(db)` -> RawData object
2. `encode(dbExport)` -> msgpack Uint8Array
3. Convert to hex string (Node: `Buffer.toString('hex')`, browser: manual hex)

### Searchlight
Uses `cbor` Dart package. The `serialize()` flow:
1. `toJson()` -> Map<String, Object?>
2. `cborEncode(map)` -> CBOR Uint8List

### Divergences

| # | Area | Impact | Classification |
|---|------|--------|----------------|
| G1 | Encoding format | Orama: msgpack. Searchlight: CBOR. Both are binary formats for JSON-like data. | **ACCEPTABLE** |
| G2 | Hex encoding | Orama wraps msgpack bytes in hex string for portability. Searchlight returns raw CBOR bytes (Uint8List). | **ACCEPTABLE** |
| G3 | CBOR deep cast | Searchlight's `cborDecode` includes `_deepCastMap` to convert `Map<dynamic, dynamic>` (from cbor package) to `Map<String, Object?>`. This is necessary for Dart type safety. | **ACCEPTABLE** |
| G4 | Data structure inside binary | The binary payload encodes the same `toJson()` structure (Searchlight) or `save()` structure (Orama). These are different structures (see section F). | **ACCEPTABLE** |

---

## H. Persist/Restore Flow

### Orama
```
persist(db, 'json'):
  1. save(db) -> RawData
  2. JSON.stringify(RawData) -> string
  3. Return string (caller stores it)

restore('json', data):
  1. create({schema: {__placeholder: 'string'}}) -> empty db with placeholder schema
  2. JSON.parse(data) -> RawData
  3. load(db, RawData) -> mutates db in place:
     a. internalDocumentIDStore.load() — restores ID mappings
     b. index.load() — restores index trees + scoring data
     c. documentsStore.load() — restores document store
     d. sorter.load() — restores sort state
     e. pinning.load() — restores pinning rules
     f. tokenizer.language = raw.language
  4. Return db (now fully loaded, placeholder schema overwritten)
```

### Searchlight
```
persist(storage):
  1. serialize() -> Uint8List:
     a. toJson() -> Map<String, Object?>
     b. cborEncode(map) -> Uint8List
  2. storage.save(bytes) -> writes to disk/memory

restore(storage):
  1. storage.load() -> Uint8List (or null -> throw StorageException)
  2. deserialize(bytes):
     a. cborDecode(bytes) -> Map<String, Object?>
     b. fromJson(map):
        i.   Check formatVersion
        ii.  Extract algorithm, language, schema
        iii. Searchlight.create(schema, algorithm, language) -> fresh db
        iv.  Re-insert all documents in internal ID order
        v.   Overwrite _nextInternalId and _nextGeneratedId counters
  3. Return Searchlight instance
```

### Divergences

| # | Area | Impact | Classification |
|---|------|--------|----------------|
| H1 | Restore strategy | Orama: create placeholder, then mutate in place via `load()`. Searchlight: create with real schema, then re-insert documents. | **ACCEPTABLE** |
| H2 | Schema on restore | Orama: placeholder schema overwritten by index restoration. Searchlight: real schema deserialized from saved data and used to create fresh db. | **ACCEPTABLE** (Searchlight approach is more explicit) |
| H3 | Storage abstraction | Orama: `persist`/`restore` return/accept raw data. The `plugin-data-persistence` handles format encoding. File I/O was removed (throws METHOD_MOVED). Searchlight: `SearchlightStorage` interface with `FileStorage` implementation. `persist()`/`restore()` are convenience wrappers. | **ACCEPTABLE** |
| H4 | Binary-only persist/restore | Searchlight's `persist()` and `restore()` use CBOR exclusively. There is no option to persist as JSON. `toJson()` and `fromJson()` are available but not wired to `persist`/`restore`. | **NEEDS REVIEW** |
| H5 | Async vs sync | Orama: `persist` and `restore` are async (return Promise). Searchlight: `persist` and `restore` are async (return Future). `toJson`/`fromJson` and `serialize`/`deserialize` are sync. | **ACCEPTABLE** |

### Analysis of H4
Orama supports `persist(db, 'json')` and `persist(db, 'binary')` format selection. Searchlight's `persist()` method always uses CBOR. Users who want JSON persistence must manually call `toJson()` and handle storage themselves. This is a minor API gap — not a correctness issue, but reduces flexibility.

---

## I. Edge Cases

### I1. Restoring with a Different Schema

**Orama:** The restored index structure implicitly defines the schema. If you `save(db1)` with schema `{title: 'string', rating: 'number'}` and then `load(db2, rawData)` where `db2` was created with a different schema, the index structure from `rawData` replaces `db2`'s index entirely. The placeholder schema `{__placeholder: 'string'}` is always used on restore, so there is no schema mismatch check.

**Searchlight:** The schema is serialized and deserialized. `fromJson` creates a fresh database with the deserialized schema, then re-inserts documents. There is no way to "load into an existing database with a different schema" because `fromJson` is a factory constructor that creates a new instance.

| # | Area | Impact | Classification |
|---|------|--------|----------------|
| I1 | Schema mismatch on restore | Searchlight's approach prevents schema mismatch by design — the schema comes from the serialized data. Orama has no schema validation on restore. | **ACCEPTABLE** (Searchlight is safer) |

### I2. Restoring with a Different Algorithm

**Orama:** The algorithm (BM25/QPS/PT15) is determined by installed plugins at creation time. Restoring data saved with BM25 into a QPS-configured instance would load BM25 scoring data into QPS structures — likely producing incorrect results.

**Searchlight:** The algorithm is saved in JSON and restored. `fromJson` creates the database with the saved algorithm. There is no way to accidentally restore with a different algorithm.

| # | Area | Impact | Classification |
|---|------|--------|----------------|
| I2 | Algorithm mismatch on restore | Searchlight prevents algorithm mismatch by saving and restoring it explicitly. | **ACCEPTABLE** (Searchlight is safer) |

### I3. Corrupt Data

**Orama:** No specific corruption detection. `JSON.parse` throws on invalid JSON. `decode` (msgpack) throws on invalid binary. No format version check. No schema validation. Partially corrupt data (e.g., missing fields in RawData) will cause undefined behavior during `load`.

**Searchlight:**
- Format version mismatch: `SerializationException`
- Missing `algorithm`: `SerializationException`
- Missing `language`: `SerializationException`
- Missing/invalid `schema`: `SerializationException`
- Invalid CBOR bytes: `FormatException` caught and wrapped as `SerializationException`
- Missing `documents` or `internalDocumentIDStore`: Silently skipped (no documents restored). **Not** an error.

| # | Area | Impact | Classification |
|---|------|--------|----------------|
| I3a | Corrupt JSON/CBOR envelope | Both throw on invalid format. Searchlight wraps in typed exception. | **ACCEPTABLE** |
| I3b | Missing required fields | Searchlight validates algorithm, language, schema. Orama does not validate. | **ACCEPTABLE** (Searchlight is more robust) |
| I3c | Missing documents data | Searchlight silently returns an empty database. This could mask data loss. | **NEEDS REVIEW** |
| I3d | Corrupt document data within `documents` map | During re-insertion, `insert()` calls `_validateDocument()` which validates against the schema. Invalid documents would throw `DocumentValidationException`, aborting the restore. Orama's direct load does not validate document data. | **ACCEPTABLE** (Searchlight is stricter but correct) |

### I4. GeoPoint Serialization

| # | Area | Impact | Classification |
|---|------|--------|----------------|
| I4 | GeoPoint in document data | GeoPoints in documents are stored as `GeoPoint` objects. The `toMap()` call on `Document` would need to produce a JSON-serializable representation. If GeoPoint is a Dart class, `jsonEncode` might fail. | **NEEDS REVIEW** |

Let me check: Searchlight's `Document.toMap()` returns the original insertion data, which includes `GeoPoint` objects. These are NOT JSON-serializable (they're Dart objects). If a document contains a GeoPoint field, `toJson()` would produce a map containing `GeoPoint` instances, and `jsonEncode()` would throw. The CBOR encoder might handle this differently depending on the cbor package's behavior.

**Update after code review:** `Document.toMap()` returns the raw `Map<String, Object?>` passed to `insert()`. If the user passed `{'location': GeoPoint(lat: 1.0, lon: 2.0)}`, the toMap result contains the GeoPoint object. This would fail JSON serialization and likely fail CBOR serialization too. This is a **potential data loss bug** for databases with geopoint fields.

---

## Summary Table

| ID | Area | Divergence | Classification |
|----|------|-----------|----------------|
| A1 | Index trees not serialized | Rebuilt via re-insertion | **NEEDS REVIEW** |
| A2 | Sort index not serialized | Rebuilt via re-insertion | **NEEDS REVIEW** |
| A3 | No pinning feature | Not implemented in Searchlight | **ACCEPTABLE** |
| A4 | Schema saved explicitly | Not saved by Orama; Searchlight saves it | **ACCEPTABLE** |
| A5 | Format version added | Not in Orama | **ACCEPTABLE** |
| A6 | Algorithm saved explicitly | Not saved by Orama | **ACCEPTABLE** |
| A7 | No docs.count field | Derived from map size | **ACCEPTABLE** |
| B1-B5 | Scoring/tree identity after round-trip | Re-insertion produces functionally identical results | **ACCEPTABLE** |
| B6 | Restore performance | Re-insertion is slower than direct tree restore | **NEEDS REVIEW** |
| B7 | BKD tree after round-trip | Functionally identical | **ACCEPTABLE** |
| C1-C2 | ID store representation | Dart type safety differences | **ACCEPTABLE** |
| C3 | Counter restoration | Explicit counters saved and restored | **NEEDS REVIEW** |
| C4-C5 | External ID preservation | Correctly preserved via re-insertion | **ACCEPTABLE** |
| D1-D2 | Sort index rebuilt | Functionally identical | **ACCEPTABLE** |
| E1 | Strict version check | Searchlight addition | **ACCEPTABLE** |
| E2 | No version migration path | Future versions reject old data | **NEEDS REVIEW** |
| F1-F3 | JSON structure differs | Not wire-compatible (expected) | **ACCEPTABLE** |
| G1-G4 | CBOR vs msgpack | Different encoding, same semantics | **ACCEPTABLE** |
| H1-H3 | Restore strategy | Create+re-insert vs placeholder+load | **ACCEPTABLE** |
| H4 | Binary-only persist/restore | No JSON format option for persist/restore | **NEEDS REVIEW** |
| H5 | Async pattern | Both async at persist/restore level | **ACCEPTABLE** |
| I1-I2 | Schema/algorithm safety | Searchlight is safer by design | **ACCEPTABLE** |
| I3c | Missing documents silent | Returns empty db without warning | **NEEDS REVIEW** |
| I4 | GeoPoint serialization | GeoPoint objects may not be serializable | **NEEDS REVIEW** |

---

## Classification Counts

| Classification | Count |
|---------------|-------|
| ACCEPTABLE | 26 |
| NEEDS REVIEW | 9 |
| MUST FIX | 0 |

---

## NEEDS REVIEW Items — Detailed Recommendations

### A1/A2: Index and Sort Index Not Serialized
**Risk:** Functional correctness is preserved. Performance on restore is degraded for large databases.
**Recommendation:** Accept for v1. Document the trade-off. Consider adding tree serialization as a performance optimization in a future phase. The re-insertion approach has the advantage of simplicity and guaranteed consistency.

### B6: Restore Performance
**Risk:** For a database with 10,000+ documents, restoring via re-insertion could take multiple seconds vs milliseconds for direct tree restoration.
**Recommendation:** Benchmark with realistic dataset sizes. If restore time is acceptable for target use cases (mobile apps with <50k docs), accept. Otherwise, implement direct tree serialization.

### C3: Counter Restoration
**Risk:** Low. The `_nextInternalId` and `_nextGeneratedId` overwrite after re-insertion is correct in normal operation. Could produce issues only with manually corrupted save data.
**Recommendation:** Accept. Add a defensive check that the saved `nextId` is >= the number of re-inserted documents + 1.

### E2: No Version Migration Path
**Risk:** When `currentFormatVersion` is bumped, all existing persisted data becomes unreadable.
**Recommendation:** Before bumping the version, implement a migration function: `migrateFromV1(Map<String, Object?> json) -> Map<String, Object?>`. Or document that re-indexing from source data is the expected upgrade path.

### H4: Binary-Only Persist/Restore
**Risk:** Users who want JSON persistence for debugging or interoperability must use `toJson()`/`fromJson()` directly and manage storage themselves.
**Recommendation:** Consider adding a `format` parameter to `persist()`/`restore()`:
```dart
Future<void> persist({required SearchlightStorage storage, PersistenceFormat format = PersistenceFormat.cbor});
```
Alternatively, accept the current design and document the `toJson()` API for JSON use cases.

### I3c: Missing Documents Data Returns Empty Database
**Risk:** If the `documents` key is missing or null in the saved data, `fromJson` silently returns an empty database. This could mask data corruption or partial saves.
**Recommendation:** Consider logging a warning or throwing when `documents` or `internalDocumentIDStore` is missing from a valid (format-version-matching) save. An empty save should be distinguishable from a corrupt save.

### I4: GeoPoint Serialization
**Risk:** Databases with geopoint fields may fail to serialize. `GeoPoint` is a Dart class that is not inherently JSON- or CBOR-encodable. `Document.toMap()` returns the raw insertion data containing `GeoPoint` instances.
**Recommendation:** Verify whether `GeoPoint` fields are correctly handled. Options:
1. Store geopoints as `{'lat': double, 'lon': double}` maps in the document store.
2. Add a `toJson()`/`fromJson()` pair to `GeoPoint`.
3. Transform GeoPoint objects during `toJson()` serialization.
This should be tested with a database containing geopoint fields.

---

## Test Coverage Assessment

The existing tests cover:
- Empty database round-trip (schema, algorithm, language preservation)
- Document round-trip (count, getById, field values)
- Search on restored database (BM25 text search)
- Filter on restored database (number gt, boolean eq)
- QPS algorithm round-trip
- PT15 algorithm round-trip
- Format version rejection
- Corrupt/missing data rejection
- JSON string round-trip (`jsonEncode`/`jsonDecode`)
- CBOR round-trip (bytes)
- CBOR corrupt data rejection
- FileStorage save/load
- FileStorage empty file (returns null)
- persist/restore end-to-end
- restore from empty storage (throws StorageException)

### Missing Test Coverage
| Area | Test Needed |
|------|------------|
| GeoPoint round-trip | Insert doc with geopoint, serialize, deserialize, verify geo query works |
| Enum field round-trip | Insert doc with enum field, serialize, deserialize, verify enum filter works |
| Array field round-trip | Insert doc with string[], number[] fields, serialize, verify filter/search |
| Sort on restored database | Insert docs, serialize, deserialize, verify sortBy produces correct order |
| Delete-then-persist | Insert, delete some docs, persist, restore, verify correct count and IDs |
| Large document count | Benchmark with 1000+ docs to verify re-insertion performance |
| Nested field round-trip | Insert doc with nested schema, serialize, deserialize, verify nested search |
| Multiple persist/restore cycles | persist, restore, insert more, persist again, restore — verify accumulation |
