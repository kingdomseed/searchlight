# Searchlight Parsedoc Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build `searchlight_parsedoc` as a pure Dart companion package that parses Markdown and HTML into normalized document/block models and maps them into Searchlight-ready records.

**Architecture:** Keep parsing outside `searchlight` core, matching the open-source Orama package boundary. Implement string-first parse APIs, then layer VM file helpers and Searchlight record mappers on top of the same normalized parsed-document model so the package stays portable and easy to test.

**Tech Stack:** Dart 3, pure Dart package, `test`, HTML/Markdown parsing dependencies selected during bootstrap, Searchlight record-shape helpers, GitHub.

---

## Global Rules

- Build this in the local companion workspace
  `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc`.
- Keep the repo pure Dart. Do not add Flutter.
- Match the Orama parsedoc boundary where source behavior is clear.
- Do not add PDF, globbing, recursive directory crawling, or front matter in
  v1.
- Do not add automatic Searchlight database creation or auto-insert helpers in
  v1. This package stops at parsed models and plain record maps.
- Keep TDD honest: one failing test, one minimal implementation, rerun, then
  continue.
- Prefer string-based parse APIs as the core implementation. File helpers should
  be thin wrappers.
- Treat the ordered block list as the core contract. `title`, `plainText`, and
  `bodyText` are convenience layers above flat extracted blocks, not a promise
  of rich document semantics.

## Task 1: Bootstrap The Package And Public Surface

**Files:**
- Create: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/pubspec.yaml`
- Create: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/README.md`
- Create: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/lib/searchlight_parsedoc.dart`
- Create: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/test/public_api_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:searchlight_parsedoc/searchlight_parsedoc.dart';
import 'package:test/test.dart';

void main() {
  test('public library exports parsed document types and parser entry points', () {
    expect(ParsedFormat.values, isNotEmpty);
    expect(parseMarkdownString, isA<Function>());
    expect(parseHtmlString, isA<Function>());
  });
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd /Users/jholt/development/jhd-business/searchlight/.companions
dart create -t package searchlight_parsedoc
cd /Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc
dart test test/public_api_test.dart
```

Expected:
- FAIL because the public API does not exist yet

**Step 3: Write minimal implementation**

- Set package metadata and description
- Add the library barrel
- Declare the initial public types and function signatures

**Step 4: Run test to verify it passes**

Run:

```bash
cd /Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc
dart test test/public_api_test.dart
dart analyze
```

Expected:
- PASS
- analyzer clean

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: bootstrap parsedoc package surface"
```

## Task 2: Add The Parsed Document Model

**Files:**
- Modify: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/lib/searchlight_parsedoc.dart`
- Create: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/lib/src/models/parsed_document.dart`
- Test: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/test/models/parsed_document_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:searchlight_parsedoc/searchlight_parsedoc.dart';
import 'package:test/test.dart';

void main() {
  test('parsed document derives plainText and bodyText from ordered blocks', () {
    final doc = ParsedDocument(
      format: ParsedFormat.markdown,
      sourcePath: 'docs/sample.md',
      title: 'Sample',
      blocks: const [
        ParsedBlock(tag: 'h1', text: 'Sample', path: 'root.body[0]'),
        ParsedBlock(tag: 'p', text: 'First paragraph.', path: 'root.body[1]'),
        ParsedBlock(tag: 'p', text: 'Second paragraph.', path: 'root.body[2]'),
      ],
    );

    expect(doc.plainText, 'Sample First paragraph. Second paragraph.');
    expect(doc.bodyText, 'First paragraph. Second paragraph.');
  });
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd /Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc
dart test test/models/parsed_document_test.dart
```

Expected:
- FAIL because the model types are incomplete

**Step 3: Write minimal implementation**

- Add `ParsedFormat`
- Add `ParsedBlock`
- Add `ParsedDocument`
- Implement the derived text getters and basic normalization
- Document in code comments that this is a Searchlight convenience wrapper over
  flat extracted blocks, not a semantic document tree

**Step 4: Run test to verify it passes**

Run:

```bash
cd /Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc
dart test test/models/parsed_document_test.dart
dart analyze
```

Expected:
- PASS
- analyzer clean

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add parsed document model"
```

## Task 3: Implement Markdown String Parsing

**Files:**
- Modify: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/lib/searchlight_parsedoc.dart`
- Create: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/lib/src/parsers/markdown_parser.dart`
- Create: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/test/fixtures/sample.md`
- Test: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/test/parsers/markdown_parser_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:searchlight_parsedoc/searchlight_parsedoc.dart';
import 'package:test/test.dart';

void main() {
  test('parseMarkdownString extracts title and paragraph blocks in order', () async {
    final doc = await parseMarkdownString('''
# Ember Lance

A focused lance of heat.

## Notes

Works best on dry brush.
''');

    expect(doc.format, ParsedFormat.markdown);
    expect(doc.title, 'Ember Lance');
    expect(doc.blocks.map((block) => block.tag), ['h1', 'p', 'h2', 'p']);
    expect(doc.bodyText, contains('A focused lance of heat.'));
  });
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd /Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc
dart test test/parsers/markdown_parser_test.dart
```

Expected:
- FAIL because Markdown parsing is not implemented

**Step 3: Write minimal implementation**

- Choose the Markdown parsing dependency
- Convert Markdown into a traversable structure
- Emit ordered blocks
- Promote the first extracted `h1` block to `title`

**Step 4: Run test to verify it passes**

Run:

```bash
cd /Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc
dart test test/parsers/markdown_parser_test.dart
dart analyze
```

Expected:
- PASS
- analyzer clean

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: parse markdown strings"
```

## Task 4: Implement HTML String Parsing

**Files:**
- Modify: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/lib/searchlight_parsedoc.dart`
- Create: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/lib/src/parsers/html_parser.dart`
- Create: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/test/fixtures/sample.html`
- Test: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/test/parsers/html_parser_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:searchlight_parsedoc/searchlight_parsedoc.dart';
import 'package:test/test.dart';

void main() {
  test('parseHtmlString prefers the document title and preserves block paths', () async {
    final doc = await parseHtmlString('''
<!doctype html>
<html>
  <head><title>Fire Ledger</title></head>
  <body>
    <h1>Ignored Title Block</h1>
    <p>First note.</p>
  </body>
</html>
''');

    expect(doc.format, ParsedFormat.html);
    expect(doc.title, 'Fire Ledger');
    expect(doc.blocks.first.path, isNotEmpty);
    expect(doc.plainText, contains('First note.'));
  });
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd /Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc
dart test test/parsers/html_parser_test.dart
```

Expected:
- FAIL because HTML parsing is not implemented

**Step 3: Write minimal implementation**

- Choose the HTML parsing dependency
- Walk text-bearing elements in order
- Preserve structural paths and attributes
- Prefer `<title>` when extracting document title

**Step 4: Run test to verify it passes**

Run:

```bash
cd /Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc
dart test test/parsers/html_parser_test.dart
dart analyze
```

Expected:
- PASS
- analyzer clean

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: parse html strings"
```

## Task 5: Add Merge Strategy And Transform Support

**Files:**
- Modify: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/lib/searchlight_parsedoc.dart`
- Modify: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/lib/src/parsers/markdown_parser.dart`
- Modify: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/lib/src/parsers/html_parser.dart`
- Create: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/lib/src/models/parsed_node.dart`
- Test: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/test/parsers/merge_strategy_test.dart`
- Test: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/test/parsers/transform_test.dart`

**Step 1: Write the failing tests**

```dart
test('mergeStrategy merge combines consecutive sibling paragraphs', () async {
  final doc = await parseHtmlString(
    '<div><p>First</p><p>Second</p></div>',
    options: const ParseOptions(mergeStrategy: MergeStrategy.merge),
  );

  expect(doc.blocks.length, 1);
  expect(doc.blocks.single.text, 'First Second');
});
```

```dart
test('transform can rewrite raw markup before blocks are emitted', () async {
  final doc = await parseHtmlString(
    '<h1>Hello</h1>',
    options: ParseOptions(
      transform: (node, context) =>
          node.tag == 'h1' ? node.copyWith(rawMarkup: '<div><p>Converted</p></div>') : node,
    ),
  );

  expect(doc.blocks.single.tag, 'p');
  expect(doc.blocks.single.text, 'Converted');
});
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc
dart test test/parsers/merge_strategy_test.dart
dart test test/parsers/transform_test.dart
```

Expected:
- FAIL because merge and transform behavior is not implemented yet

**Step 3: Write minimal implementation**

- Add `MergeStrategy`
- Add parse options and transform callback types
- Match the Orama precedence rule where raw-markup rewrites win over tag/text
  rewrites
- Preserve deterministic block ordering
- Keep the transform surface narrow: no plugin system inside parsedoc

**Step 4: Run tests to verify they pass**

Run:

```bash
cd /Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc
dart test test/parsers/merge_strategy_test.dart
dart test test/parsers/transform_test.dart
dart analyze
```

Expected:
- PASS
- analyzer clean

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add parsedoc merge and transform options"
```

## Task 6: Add Searchlight Record Mapping Helpers

**Files:**
- Modify: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/lib/searchlight_parsedoc.dart`
- Create: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/lib/src/mappers/searchlight_record_mapper.dart`
- Test: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/test/mappers/searchlight_record_mapper_test.dart`

**Step 1: Write the failing tests**

```dart
import 'package:searchlight_parsedoc/searchlight_parsedoc.dart';
import 'package:test/test.dart';

void main() {
  test('document mapper emits one Searchlight-ready record', () {
    final doc = ParsedDocument(
      format: ParsedFormat.markdown,
      sourcePath: 'docs/ember.md',
      title: 'Ember Lance',
      blocks: const [
        ParsedBlock(tag: 'p', text: 'A focused lance of heat.', path: 'root.body[0]'),
      ],
    );

    final record = SearchlightDocumentRecordMapper().map(
      id: 'ember-lance',
      document: doc,
    );

    expect(record['title'], 'Ember Lance');
    expect(record['content'], 'A focused lance of heat.');
    expect(record['sourcePath'], 'docs/ember.md');
  });
}
```

```dart
test('block mapper emits one record per parsed block with structural fields', () {
  final doc = ParsedDocument(
    format: ParsedFormat.html,
    sourcePath: 'docs/page.html',
    blocks: const [
      ParsedBlock(tag: 'p', text: 'Hello', path: 'root.body[0]'),
      ParsedBlock(tag: 'li', text: 'World', path: 'root.body[1]'),
    ],
  );

  final records = SearchlightBlockRecordMapper().map(
    documentId: 'page',
    document: doc,
  );

  expect(records, hasLength(2));
  expect(records.first['tag'], 'p');
  expect(records.first['path'], 'root.body[0]');
});
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc
dart test test/mappers/searchlight_record_mapper_test.dart
```

Expected:
- FAIL because mapping helpers do not exist yet

**Step 3: Write minimal implementation**

- Add a document-level mapper
- Add a block-level mapper
- Keep the output as plain `Map<String, Object?>` records so callers can fit
  their own Searchlight schema
- Do not couple these helpers to Searchlight database creation or insertion

**Step 4: Run tests to verify they pass**

Run:

```bash
cd /Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc
dart test test/mappers/searchlight_record_mapper_test.dart
dart analyze
```

Expected:
- PASS
- analyzer clean

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Searchlight record mapping helpers"
```

## Task 7: Add Live File Parsing Helpers

**Files:**
- Modify: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/lib/searchlight_parsedoc.dart`
- Create: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/lib/src/io/file_parsers.dart`
- Create: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/test/fixtures/live.md`
- Create: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/test/fixtures/live.html`
- Test: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/test/io/file_parsers_test.dart`

**Step 1: Write the failing tests**

```dart
import 'package:searchlight_parsedoc/searchlight_parsedoc.dart';
import 'package:test/test.dart';

void main() {
  test('parseMarkdownFile reads a live markdown file and preserves sourcePath', () async {
    final doc = await parseMarkdownFile('test/fixtures/live.md');
    expect(doc.sourcePath, 'test/fixtures/live.md');
    expect(doc.title, isNotNull);
  });

  test('parseFile rejects unsupported extensions', () async {
    expect(
      () => parseFile('test/fixtures/unsupported.txt'),
      throwsA(isA<UnsupportedParsedocFileTypeError>()),
    );
  });

  test('parseHtmlString returns an empty parsed document for empty input', () async {
    final doc = await parseHtmlString('');
    expect(doc.blocks, isEmpty);
    expect(doc.title, isNull);
  });
}
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc
dart test test/io/file_parsers_test.dart
```

Expected:
- FAIL because file helpers do not exist yet

**Step 3: Write minimal implementation**

- Add VM-only file wrappers around the string parsers
- Infer supported types from extension
- Add typed package errors
- Lock the empty-input contract and use the same rule across file and string
  APIs

**Step 4: Run tests to verify they pass**

Run:

```bash
cd /Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc
dart test test/io/file_parsers_test.dart
dart analyze
```

Expected:
- PASS
- analyzer clean

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add parsedoc live file helpers"
```

## Task 8: Finish README And End-To-End Verification

**Files:**
- Modify: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/README.md`
- Test: `/Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc/test/public_api_test.dart`

**Step 1: Write the failing test**

```dart
test('README example API stays compile-valid', () async {
  final doc = await parseMarkdownString('# Ember Lance');
  final record = SearchlightDocumentRecordMapper().map(
    id: 'ember-lance',
    document: doc,
  );

  expect(record['title'], 'Ember Lance');
});
```

**Step 2: Run test to verify it fails only if the docs drift**

Run:

```bash
cd /Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc
dart test test/public_api_test.dart
```

Expected:
- PASS once the public API is stable
- this test becomes the README regression guard

**Step 3: Write the README**

The README must cover:

- package purpose
- supported formats: Markdown and HTML only
- string parsing example
- live file parsing example
- Searchlight record mapping example
- explicit note that callers still insert the resulting records into
  `searchlight` themselves
- platform note for web vs `dart:io`
- explicit non-goals: PDF, globbing, front matter

**Step 4: Run the full verification suite**

Run:

```bash
cd /Users/jholt/development/jhd-business/searchlight/.companions/searchlight_parsedoc
dart format .
dart analyze
dart test
dart pub publish --dry-run
```

Expected:
- formatter makes no semantic changes
- analyzer clean
- all tests pass
- publish dry run has no blocking issues

**Step 5: Commit**

```bash
git add -A
git commit -m "docs: finish parsedoc package README"
```
