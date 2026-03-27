# Search Validation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a public-safe corpus, deterministic integration tests, local corpus/index generation tooling, and a thin Flutter web example so Searchlight can be validated with the same extraction-to-indexing flow used by Orama integrations.

**Architecture:** Keep the core package as the only production package for now. Add a repo-owned record schema for validation data, exercise it through `Searchlight.create()` and persistence APIs in tests, and add local tooling that converts copied source content into records or a serialized snapshot under `.local/`. The Flutter app under `packages/searchlight/example` should consume the same public fixture contract by default and optionally switch to a local generated asset.

**Tech Stack:** Dart, Flutter (example app only), JSON fixtures, existing `Searchlight` APIs (`create`, `search`, `toJson`/`fromJson`, `persist`/`restore`), existing highlighter, gitignored local assets.

---

### Task 1: Public Fixture Contract And Loader

**Files:**
- Modify: `.gitignore`
- Create: `packages/searchlight/test/fixtures/search_corpus.json`
- Create: `packages/searchlight/test/fixtures/search_expectations.json`
- Create: `packages/searchlight/test/fixtures/README.md`
- Create: `packages/searchlight/test/helpers/search_fixture_loader.dart`
- Test: `packages/searchlight/test/integration/search_fixture_loader_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:test/test.dart';

import '../helpers/search_fixture_loader.dart';

void main() {
  test('loads public search corpus and expectations', () async {
    final fixture = await loadSearchFixture();

    expect(fixture.records, isNotEmpty);
    expect(fixture.records.first['title'], isA<String>());
    expect(fixture.expectations, isNotEmpty);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `dart test test/integration/search_fixture_loader_test.dart`

Expected: FAIL because the loader and fixture files do not exist yet.

**Step 3: Write minimal implementation**

- Add `packages/searchlight/test/fixtures/search_corpus.json` with a public-safe, generalized dataset using the record schema:

```json
[
  {
    "url": "/guide/spells/ember-lance",
    "title": "Ember Lance",
    "content": "A precise fire spell that launches a concentrated spear of heat.",
    "type": "spell",
    "group": "fire"
  }
]
```

- Add `packages/searchlight/test/fixtures/search_expectations.json` with representative expected queries:

```json
[
  {
    "name": "spell title query",
    "term": "ember lance",
    "properties": ["title", "content"],
    "expectedTopUrl": "/guide/spells/ember-lance"
  }
]
```

- Add `packages/searchlight/test/helpers/search_fixture_loader.dart` with a minimal loader that reads both JSON files from disk and returns typed records/expectations.
- Update `.gitignore` to include:

```gitignore
packages/searchlight/.local/
```

**Step 4: Run test to verify it passes**

Run: `dart test test/integration/search_fixture_loader_test.dart`

Expected: PASS

**Step 5: Commit**

```bash
git add .gitignore packages/searchlight/test/fixtures packages/searchlight/test/helpers/search_fixture_loader.dart packages/searchlight/test/integration/search_fixture_loader_test.dart
git commit -m "test: add public search fixture contract"
```

### Task 2: Dataset-Backed Search And Persistence Tests

**Files:**
- Create: `packages/searchlight/test/integration/search_fixture_integration_test.dart`
- Modify: `packages/searchlight/test/helpers/search_fixture_loader.dart`
- Modify: `packages/searchlight/test/fixtures/search_expectations.json`

**Step 1: Write the failing test**

```dart
import 'package:searchlight/searchlight.dart';
import 'package:test/test.dart';

import '../helpers/search_fixture_loader.dart';

void main() {
  test('public fixture queries return expected top hits', () async {
    final fixture = await loadSearchFixture();
    final db = Searchlight.create(
      schema: Schema({
        'url': const TypedField(SchemaType.string),
        'title': const TypedField(SchemaType.string),
        'content': const TypedField(SchemaType.string),
        'type': const TypedField(SchemaType.enumType),
        'group': const TypedField(SchemaType.enumType),
      }),
    );

    for (final record in fixture.records) {
      db.insert(record);
    }

    for (final query in fixture.expectations) {
      final result = db.search(
        term: query.term,
        properties: query.properties,
        limit: query.limit,
      );
      expect(result.hits.first.document.getString('url'), query.expectedTopUrl);
    }
  });
}
```

**Step 2: Run test to verify it fails**

Run: `dart test test/integration/search_fixture_integration_test.dart`

Expected: FAIL because at least one expectation is not yet calibrated or the loader is not yet typed enough to drive the test.

**Step 3: Write minimal implementation**

- Expand the loader to return typed `SearchFixtureRecord` and `SearchFixtureExpectation` models.
- Flesh out `search_expectations.json` with cases that cover:
  - title match
  - content match
  - mixed title/content search via `properties`
  - enum filter sanity using `where`
  - highlighting sanity by checking `Highlighter().highlight(content, term).positions`
  - JSON persistence sanity via `db.toJson()` and `Searchlight.fromJson(...)`

**Step 4: Run targeted tests to verify they pass**

Run: `dart test test/integration/search_fixture_integration_test.dart`

Expected: PASS

**Step 5: Run broader verification**

Run: `dart test`

Expected: PASS

**Step 6: Commit**

```bash
git add packages/searchlight/test/helpers/search_fixture_loader.dart packages/searchlight/test/fixtures/search_expectations.json packages/searchlight/test/integration/search_fixture_integration_test.dart
git commit -m "test: validate searchlight against public search corpus"
```

### Task 3: Local Corpus And Snapshot Generation Tooling

**Files:**
- Create: `packages/searchlight/tool/build_validation_assets.dart`
- Create: `packages/searchlight/.local/.gitkeep`
- Create: `packages/searchlight/.local/README.md`
- Create: `packages/searchlight/test/integration/local_validation_asset_generation_test.dart`
- Modify: `packages/searchlight/pubspec.yaml`

**Step 1: Write the failing test**

```dart
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('generator writes validation corpus and snapshot to .local', () async {
    final corpusFile = File('.local/generated_search_corpus.json');
    final snapshotFile = File('.local/generated_search_snapshot.json');

    expect(await corpusFile.exists(), isTrue);
    expect(await snapshotFile.exists(), isTrue);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `dart test test/integration/local_validation_asset_generation_test.dart`

Expected: FAIL because no generation tool has run and the local files do not exist.

**Step 3: Write minimal implementation**

- Add `packages/searchlight/tool/build_validation_assets.dart` that:
  - reads copied local source content from a repo-local input directory such as `.local/source/`
  - extracts records into the shared schema: `url`, `title`, `content`, `type`, `group`
  - caps content length when configured
  - builds a `Searchlight` database
  - writes:
    - `.local/generated_search_corpus.json`
    - `.local/generated_search_snapshot.json`
- If YAML support is needed for glossary-style sources, add the smallest dependency necessary and document it in `pubspec.yaml`.
- Keep the generator aligned with the Nimblenomicon/Orama pattern:

```dart
final db = Searchlight.create(schema: schema);
for (final record in records) {
  db.insert(record);
}
await File(corpusPath).writeAsString(jsonEncode(records));
await File(snapshotPath).writeAsString(db.toJson());
```

**Step 4: Run the tool manually**

Run: `dart run tool/build_validation_assets.dart`

Expected: Generates `.local/generated_search_corpus.json` and `.local/generated_search_snapshot.json`

**Step 5: Run the test to verify it passes**

Run: `dart test test/integration/local_validation_asset_generation_test.dart`

Expected: PASS after generation

**Step 6: Commit**

```bash
git add packages/searchlight/tool/build_validation_assets.dart packages/searchlight/.local/.gitkeep packages/searchlight/.local/README.md packages/searchlight/test/integration/local_validation_asset_generation_test.dart packages/searchlight/pubspec.yaml .gitignore
git commit -m "feat: add local search validation asset generator"
```

### Task 4: Thin Flutter Web Validation App

**Files:**
- Create: `packages/searchlight/example/pubspec.yaml`
- Create: `packages/searchlight/example/analysis_options.yaml`
- Create: `packages/searchlight/example/lib/main.dart`
- Create: `packages/searchlight/example/assets/search_corpus.json`
- Create: `packages/searchlight/example/assets/README.md`
- Create: `packages/searchlight/example/test/widget_test.dart`

**Step 1: Write the failing widget test**

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:searchlight_example/main.dart';

void main() {
  testWidgets('shows seeded results for a corpus query', (tester) async {
    await tester.pumpWidget(const SearchValidationApp());

    await tester.enterText(find.byType(TextField), 'ember');
    await tester.pumpAndSettle();

    expect(find.text('Ember Lance'), findsOneWidget);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/widget_test.dart`

Expected: FAIL because the example app does not exist yet.

**Step 3: Write minimal implementation**

- Create a small Flutter example app inside `packages/searchlight/example`.
- Load the public fixture from assets by default.
- Build the `Searchlight` instance in memory from those records.
- Add:
  - search `TextField`
  - results list
  - basic excerpt rendering
  - optional highlight rendering using the existing `Highlighter`
- Add a small switch or debug setting that can use `.local/generated_search_corpus.json` or `.local/generated_search_snapshot.json` when copied into example assets for local runs.

**Step 4: Run widget test to verify it passes**

Run: `flutter test test/widget_test.dart`

Expected: PASS

**Step 5: Run web build verification**

Run: `flutter build web`

Expected: successful web build for the validation app

**Step 6: Commit**

```bash
git add packages/searchlight/example
git commit -m "feat: add flutter web search validation example"
```

### Task 5: Public Documentation And Workflow Notes

**Files:**
- Modify: `packages/searchlight/README.md`
- Create: `packages/searchlight/example/README.md`
- Create: `docs/research/search-validation-workflow.md`

**Step 1: Write the failing docs check**

Use a manual failing condition: before editing docs, confirm the repo does not explain:

- the public-safe corpus constraint
- the local `.local/` private validation workflow
- the Orama-style extraction/index-generation model
- that `searchlight_flutter` and `searchlight_pdf` are future packages

**Step 2: Update docs**

- Add a README section describing:
  - public corpus fixtures
  - local generator workflow
  - example app purpose
- Add `packages/searchlight/example/README.md` with run instructions:

```bash
flutter pub get
flutter run -d chrome
```

- Add `docs/research/search-validation-workflow.md` documenting:
  - how Orama handles extraction vs indexing
  - how Searchlight mirrors that flow
  - where to place copied local content
  - how to regenerate local corpus/snapshot files

**Step 3: Run verification**

Run:

```bash
dart analyze
dart test
```

And for the example app:

```bash
cd packages/searchlight/example
flutter test
flutter build web
```

Expected: all verification commands pass

**Step 4: Commit**

```bash
git add packages/searchlight/README.md packages/searchlight/example/README.md docs/research/search-validation-workflow.md
git commit -m "docs: add search validation workflow"
```

### Task 6: Final End-To-End Review

**Files:**
- Review only

**Step 1: Run final project verification**

Run:

```bash
cd packages/searchlight
dart analyze
dart test
```

Then, if Flutter is available:

```bash
cd packages/searchlight/example
flutter test
flutter build web
```

**Step 2: Sanity-check local asset flow**

Run:

```bash
cd packages/searchlight
dart run tool/build_validation_assets.dart
```

Then confirm that the example app can be pointed at the generated local assets.

**Step 3: Commit any final cleanup**

```bash
git add -A
git commit -m "chore: finalize search validation workflow"
```
