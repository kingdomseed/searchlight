# Searchlight Validation Workflow

Searchlight includes a lightweight validation workflow for checking search
behavior against realistic corpora without committing private source material.

## Public and Private Validation Data

Committed public-safe data:

- `test/fixtures/search_corpus.json`
- `test/fixtures/search_expectations.json`

Local private data:

- `.local/source/`
- `.local/generated_search_corpus.json`
- `.local/generated_search_snapshot.json`

Only public-safe fixture data should be committed.

## Generate Local Validation Assets

From the repository root:

```bash
dart run example/tool/build_validation_assets.dart
```

The tool:

1. reads markdown files from `.local/source/`
2. converts them into records with `url`, `title`, `content`, `type`, and
   `group`
3. builds a Searchlight index from those records
4. writes both a raw corpus JSON file and a persisted snapshot JSON file

Then copy the generated files into `assets/local/` if you want to run
the Flutter validation app with those local assets.

## Validate in Tests

Run the core package checks:

```bash
dart analyze
dart test
```

Integration coverage includes:

- fixture loading and schema validation
- search behavior against the public corpus
- local asset generation and snapshot round-tripping

## Validate in the Example App

From `example/`:

```bash
flutter pub get
flutter run -d chrome
```

The example app can validate:

- raw fixture corpus loading
- desktop folder indexing from live `.md` files on macOS, Windows, and Linux
- local generated corpus loading
- local generated snapshot restore
- highlighted excerpt rendering over search hits

For desktop folder validation on macOS:

```bash
cd example
flutter run -d macos
```
