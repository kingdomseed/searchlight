# PR 3 Review Triage

**Last updated:** 2026-03-30

This document tracks the open review findings on
`feat/extension-system` and records whether each item is:

- a real bug to fix
- a duplicate of another issue
- a non-blocking improvement
- a non-issue relative to current Searchlight and Orama behavior

## Current review set

### 1. Compatibility error message wording

- Source: Copilot review thread on `lib/src/core/database.dart`
- Status: `non-blocking improvement`
- Initial read:
  the message text appears confusing but does not describe a runtime behavior
  bug. This thread is also already marked outdated on GitHub.
- Planned action:
  fix only if the surrounding persistence path is touched again during this
  triage pass.

### 2. `reindex()` conflicts when plugins provide components

- Source: Copilot + Devin review threads
- Status: `fixed`
- Duplicate: yes
- Resolution:
  real bug. A failing regression test proved `reindex()` replayed plugin-owned
  components as if they were user overrides and then tripped the resolver's
  conflict check.
- Fix:
  retain the original user-provided component overrides separately and replay
  only those during `reindex()`.
- Evidence:
  `test/core/extensions_components_test.dart`
  `reindex preserves plugin-provided index components`

### 3. `fromJson()` restores plugin-overridden indexes through the default
factory path

- Source: Devin review thread
- Status: `fixed`
- Resolution:
  real bug. A failing persistence test proved plugin-forced PT15 indexes were
  restored as BM25 because restore used the top-level database algorithm
  instead of the resolved index component's effective runtime algorithm.
- Fix:
  resolve the active index/sorter components first during restore, create their
  runtime shape, and hydrate serialized index/sort state using that effective
  configuration rather than the top-level defaults alone.
- Evidence:
  `test/persistence/json_serializer_test.dart`
  `fromJson preserves plugin-provided index algorithm and search`

### 4. Sync hook runners can fail for named `FutureOr<void>` hooks

- Source: Copilot review thread
- Status: `non-issue`
- Resolution:
  could not reproduce. Named synchronous `FutureOr<void>` hooks already run
  successfully on both the single-record lifecycle path and the dedicated
  search-hook path without production changes.
- Evidence:
  passing regression coverage added in:
  `test/core/extensions_lifecycle_single_test.dart`
  `insert accepts named synchronous FutureOr<void> hooks`
  `test/search/engine_test.dart`
  `search accepts named synchronous FutureOr<void> hooks`

### 5. `upsert()` / `upsertMultiple()` resolve generated IDs twice

- Source: Devin review thread
- Status: `fixed`
- Resolution:
  real bug. Missing-`id` upserts burned generated IDs during the existence
  check, then generated new IDs again during the delegated insert path. That
  caused mismatched hook IDs and skipped generated values.
- Fix:
  add private insert helpers that accept an already-resolved external ID, then
  thread those IDs through `upsert()` and `upsertMultiple()` so the generator
  runs only once per inserted document.
- Evidence:
  `test/core/extensions_lifecycle_single_test.dart`
  `upsert reuses one generated ID across hooks and insert`
  `test/core/extensions_lifecycle_batch_test.dart`
  `upsertMultiple reuses generated IDs for inserted documents`

### 6. `insert()` ignores `documentsStore.store()` failure

- Source: Devin review thread
- Status: `fixed`
- Resolution:
  real bug. A failing regression test proved insert returned success even when
  the active documents store rejected the write.
- Fix:
  call `documentsStore.store(...)` before publishing the document into the
  database's ID maps or search index, and throw `StorageException` when the
  store rejects the write.
- Evidence:
  `test/core/extensions_documents_store_component_test.dart`
  `insert fails fast when the documentsStore rejects the write`

## Execution notes

- Triage should proceed red-green, one issue at a time.
- Duplicate findings should collapse to one regression test and one fix.
- Improvements that go beyond Orama are allowed only when they are clearly
  correct, finished, and documented.
- Current disposition:
  3 real bugs fixed, 1 duplicate collapsed into the same fix, 1 outdated
  wording nit left as non-blocking, and 1 likely false positive verified as a
  non-issue.
