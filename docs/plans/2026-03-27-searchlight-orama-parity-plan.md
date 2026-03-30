# Searchlight Orama-Parity Plan

## Overview

Parity-first reset. No publish, no package-split work until core public-surface
gaps vs Orama are resolved or explicitly accepted.

**Spec**: quick plan from repo research and parity audits

## Execution Note -- 2026-03-28

- Continue autonomously without pausing for intermediate approval when the
  next parity step is already implied by the source audit and prior user
  decisions.
- Keep landing incremental commits on the active extension branch as each
  parity slice is verified.
- Only stop for user input when a source-level parity question is genuinely
  ambiguous or when a change would intentionally diverge from Orama.

## Context

- **Structure**: core Dart package under `packages/searchlight`; example app under `packages/searchlight/example`
- **State management**: N/A; library package
- **Reference implementations**: `reference/orama/packages/orama/src/`, `docs/research/orama-functional-audit-phase1.md`, `docs/research/orama-functional-audit-phase2.md`, `docs/research/nimblenomicon-reference.md`
- **Assumptions/Gaps**:
  - Publish bar = credible Orama-style parity at public API level
  - Intentional divergences allowed only if explicit, narrow, defensible
  - `searchlight_flutter` and `searchlight_pdf` remain blocked on core parity

## Plan

## Current Status -- 2026-03-30

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
- create-time extension registration now exists for ordered plugins, named
  plugin metadata, lifecycle hooks, and `index` / `sorter` replacement
- component registration now fails deterministically for conflicting `index` /
  `sorter` claims, matching Orama's conflict model for those slots
- current Orama source behavior for reserved hooks has been pinned explicitly:
  `beforeInsertMultiple`, `beforeLoad`, and `afterLoad` remain declared but
  non-dispatched because the Orama runtime does not visibly dispatch them
- `upsert()` / `upsertMultiple()` now exist with Orama-style nested lifecycle
  behavior and matching upsert hook paths
- the extension component graph now also wires the runtime-reachable
  Orama-style slots that fit Searchlight cleanly today:
  `tokenizer`, `validateSchema`, `getDocumentIndexId`, and
  `getDocumentProperties`
- restore now fails fast if a caller tries to load a serialized snapshot
  through a custom tokenizer component, because Searchlight only persists
  reconstructible built-in tokenizer state
- a synchronous `documentsStore` component now exists with deterministic
  conflict handling, runtime CRUD/search hydration wiring, and persistence
  routed through `save()` plus exact-state `restore(...)`
- a synchronous `pinning` component now exists with deterministic conflict
  handling, tuple-based persistence, public pin CRUD, and search-time
  application after sort order but before pagination/facets/groups
- a `formatElapsedTime` function component now exists with deterministic
  conflict handling, and `SearchResult.elapsed` now carries an Orama-style
  `{raw, formatted}` payload plus a Dart-friendly `duration` getter
- hook registration now matches the current Orama runtime path:
  hooks register through top-level plugin fields, not through
  `SearchlightComponents`
- plugin component registration now matches the current Orama runtime path:
  plugins contribute schema-aware components through `getComponents(schema)`
- the public barrel now exports hook callback typedefs without exporting the
  internal `SearchlightHooks` bundle type

### Current checkpoint

- core extension-system parity is complete enough to unblock real plugin work
- the only remaining source-pinned runtime gap is the reserved hook trio:
  `beforeInsertMultiple`, `beforeLoad`, and `afterLoad`
- those hooks remain publicly named but intentionally non-dispatched because
  the current Orama runtime does not visibly dispatch them either
- async plugins and async component factories remain intentionally unsupported
  until a source-confirmed runtime contract exists
- the next useful validation step is no longer core refactoring; it is to
  build a real plugin against this API and pressure-test ergonomics

### Immediate next execution block

1. **Plugin proof**
   - implement the first real plugin package against the current extension API
   - use that package to verify that plugin authoring feels clean without
     reopening core contracts unnecessarily

2. **Recommended order**
   - first: highlight plugin
   - second: parsedoc
   - third: PDF-specific work
   - only reopen the core extension system if real plugin implementation
     exposes a concrete API or runtime mismatch

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
- **Status**: complete for the current parity target
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
- **Status**: complete enough for current parity target; compatibility rules are
  now explicit and tested
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
