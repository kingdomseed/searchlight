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
