# Searchlight Orama-Parity Plan

## Overview

Parity-first reset. No publish, no package-split work until core public-surface
gaps vs Orama are resolved or explicitly accepted.

**Spec**: quick plan from repo research and parity audits

## Context

- **Structure**: core Dart package under `packages/searchlight`; example app under `packages/searchlight/example`
- **State management**: N/A; library package
- **Reference implementations**: `reference/orama/packages/orama/src/`, `docs/research/orama-functional-audit-phase1.md`, `docs/research/orama-functional-audit-phase2.md`, `docs/research/nimblenomicon-reference.md`
- **Assumptions/Gaps**:
  - Publish bar = credible Orama-style parity at public API level
  - Intentional divergences allowed only if explicit, narrow, defensible
  - `searchlight_flutter` and `searchlight_pdf` remain blocked on core parity

## Plan

## Current Status -- 2026-03-27

### Completed since this plan was created

- `Searchlight.create(...)` now wires through create-time tokenizer controls:
  `stemming`, `stemmer`, `stopWords`, `useDefaultStopWords`,
  `allowDuplicates`, `tokenizeSkipProperties`, `stemmerSkipProperties`,
  and injected `tokenizer`
- added public regression tests covering create-time tokenizer behavior in
  `packages/searchlight/test/core/database_create_config_test.dart`
- aligned constructor conflict behavior with Orama:
  injected `tokenizer` + explicit `language` now throws deterministically
- aligned default create-time stemming with Orama:
  default stemming is now off
- tokenizer config that is reconstructible now round-trips through JSON
  persistence
- non-reconstructible tokenizer state is now rejected during persistence:
  injected `Tokenizer` instances and custom stemmer callbacks fail fast in
  `toJson()` rather than serializing misleading data
- persistence now serializes and restores `index` and `sorting` component
  state directly, matching Orama's save/load shape more closely while still
  accepting legacy snapshots that require reinsertion fallback
- the public barrel no longer exports Searchlight-only `DocumentAdapter`;
  adapter-style extraction is now an internal concern until extension work
  defines a stable package boundary
- package docs updated to describe the current create-time configuration
  surface and persistence limits

### Immediate next execution block

1. **Reindex parity for tokenizer config**
   - add failing tests in
     `packages/searchlight/test/scoring/algorithm_selection_test.dart`
   - prove `reindex()` preserves built-in tokenizer settings such as
     `stemming`, `stopWords`, `useDefaultStopWords`, `allowDuplicates`,
     `tokenizeSkipProperties`, and `stemmerSkipProperties`
   - decide and test how `reindex()` should behave for injected tokenizers and
     custom stemmers; minimum acceptable behavior is deterministic rejection

2. **Persistence guard completion**
   - add failing tests covering `persist()` / `serialize()` and
     `restore()` / `deserialize()` paths, not only `toJson()`
   - verify custom-tokenizer/custom-stemmer rejection is consistent across
     JSON and CBOR entry points

3. **Create-time tokenizer validation parity**
   - add failing tests for unsupported tokenizer language handling
   - add failing tests for invalid stop-word configuration and mismatch cases
     where Searchlight intentionally diverges or still needs parity work
   - explicitly decide which non-English stemming differences remain accepted
     enhancements vs must-fix parity gaps

4. **Public divergence ledger**
   - add a concise document under `docs/research/` listing:
     matched, intentional divergences, and remaining gaps
   - use that ledger to gate publish-readiness claims

### Phase 1: Freeze Publish Scope

- **Goal**: stop premature release work; define gates
- [ ] `packages/searchlight/README.md` - remove publish-forward wording that implies parity beyond current public surface
- [ ] `packages/searchlight/doc/README.md` - add parity-status note pointing to audit/plan
- [ ] `docs/research/` - add or update a concise public divergence ledger: matches / intentional / missing
- [ ] TDD: no runtime tests; add a release checklist requiring every public divergence to be fixed or documented before publish
- [ ] Verify: `dart analyze` && `dart test`

### Phase 2: Searchlight.create Parity

- **Goal**: close top-level creation/configuration gap first
- [ ] `packages/searchlight/test/core/` - add one failing public-API test at a time for Orama-style creation config
- [ ] `packages/searchlight/lib/src/core/database.dart` - expand `Searchlight.create(...)` surface
- [ ] `packages/searchlight/lib/searchlight.dart` - export any new public config types
- [ ] `packages/searchlight/lib/src/text/tokenizer.dart` - reuse current tokenizer capabilities through DB creation path rather than standalone-only
- [ ] TDD: `Searchlight.create(..., language: ...)` preserves current behavior while allowing explicit tokenizer-related config
- [ ] TDD: stop-word configuration at creation time affects insert/search tokenization end-to-end
- [ ] TDD: stemming configuration at creation time affects insert/search tokenization end-to-end
- [ ] TDD: invalid language/config combinations fail deterministically
- [ ] Verify: `dart analyze` && `dart test packages/searchlight/test/text/tokenizer_test.dart packages/searchlight/test/core/database_lifecycle_test.dart`

### Phase 3: Extension Surface Decision

- **Goal**: decide and implement public extension architecture parity
- [ ] `reference/orama/packages/orama/src/` - pin exact Orama create/components/hooks/plugins contract to match
- [ ] `packages/searchlight/test/core/` - add failing tests for the chosen public extension surface
- [ ] `packages/searchlight/lib/src/core/` - add hook/plugin/component config types
- [ ] `packages/searchlight/lib/src/core/database.dart` - wire lifecycle callbacks into insert/search/remove/load paths
- [ ] `packages/searchlight/lib/searchlight.dart` - export stable extension-surface types only
- [ ] TDD: `beforeInsert` and `afterInsert` fire in deterministic order
- [ ] TDD: `beforeSearch` and `afterSearch` wrap `search()` correctly
- [ ] TDD: conflicting plugin/component registrations fail deterministically
- [ ] Verify: `dart analyze` && `dart test packages/searchlight/test/core`

### Phase 4: Persistence Public-Surface Parity

- **Goal**: align save/load/restore contract closely enough for public claims
- [ ] `packages/searchlight/test/persistence/` - add failing parity tests before implementation
- [ ] `packages/searchlight/lib/src/core/database.dart` - separate public save/load payload behavior from current reinsertion shortcut if parity requires it
- [ ] `packages/searchlight/lib/src/persistence/` - add format-symmetric persist/restore API if retained in public surface
- [ ] `packages/searchlight/lib/src/indexing/` - serialize/restore index and sort metadata directly if required by parity target
- [ ] TDD: JSON round-trip restores searchable/sortable state without rebuilding through public `insert()`
- [ ] TDD: CBOR round-trip restores searchable/sortable state without rebuilding through public `insert()`
- [ ] TDD: persist/restore format selection is symmetric and explicit
- [ ] Verify: `dart analyze` && `dart test packages/searchlight/test/persistence`

### Phase 5: Remaining High-Value Parity Gaps

- **Goal**: clear remaining publish blockers and user-visible mismatches
- [ ] `packages/searchlight/test/indexing/` - add locale-aware sort parity tests
- [ ] `packages/searchlight/lib/src/indexing/sort_index.dart` - implement locale-aware string ordering or document exact supported behavior if exact parity is not feasible
- [ ] `packages/searchlight/lib/src/core/document_adapter.dart` - either stabilize and document `DocumentAdapter` or remove it from the public barrel
- [ ] `packages/searchlight/doc/app-integration.md` - clarify schema-declared fields rule for PDF/page metadata
- [ ] TDD: configured-language string sort matches Orama for at least one non-English fixture
- [ ] TDD: public extraction path using `DocumentAdapter<T>` either works end-to-end or the type is no longer public
- [ ] Verify: `dart analyze` && `dart test packages/searchlight/test/search/sorting_test.dart packages/searchlight/test/core/document_adapter_test.dart`

### Phase 6: Publish Readiness Re-open

- **Goal**: only after parity gates are green
- [ ] `packages/searchlight/README.md` - re-open publish-facing positioning after parity is true
- [ ] `packages/searchlight/doc/README.md` - add explicit supported-surface summary
- [ ] `packages/searchlight/pubspec.yaml` - finalize metadata only after core parity sign-off
- [ ] TDD: no new runtime tests unless docs expose new public behavior
- [ ] Verify: `dart analyze` && `dart test` && `dart pub publish --dry-run`

### Phase 7: Package-Split Planning

- **Goal**: unblock later packages only after core parity ships
- [ ] `docs/plans/` - create separate plans for `searchlight_flutter` and `searchlight_pdf`
- [ ] `packages/searchlight/example/` - keep validation/example code as consumer reference, not core API spillover
- [ ] TDD: none yet; planning only
- [ ] Verify: N/A

## Risks / Out of scope

- **Risks**:
  - Orama parity at public API level is broader than tokenizer config alone
  - plugin/hooks/components parity may force a substantial public-surface redesign
  - direct index serialization may be materially more invasive than current reinsert-on-load approach
- **Out of scope**:
  - `searchlight_flutter`
  - `searchlight_pdf`
  - PDF viewer/search UX
  - publish/marketing polish before parity gates are green
