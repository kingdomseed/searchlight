# Searchlight Post-Merge Roadmap Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Finish `searchlight` core publish readiness, freeze the v1 extension contract, and then sequence the first three companion packages in the agreed order: `parsedoc`, `highlight`, `pdf`.

**Architecture:** Keep `searchlight` as a single publishable core package in this repo. Do not reintroduce a monorepo. Treat `searchlight_parsedoc`, `searchlight_highlight`, and `searchlight_pdf` as follow-on companion packages in separate repos once the core publish gate and extension contract are stable. Match Orama where the source is clear; document intentional divergence where Searchlight is stricter or broader.

**Tech Stack:** Dart 3, Flutter example app, `test`, `very_good_analysis`, GitHub, pub.dev packaging, existing Orama research docs in `docs/research/`.

---

## Global Rules

- Work on `main`.
- Keep TDD honest for all code changes.
- For docs-only or publish-only tasks, use verification-first instead of fake tests.
- Do not weaken current extension behavior just to simplify docs.
- Do not reintroduce a `packages/` monorepo layout.
- Companion packages should assume sibling repos:
  - `../searchlight_parsedoc`
  - `../searchlight_highlight`
  - `../searchlight_pdf`

## Task 1: Publish-Readiness Gate For `searchlight`

**Files:**
- Modify: `/Users/jholt/development/jhd-business/searchlight/pubspec.yaml`
- Modify: `/Users/jholt/development/jhd-business/searchlight/README.md`
- Modify: `/Users/jholt/development/jhd-business/searchlight/CHANGELOG.md`
- Modify: `/Users/jholt/development/jhd-business/searchlight/doc/app-integration.md`
- Modify: `/Users/jholt/development/jhd-business/searchlight/doc/validation-workflow.md`
- Modify: `/Users/jholt/development/jhd-business/searchlight/example/README.md`
- Test: `/Users/jholt/development/jhd-business/searchlight/test/core/public_api_surface_test.dart`

**Step 1: Run the publish gate exactly as users will experience it**

Run:

```bash
cd /Users/jholt/development/jhd-business/searchlight
dart analyze
dart test
dart pub publish --dry-run
cd /Users/jholt/development/jhd-business/searchlight/example
flutter pub get
flutter analyze
```

Expected:
- `dart analyze` passes cleanly
- `dart test` passes
- `dart pub publish --dry-run` reports no blocking warnings
- `flutter analyze` passes for the example app

**Step 2: Fix metadata and public-package copy until the dry run is clean**

Constrain edits to:
- package description, topics, homepage/documentation URLs in `pubspec.yaml`
- README opening sections, install flow, quick start, extension summary
- `CHANGELOG.md` unreleased notes
- app/example docs where public usage is unclear

Do not add marketing fluff. Keep the README technical and implementation-focused.

**Step 3: Add or tighten public surface regression coverage if docs claim behavior**

Examples of acceptable tests in `test/core/public_api_surface_test.dart`:

```dart
test('searchlight barrel exports extension types used in README snippets', () {
  // compile-only API surface proof
});
```

```dart
test('searchlight public API exposes create-time extension entry points', () {
  // compile-only API surface proof
});
```

Only add tests for claims that the README now makes.

**Step 4: Re-run the full publish gate**

Run:

```bash
cd /Users/jholt/development/jhd-business/searchlight
dart analyze
dart test
dart pub publish --dry-run
cd /Users/jholt/development/jhd-business/searchlight/example
flutter analyze
```

Expected:
- all four commands pass

**Step 5: Commit**

```bash
git add -A
git commit -m "docs: finish core publish readiness"
```

## Task 2: Freeze The V1 Extension Contract

**Files:**
- Modify: `/Users/jholt/development/jhd-business/searchlight/README.md`
- Modify: `/Users/jholt/development/jhd-business/searchlight/doc/app-integration.md`
- Modify: `/Users/jholt/development/jhd-business/searchlight/docs/research/searchlight-extension-status.md`
- Modify: `/Users/jholt/development/jhd-business/searchlight/docs/research/orama-divergence-ledger.md`
- Modify: `/Users/jholt/development/jhd-business/searchlight/test/core/public_api_surface_test.dart`
- Modify: `/Users/jholt/development/jhd-business/searchlight/test/core/extensions_lifecycle_batch_test.dart`
- Modify: `/Users/jholt/development/jhd-business/searchlight/test/persistence/json_serializer_test.dart`

**Step 1: Write failing tests for any extension contract that is still only documented loosely**

Candidate tests:

```dart
test('beforeInsertMultiple remains non-dispatched for Orama parity', () {
  // create plugin, call insertMultiple, prove no beforeInsertMultiple call
});
```

```dart
test('restore requires matching plugin order and component ids', () {
  // fromJson compatibility proof
});
```

```dart
test('public API does not expose async plugin initialization hooks', () {
  // compile-time surface proof if needed
});
```

Only add missing proof. Do not duplicate coverage that already exists.

**Step 2: Run the targeted failing tests**

Run:

```bash
cd /Users/jholt/development/jhd-business/searchlight
dart test test/core/public_api_surface_test.dart
dart test test/core/extensions_lifecycle_batch_test.dart
dart test test/persistence/json_serializer_test.dart
```

Expected:
- at least one targeted test fails if the contract is not yet fully pinned down

**Step 3: Implement the minimal contract/documentation alignment**

Allowed outcomes:
- add the missing regression test only, if runtime already matches
- tighten docs to describe the actual contract precisely
- make minimal code changes only if the runtime is under-specified and the fix
  is fully source-confirmed by Orama

Do not implement speculative async/plugin behavior here.

**Step 4: Re-run the targeted extension tests**

Run:

```bash
cd /Users/jholt/development/jhd-business/searchlight
dart test test/core/public_api_surface_test.dart
dart test test/core/extensions_lifecycle_batch_test.dart
dart test test/persistence/json_serializer_test.dart
dart analyze
```

Expected:
- all targeted tests pass
- analyzer stays clean

**Step 5: Commit**

```bash
git add -A
git commit -m "docs(extensions): freeze v1 contract"
```

## Task 3: `searchlight_parsedoc` Spec + Bootstrap

**Files in this repo first:**
- Modify: `/Users/jholt/development/jhd-business/searchlight/docs/research/orama-plugin-package-map.md`
- Create: `/Users/jholt/development/jhd-business/searchlight/docs/research/searchlight-parsedoc-package-spec.md`
- Create: `/Users/jholt/development/jhd-business/searchlight/docs/plans/2026-03-30-searchlight-parsedoc-implementation.md`

**Files in the new sibling repo after the spec is approved:**
- Create: `../searchlight_parsedoc/pubspec.yaml`
- Create: `../searchlight_parsedoc/README.md`
- Create: `../searchlight_parsedoc/lib/searchlight_parsedoc.dart`
- Create: `../searchlight_parsedoc/lib/src/models/parsed_document.dart`
- Create: `../searchlight_parsedoc/lib/src/parsers/markdown_parser.dart`
- Create: `../searchlight_parsedoc/lib/src/parsers/html_parser.dart`
- Create: `../searchlight_parsedoc/lib/src/mappers/searchlight_record_mapper.dart`
- Create: `../searchlight_parsedoc/test/markdown_parser_test.dart`
- Create: `../searchlight_parsedoc/test/html_parser_test.dart`
- Create: `../searchlight_parsedoc/test/searchlight_record_mapper_test.dart`

**Step 1: Write the package spec from Orama-confirmed scope**

The spec must explicitly lock:
- supported source types: Markdown and HTML only
- non-goals: PDF, OCR, rendering, viewport geometry
- outputs: normalized parsed document model plus direct Searchlight record
  mapping helpers
- live-file support: file path in, parsed result out
- pure Dart only

Use Orama research as the source of truth for package boundary, not guesses.

**Step 2: Save the parsedoc implementation plan**

The plan must include TDD slices:
1. markdown parsing
2. html parsing
3. metadata extraction
4. Searchlight record mapping
5. live-file loading helpers
6. README examples

Each slice must include exact tests and commands.

**Step 3: Bootstrap the sibling repo only after the spec is accepted**

Run:

```bash
cd /Users/jholt/development/jhd-business
dart create -t package searchlight_parsedoc
```

Expected:
- a clean pure Dart package repo with no Flutter dependency

**Step 4: Start TDD in the new repo**

First failing test example:

```dart
test('markdown parser extracts title and body text from a live file', () async {
  final doc = await parseMarkdownFile('test/fixtures/sample.md');
  expect(doc.title, 'Sample Title');
  expect(doc.bodyText, contains('First paragraph'));
});
```

Run:

```bash
cd ../searchlight_parsedoc
dart test test/markdown_parser_test.dart
```

Expected:
- fail first

**Step 5: Commit the spec here, then commit the repo bootstrap there**

Core repo:

```bash
git add docs/research/orama-plugin-package-map.md docs/research/searchlight-parsedoc-package-spec.md docs/plans/2026-03-30-searchlight-parsedoc-implementation.md
git commit -m "docs(parsedoc): define package scope and implementation plan"
```

Sibling repo:

```bash
git add -A
git commit -m "chore: bootstrap searchlight_parsedoc"
```

## Task 4: `searchlight_highlight` Package Spec + Bootstrap

**Files in this repo first:**
- Create: `/Users/jholt/development/jhd-business/searchlight/docs/research/searchlight-highlight-package-spec.md`
- Create: `/Users/jholt/development/jhd-business/searchlight/docs/plans/2026-03-30-searchlight-highlight-implementation.md`
- Modify: `/Users/jholt/development/jhd-business/searchlight/doc/app-integration.md`

**Files in the new sibling repo after the spec is approved:**
- Create: `../searchlight_highlight/pubspec.yaml`
- Create: `../searchlight_highlight/README.md`
- Create: `../searchlight_highlight/lib/searchlight_highlight.dart`
- Create: `../searchlight_highlight/lib/src/excerpt_builder.dart`
- Create: `../searchlight_highlight/lib/src/range_adapter.dart`
- Create: `../searchlight_highlight/lib/src/text_span_adapter.dart`
- Create: `../searchlight_highlight/test/excerpt_builder_test.dart`
- Create: `../searchlight_highlight/test/range_adapter_test.dart`
- Create: `../searchlight_highlight/test/text_span_adapter_test.dart`

**Step 1: Write the package spec against Orama's package map and current core behavior**

The spec must decide:
- what remains in core vs what moves into the companion package
- whether this package wraps the core `Highlighter` instead of duplicating it
- whether Flutter-specific adapters are in scope now or deferred

Recommended direction:
- keep core highlighting primitives in `searchlight`
- make `searchlight_highlight` an additive ergonomics package

**Step 2: Save the highlight implementation plan**

The plan should sequence:
1. excerpt building from core highlight positions
2. safe text-range adapters
3. optional `TextSpan` adapter if Flutter dependency is explicitly accepted

If Flutter dependency is not accepted, split `TextSpan` helpers into a later
Flutter-specific package instead of polluting the pure Dart package.

**Step 3: Bootstrap the sibling repo**

Run:

```bash
cd /Users/jholt/development/jhd-business
dart create -t package searchlight_highlight
```

**Step 4: Start with the smallest TDD slice**

First failing test example:

```dart
test('excerpt builder trims around the highest-signal highlight span', () {
  final excerpt = buildExcerpt(
    text: 'one two three four five six seven',
    matches: [TextRange(start: 8, end: 13)],
    contextWords: 2,
  );
  expect(excerpt.text, 'two three four five');
});
```

Run:

```bash
cd ../searchlight_highlight
dart test test/excerpt_builder_test.dart
```

Expected:
- fail first

**Step 5: Commit**

Core repo:

```bash
git add docs/research/searchlight-highlight-package-spec.md docs/plans/2026-03-30-searchlight-highlight-implementation.md doc/app-integration.md
git commit -m "docs(highlight): define companion-package plan"
```

Sibling repo:

```bash
git add -A
git commit -m "chore: bootstrap searchlight_highlight"
```

## Task 5: `searchlight_pdf` Discovery, Spec, Then Bootstrap

**Files in this repo first:**
- Create: `/Users/jholt/development/jhd-business/searchlight/docs/research/searchlight-pdf-package-spec.md`
- Create: `/Users/jholt/development/jhd-business/searchlight/docs/research/searchlight-pdf-library-evaluation.md`
- Create: `/Users/jholt/development/jhd-business/searchlight/docs/plans/2026-03-30-searchlight-pdf-implementation.md`
- Modify: `/Users/jholt/development/jhd-business/searchlight/doc/app-integration.md`

**Files in the new sibling repo only after the discovery phase is accepted:**
- Create: `../searchlight_pdf/pubspec.yaml`
- Create: `../searchlight_pdf/README.md`
- Create: `../searchlight_pdf/lib/searchlight_pdf.dart`
- Create: `../searchlight_pdf/lib/src/models/pdf_search_document.dart`
- Create: `../searchlight_pdf/lib/src/pdf_loader.dart`
- Create: `../searchlight_pdf/lib/src/pdf_record_mapper.dart`
- Create: `../searchlight_pdf/test/pdf_record_mapper_test.dart`
- Create: `../searchlight_pdf/test/pdf_loader_test.dart`

**Step 1: Run the discovery phase before writing code**

The evaluation doc must answer:
- which Dart/Flutter PDF libraries can extract text reliably
- which platforms they support
- whether they expose page-level text geometry for in-view highlighting
- whether they can support user-imported and remotely downloaded PDFs

Do not start implementation before this decision is written down.

**Step 2: Write the package spec**

The spec must separate three concerns:
- PDF ingestion and text extraction
- mapping extracted text into Searchlight records
- optional page/position metadata for future in-view highlighting

The first version should target indexing and searching first. Do not promise
rendering integration in v1 unless the chosen library proves it.

**Step 3: Save the PDF implementation plan**

The plan should sequence:
1. library evaluation
2. fixture-driven extraction tests
3. page-to-record mapping
4. live local-file loading
5. search integration example
6. future geometry/highlighting extension notes

**Step 4: Bootstrap only after the spec is accepted**

Run:

```bash
cd /Users/jholt/development/jhd-business
dart create -t package searchlight_pdf
```

**Step 5: Start with mapper-first TDD**

First failing test example:

```dart
test('pdf page mapper emits one Searchlight-ready record per page', () {
  final records = mapPdfPagesToRecords(
    sourceId: 'sample.pdf',
    pages: [
      PdfPageText(pageNumber: 1, text: 'alpha'),
      PdfPageText(pageNumber: 2, text: 'beta'),
    ],
  );

  expect(records, hasLength(2));
  expect(records.first['page'], 1);
  expect(records.first['content'], 'alpha');
});
```

Run:

```bash
cd ../searchlight_pdf
dart test test/pdf_record_mapper_test.dart
```

Expected:
- fail first

**Step 6: Commit**

Core repo:

```bash
git add docs/research/searchlight-pdf-package-spec.md docs/research/searchlight-pdf-library-evaluation.md docs/plans/2026-03-30-searchlight-pdf-implementation.md doc/app-integration.md
git commit -m "docs(pdf): define package scope and evaluation plan"
```

Sibling repo:

```bash
git add -A
git commit -m "chore: bootstrap searchlight_pdf"
```

## Final Verification After Each Task

Run after every core-repo task:

```bash
cd /Users/jholt/development/jhd-business/searchlight
dart analyze
dart test
```

Run after every companion-package task:

```bash
dart analyze
dart test
dart pub publish --dry-run
```

## Expected Order Of Execution

1. Task 1: core publish gate
2. Task 2: extension contract freeze
3. Task 3: parsedoc spec, then parsedoc repo bootstrap
4. Task 4: highlight spec, then highlight repo bootstrap
5. Task 5: pdf discovery/spec, then pdf repo bootstrap

## Stop Conditions

- Do not start companion-package implementation until Tasks 1 and 2 are done.
- Do not start `searchlight_highlight` until `searchlight_parsedoc` has proven
  the companion-package model.
- Do not start `searchlight_pdf` implementation until the library evaluation
  and spec are written and accepted.
