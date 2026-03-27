# Search Validation Workflow

## Purpose

Document the practical validation loop for Searchlight so behavior can be
checked against realistic corpora while keeping the public repository clean.

## Orama Model (What We Mirror)

Orama core builds and searches indexes, but extraction is done by the host app
or plugin:

1. Read source files
2. Transform content into a record schema
3. Insert records into the search engine
4. Persist and reload the built index at runtime

Searchlight follows the same split: extraction in tooling, indexing in core.

## Searchlight Validation Data Split

Public-safe committed data:

- `packages/searchlight/test/fixtures/search_corpus.json`
- `packages/searchlight/test/fixtures/search_expectations.json`

Private local-only data (gitignored):

- `packages/searchlight/.local/source/` (copied local content)
- `packages/searchlight/.local/generated_search_corpus.json`
- `packages/searchlight/.local/generated_search_snapshot.json`

Rule: do not commit proprietary or copyrighted corpora.

## Regenerating Local Assets

From `packages/searchlight`:

```bash
dart run tool/build_validation_assets.dart
```

What the tool does:

1. Reads markdown files from `.local/source/`
2. Extracts records (`url`, `title`, `content`, `type`, `group`)
3. Caps content length for index size control
4. Builds a Searchlight database from those records
5. Writes corpus and snapshot JSON files to `.local/`

## How To Validate

Core integration tests:

```bash
dart test test/integration/search_fixture_loader_test.dart \
  test/integration/search_fixture_integration_test.dart \
  test/integration/local_validation_asset_generation_test.dart
```

Flutter web validation app:

1. Copy local generated assets into `packages/searchlight/example/assets/local/`
2. Run the example app and switch source mode

```bash
cd packages/searchlight/example
flutter run -d chrome
```

## Package Roadmap Context

Current package:

- `packages/searchlight` (core)

Planned future packages:

- `searchlight_flutter` (UI/rendering helpers and widgets)
- `searchlight_pdf` (PDF extraction adapters)
