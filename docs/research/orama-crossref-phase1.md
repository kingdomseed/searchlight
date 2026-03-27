# Orama Cross-Reference Review — Phase 1

**Date:** 2026-03-25
**Scope:** Core layer (schema, types, CRUD, batch) vs Orama source

## Feature Parity — Gaps Found

| Gap | Severity | Notes |
|-----|----------|-------|
| User-provided document IDs | Design decision | Orama allows `doc.id` (string) or auto-generates UUID. We auto-increment int only. |
| Duplicate document detection | Low | Orama throws `DOCUMENT_ALREADY_EXISTS`. Our auto-increment prevents ID collisions but no content dedup. |
| `update` / `replace` / `patch` | Expected | Task 8 in our plan. Not yet implemented. |
| `updateMultiple` batch | Consider | Orama has this. Not in our plan — could add later. |
| `enum` accepts `string \| number` in Orama | Minor | We only accept `String`. Consider accepting `num` too. |
| `remove()` return type | Low | Orama returns `bool` (found/not found). We return `void`. |

## Patterns to Adopt

1. **Validate-all-first for batch updates** — Orama validates ALL docs before removing any, preventing partial state corruption. Adopt for `replace`/`patch`.
2. **Normalization cache** — Cache tokenized/stemmed terms per `language:property:token` (from tokenizer analysis).
3. **Component extraction** — Plan to extract `DocumentStore`, `Index`, `Scorer` as separate objects for Phase 2.
4. **Error codes** — Consider adding stable codes to exceptions for programmatic matching.

## Patterns We Correctly Diverge From

1. **Sealed types vs string literals** — Our SchemaField hierarchy catches errors at compile time
2. **Extension type DocId** — Zero-cost type safety TypeScript can't match
3. **Synchronous API** — No dual sync/async path needed (Dart isolates)
4. **Immutable Document wrapper** — Type-safe access vs raw JS objects
5. **No hook/plugin system** — Correct for v1, avoids enormous complexity
6. **Stricter validation** — We reject unknown fields; Orama silently ignores them

## Issues Found

| Issue | Severity | Action |
|-------|----------|--------|
| `_nextId` not reset on `clear()` | Moderate | Document or fix |
| `insertMultiple` only catches `DocumentValidationException` | Moderate | Add comment about future error surface |
| `DocId.isValid` missing from implementation | Low | Add or update spec |
| `GeoPoint` uses exact `double` equality | Low | Document semantics |
| `Document.getStringList` uses lazy `.cast<String>()` | Low | Document behavior |

## Recommendations for Phase 2

1. Indexing is per-property, not per-document
2. Scorer needs access to `docsCount` for IDF
3. Sort index built at insert time, not search time
4. `remove()` must un-index all fields (not just remove from document store)
5. `update` = remove old entries + insert new entries
6. Pre-compute searchable/sortable properties from Schema (already done via `fieldPathsOfType`)
