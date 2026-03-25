# Functional Equivalence Audit — Phase 1

**Date:** 2026-03-25
**Result:** 19 MUST FIX, 14 NEEDS REVIEW, 11 ACCEPTABLE

## MUST FIX Items (Priority Order)

### 1. Document ID System (A1, A2, A5, C1, C5, C6, D4, F5, G1)

Orama uses STRING external IDs (user-supplied via `doc.id` or auto-generated UUID) mapped to internal integers. Searchlight uses auto-increment int only. This is the single biggest divergence — nearly half of all MUST FIX items trace back to this.

**Fix:** Implement dual ID system matching Orama. External string IDs, internal int IDs, bidirectional mapping.

### 2. Schema Validation Direction (B1, H6)

Orama iterates SCHEMA keys (extra doc fields silently ignored). Searchlight iterates DOCUMENT keys (extra fields rejected with exception). Orama's approach is correct because documents can have `id` and other metadata fields.

**Fix:** Change `_validateDocument` to iterate schema fields, not document fields. Tolerate extra properties.

### 3. Enum Type Acceptance (B2, B5, H3, H4)

Orama's `enum` and `enum[]` accept `string | number`. Searchlight only accepts `String`.

**Fix:** Accept both `String` and `num` for enum types.

### 4. Batch Insert Error Semantics (E1, E2, E5)

Orama: single failure ABORTS the entire batch (no try/catch around individual inserts). Searchlight: catches errors per-document, continues batch, returns BatchResult.

**Fix:** Match Orama behavior — propagate failure, abort batch on first error. Remove or repurpose BatchResult/BatchError.

### 5. Remove Return Values (D1, D3, F6)

Orama `remove` returns `bool` (false if not found). Orama `removeMultiple` returns count. Searchlight returns `void` for both.

**Fix:** Change return types to match Orama.

## NEEDS REVIEW Items (Document Decisions)

These are deferred features, not bugs. Document whether they're Phase 1 deferrals or design decisions:

- A3: Dual ID system architecture (internal vs external)
- A4: 1-based vs 0-based internal IDs
- B6: Swappable validation component
- C2: Two-pass validation (schema + index property types)
- C3, D5, E6: Before/after hooks (plugin system)
- C4, D2: Index/sort operations on insert/remove
- E3: Default batch size (1000 vs 500)
- E4: Timeout parameter for batch rate-limiting
- F3: getMultiple / getAll methods
- F4: load/save serialization on doc store
- G4: ID translation in get operations
- H2: Vector type support

## ACCEPTABLE Items (No Action Needed)

Language/platform adaptations that are functionally equivalent:
- B3: Nominal GeoPoint type vs structural check
- B4: Exception throwing vs error return
- D6: Sequential processing vs setTimeout scheduling
- F1: Document wrapper vs raw objects
- F2: Computed count vs separate field
- G2: Document wrapper return type
- G3: isEmpty convenience getter
- H1: Enum vs string literals
- H5: Sealed class hierarchy vs runtime object check
- H7: Schema constructor validation (stricter, fail-fast)
- H8: Schema helper methods (typeAt, fieldPaths, etc.)
