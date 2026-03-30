# Searchlight Validation Workflow

Searchlight includes a lightweight validation workflow for checking search
behavior against realistic corpora without committing private source material.

## Canonical Validation Sequence

From the repository root:

```bash
dart analyze
dart test
dart pub publish --dry-run
```

From `example/`:

```bash
flutter pub get
flutter analyze
flutter test
flutter build web
flutter build macos
```

Use that sequence as the canonical validation pass before major refactors,
publish work, or companion-package extraction.

## Public and Private Validation Data

Committed public-safe data:

- `test/fixtures/search_corpus.json`
- `test/fixtures/search_expectations.json`

Local private data:

- `.local/source/`
- `.local/generated_search_corpus.json`
- `.local/generated_search_snapshot.json`

Only public-safe fixture data should be committed.

## What Each Validation Path Proves

- public fixture corpus:
  committed safe records that prove the default in-memory indexing path
- local generated corpus:
  generated extracted records that prove your extraction output before
  persistence
- local generated snapshot:
  generated persisted index data that proves the restore path you will usually
  prefer in production

The example app is designed to make those three paths easy to compare.

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

The generator always writes those files to the package-root `.local/`
directory, even when you run it from `example/`.

Then copy the generated files into `example/assets/local/` if you want to run
the Flutter validation app with those local assets.

## Validate in Tests

Run the core package checks:

```bash
dart analyze
dart test
```

The root `dart analyze` intentionally excludes the nested Flutter `example/`
package. Analyze the example separately with Flutter tooling.

Integration coverage includes:

- fixture loading and schema validation
- search behavior against the public corpus
- local asset generation and snapshot round-tripping

## Validate in the Example App

From `example/`:

```bash
flutter pub get
flutter analyze
flutter run -d chrome
```

The example app can validate:

- raw fixture corpus loading
- desktop folder indexing from live `.md` files on macOS, Windows, and Linux
- local generated corpus loading
- local generated snapshot restore
- excerpt match computation over search hits through `searchlight_highlight`

See [example/README.md](../example/README.md) for the manual verification
checklist inside the app.

For desktop folder validation on macOS:

```bash
cd example
flutter run -d macos
```
