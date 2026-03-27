# PR #1 Review Thread Remediation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Prove each legitimate PR #1 review finding with failing tests first, then fix or explicitly disposition each item, and clean up the related docs/API notes.

**Architecture:** Treat the work in two lanes. Lane 1 is executable regressions: write failing tests for the real runtime bugs, make the smallest code changes to pass them, then document any deliberate divergence from current Orama behavior. Lane 2 is non-runtime review feedback: clarify docs, tighten API comments, or explicitly validate unsupported shapes instead of silently changing behavior that currently matches Orama.

**Tech Stack:** Dart, package:test, GitHub PR review threads via `gh`, Searchlight core package.

---

## Disposition Matrix

- Fix in code with failing tests first:
  - Facet pagination crash when `offset > limit`
  - `NOT` filter phantom internal IDs inflating `SearchResult.count`
  - BM25 score metadata corruption when removing `string[]` fields
  - QPS sentence-bit overflow at quantum index `20`
  - Boolean sort comparator contract violation
- Keep behavior or harden with docs/validation instead of behavior change:
  - `tokenizeSkipProperties` bypasses lowercasing and currently matches Orama
  - Logical `and`/`or`/`not` filter objects are treated as exclusive top-level forms
  - `update()` remove-then-insert semantics match Orama
  - QPS `foundWords` merge shape matches Orama
- Docs/API/maintainability only:
  - `FacetConfig.limit` docs describe count semantics but implementation uses end-index semantics
  - `FlatTree.fromJson()` error text is vague
  - `progress.md` says "Concurrent" for a sequential scenario
  - `Document.toMap()` is only shallowly unmodifiable
  - README / audit notes should clearly mark any intentional divergences from Orama

### Task 1: Facet Pagination RangeError

**Files:**
- Modify: `packages/searchlight/test/search/facets_test.dart`
- Modify: `packages/searchlight/lib/src/search/facets.dart`
- Modify: `packages/searchlight/lib/src/core/types.dart`

**Step 1: Write the failing test**

Add a regression in `packages/searchlight/test/search/facets_test.dart` that creates a string facet with `offset: 5, limit: 3` and asserts:
- no exception is thrown
- returned `values` is empty
- `count` still reports total distinct facet values

**Step 2: Run test to verify it fails**

Run: `dart test packages/searchlight/test/search/facets_test.dart`
Expected: FAIL with a `RangeError` from `sublist(start, end)`.

**Step 3: Write minimal implementation**

Update `packages/searchlight/lib/src/search/facets.dart` so slicing emulates JS `slice(start, end)` when `start > end`:
- compute `end = min(limit, sorted.length)`
- compute `start = min(offset, end)`

Then update `FacetConfig` docs in `packages/searchlight/lib/src/core/types.dart` so `limit` is described as an end index for Orama parity, or rename the wording to "slice end" semantics.

**Step 4: Run tests to verify pass**

Run:
- `dart test packages/searchlight/test/search/facets_test.dart`
- `dart test packages/searchlight/test/search/engine_test.dart`

Expected: PASS.

**Step 5: Commit**

```bash
git add packages/searchlight/test/search/facets_test.dart packages/searchlight/lib/src/search/facets.dart packages/searchlight/lib/src/core/types.dart
git commit -m "fix: match Orama facet slice semantics for invalid ranges"
```

### Task 2: `NOT` Filter Phantom IDs

**Files:**
- Modify: `packages/searchlight/test/search/filters_test.dart`
- Modify: `packages/searchlight/test/search/engine_test.dart`
- Modify: `packages/searchlight/lib/src/search/filters.dart`
- Modify: `packages/searchlight/lib/src/core/database.dart`

**Step 1: Write the failing tests**

Add one focused regression in `packages/searchlight/test/search/filters_test.dart` and one end-to-end regression in `packages/searchlight/test/search/engine_test.dart`:
- insert 3 docs
- remove 1 doc
- run a `not(...)` query
- assert `results.count == results.hits.length`
- assert the deleted internal ID is not counted

**Step 2: Run tests to verify they fail**

Run:
- `dart test packages/searchlight/test/search/filters_test.dart`
- `dart test packages/searchlight/test/search/engine_test.dart`

Expected: FAIL because `count` includes deleted IDs even though hits do not.

**Step 3: Write minimal implementation**

Change `searchByWhereClause()` in `packages/searchlight/lib/src/search/filters.dart` to accept the actual existing internal IDs set instead of synthesizing `1..totalDocs`.

In `packages/searchlight/lib/src/core/database.dart`, pass:

```dart
_documents.keys.map((docId) => docId.id).toSet()
```

Thread the same set through recursive `and` / `or` / `not` calls.

**Step 4: Run tests to verify pass**

Run:
- `dart test packages/searchlight/test/search/filters_test.dart`
- `dart test packages/searchlight/test/search/engine_test.dart`

Expected: PASS.

**Step 5: Commit**

```bash
git add packages/searchlight/test/search/filters_test.dart packages/searchlight/test/search/engine_test.dart packages/searchlight/lib/src/search/filters.dart packages/searchlight/lib/src/core/database.dart
git commit -m "fix: exclude deleted docs from not-filter result sets"
```

### Task 3: BM25 `string[]` Removal Score Metadata

**Files:**
- Modify: `packages/searchlight/test/indexing/index_manager_test.dart`
- Modify: `packages/searchlight/test/search/engine_test.dart`
- Modify: `packages/searchlight/lib/src/indexing/index_manager.dart`
- Modify: `docs/research/orama-functional-audit-phase2.md`

**Step 1: Write the failing tests**

Add a low-level regression in `packages/searchlight/test/indexing/index_manager_test.dart` that:
- builds a BM25 index with a `stringArray` field
- inserts a doc with multiple array elements
- removes that doc
- asserts `fieldLengths`, `frequencies`, and `avgFieldLength` are updated exactly once per document

Add one end-to-end regression in `packages/searchlight/test/search/engine_test.dart` that:
- inserts two docs with `string[]`
- removes one
- searches remaining content
- asserts stable ranking / count and no score corruption

**Step 2: Run tests to verify they fail**

Run:
- `dart test packages/searchlight/test/indexing/index_manager_test.dart`
- `dart test packages/searchlight/test/search/engine_test.dart`

Expected: FAIL due to double-removal of document score parameters.

**Step 3: Write minimal implementation**

Refactor BM25 `string[]` handling in `packages/searchlight/lib/src/indexing/index_manager.dart`:
- compute per-document score parameters once per property, not once per array element
- still insert/remove tokens for every element
- preserve non-array behavior

Update `docs/research/orama-functional-audit-phase2.md` to mark this as a deliberate hardening divergence from current Orama behavior.

**Step 4: Run tests to verify pass**

Run:
- `dart test packages/searchlight/test/indexing/index_manager_test.dart`
- `dart test packages/searchlight/test/search/engine_test.dart`

Expected: PASS.

**Step 5: Commit**

```bash
git add packages/searchlight/test/indexing/index_manager_test.dart packages/searchlight/test/search/engine_test.dart packages/searchlight/lib/src/indexing/index_manager.dart docs/research/orama-functional-audit-phase2.md
git commit -m "fix: apply bm25 score bookkeeping once per string-array field"
```

### Task 4: QPS Quantum Overflow

**Files:**
- Modify: `packages/searchlight/test/scoring/qps_test.dart`
- Modify: `packages/searchlight/lib/src/scoring/qps.dart`
- Modify: `docs/research/orama-functional-audit-phase8.md`

**Step 1: Write the failing test**

Add a regression in `packages/searchlight/test/scoring/qps_test.dart` that constructs a string with more than 20 multi-token sentences containing the same token and asserts:
- late sentences still contribute to the final saturated quantum bucket
- the packed bitmask never loses the last bucket because of writing into bit `20`

Keep this at the unit level by inspecting `calculateTokenQuantum`, `bitmask20`, or the stored token quantum descriptor.

**Step 2: Run test to verify it fails**

Run: `dart test packages/searchlight/test/scoring/qps_test.dart`
Expected: FAIL because bit `20` is masked away.

**Step 3: Write minimal implementation**

In `packages/searchlight/lib/src/scoring/qps.dart`, cap the bit index at `19`, not `20`.

Update `docs/research/orama-functional-audit-phase8.md` to record this as a deliberate hardening divergence if the goal is no longer strict bug-for-bug parity.

**Step 4: Run tests to verify pass**

Run: `dart test packages/searchlight/test/scoring/qps_test.dart`
Expected: PASS.

**Step 5: Commit**

```bash
git add packages/searchlight/test/scoring/qps_test.dart packages/searchlight/lib/src/scoring/qps.dart docs/research/orama-functional-audit-phase8.md
git commit -m "fix: saturate qps sentence bit packing at bit 19"
```

### Task 5: Boolean Sort Comparator Hardening

**Files:**
- Modify: `packages/searchlight/test/search/sorting_test.dart`
- Modify: `packages/searchlight/lib/src/indexing/sort_index.dart`
- Modify: `docs/research/orama-functional-audit-phase2.md`

**Step 1: Write the failing test**

Add a regression in `packages/searchlight/test/search/sorting_test.dart` that inserts multiple docs with duplicate boolean values and asserts:
- sorting by the boolean field returns all docs
- equal boolean groups remain deterministic across repeated sorts
- the comparator treats equal values as equal

If this is awkward through the public API, add a small focused unit around `SortIndex.sortBy()` using duplicate `true` and `false` values.

**Step 2: Run test to verify it fails**

Run: `dart test packages/searchlight/test/search/sorting_test.dart`
Expected: FAIL or expose nondeterministic ordering / comparator contract violation.

**Step 3: Write minimal implementation**

In `packages/searchlight/lib/src/indexing/sort_index.dart`, change the boolean comparator to:

```dart
if (va == vb) return 0;
return va ? 1 : -1;
```

Update the audit note in `docs/research/orama-functional-audit-phase2.md` to mark this as intentional hardening beyond Orama.

**Step 4: Run tests to verify pass**

Run: `dart test packages/searchlight/test/search/sorting_test.dart`
Expected: PASS.

**Step 5: Commit**

```bash
git add packages/searchlight/test/search/sorting_test.dart packages/searchlight/lib/src/indexing/sort_index.dart docs/research/orama-functional-audit-phase2.md
git commit -m "fix: make boolean sort comparator obey comparator contract"
```

### Task 6: Docs, API Semantics, and Maintainability Sweep

**Files:**
- Modify: `packages/searchlight/lib/src/core/types.dart`
- Modify: `packages/searchlight/lib/src/text/tokenizer.dart`
- Modify: `packages/searchlight/lib/src/trees/flat_tree.dart`
- Modify: `packages/searchlight/lib/src/core/document.dart`
- Modify: `packages/searchlight/lib/src/core/database.dart`
- Modify: `packages/searchlight/progress.md`
- Modify: `packages/searchlight/README.md`

**Step 1: Write documentation-only assertions where practical**

Add or extend tests where they increase confidence:
- tokenizer skip-properties test documenting current lowercase behavior
- document/update semantics test names or comments that clarify intended behavior

Do not force behavior changes for items that intentionally match Orama.

**Step 2: Apply doc/API changes**

Make the following updates:
- `FacetConfig` docs: describe slice end semantics explicitly
- `tokenizer.dart`: document that `tokenizeSkipProperties` bypasses split/lowercase and matches current Orama behavior
- `flat_tree.dart`: improve invalid JSON error text
- `document.dart`: document that `toMap()` is shallowly unmodifiable
- `database.dart`: explicitly call out `update()` remove-then-insert semantics
- `progress.md`: rename "Concurrent insert and search" to "Sequential interleaved insert/search"
- `README.md`: keep language count aligned with actual supported tokenizer languages

**Step 3: Run targeted tests**

Run:
- `dart test packages/searchlight/test/text/tokenizer_test.dart`
- `dart test packages/searchlight/test/core/document_test.dart`
- `dart test packages/searchlight/test/core/database_update_test.dart`

Expected: PASS.

**Step 4: Commit**

```bash
git add packages/searchlight/lib/src/core/types.dart packages/searchlight/lib/src/text/tokenizer.dart packages/searchlight/lib/src/trees/flat_tree.dart packages/searchlight/lib/src/core/document.dart packages/searchlight/lib/src/core/database.dart packages/searchlight/progress.md packages/searchlight/README.md packages/searchlight/test/text/tokenizer_test.dart packages/searchlight/test/core/document_test.dart packages/searchlight/test/core/database_update_test.dart
git commit -m "docs: clarify review-thread semantics and api behavior"
```

### Task 7: Review Thread Follow-Through

**Files:**
- No repository files required

**Step 1: Re-check open threads**

Run:

```bash
gh pr view 1 --repo kingdomseed/searchlight --json reviews
```

and:

```bash
gh api graphql -f query='query($owner:String!, $repo:String!, $number:Int!) { repository(owner:$owner, name:$repo) { pullRequest(number:$number) { reviewThreads(first:100) { nodes { id isResolved isOutdated path } } } } }' -F owner=kingdomseed -F repo=searchlight -F number=1
```

**Step 2: Reply only where useful**

If implementation lands, reply on threads that need rationale:
- fixed in code
- documented as deliberate divergence
- no-op because behavior intentionally matches Orama

**Step 3: Resolve threads**

Use `resolveReviewThread` for every remaining unresolved thread once the disposition is reflected in code or docs.

**Step 4: Final verification**

Run:

```bash
gh api graphql -f query='query($owner:String!, $repo:String!, $number:Int!) { repository(owner:$owner, name:$repo) { pullRequest(number:$number) { reviewThreads(first:100) { nodes { isResolved } } } } }' -F owner=kingdomseed -F repo=searchlight -F number=1
```

Expected: all threads resolved.

### Task 8: Final Verification Pass

**Files:**
- No direct edits

**Step 1: Run the focused suite**

Run:

```bash
dart test \
  packages/searchlight/test/search/facets_test.dart \
  packages/searchlight/test/search/filters_test.dart \
  packages/searchlight/test/search/engine_test.dart \
  packages/searchlight/test/scoring/qps_test.dart \
  packages/searchlight/test/search/sorting_test.dart \
  packages/searchlight/test/indexing/index_manager_test.dart \
  packages/searchlight/test/text/tokenizer_test.dart \
  packages/searchlight/test/core/document_test.dart \
  packages/searchlight/test/core/database_update_test.dart
```

**Step 2: Run full verification**

Run:

```bash
dart test
dart analyze
```

Expected: all pass.

**Step 3: Commit any final audit/doc fixes**

```bash
git add .
git commit -m "test: lock in pr review regressions"
```

Plan complete and saved to `docs/plans/2026-03-26-pr1-thread-remediation.md`. Two execution options:

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

**Which approach?**
