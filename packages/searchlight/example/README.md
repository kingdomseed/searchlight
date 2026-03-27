# Searchlight Validation Example

This example app is a thin Flutter web harness for validating how Searchlight
behaves with realistic content records.

It is not intended to be a production search UI package. Its job is to make it
easy to verify:

- corpus extraction output
- index build and restore behavior
- query behavior over `title` and `content`
- excerpt highlighting in UI

## Data Sources

The app supports three modes:

- `Public fixture`: loads `assets/search_corpus.json` and builds an in-memory
  index
- `Local corpus asset`: loads `assets/local/generated_search_corpus.json` and
  builds an in-memory index
- `Local snapshot asset`: loads
  `assets/local/generated_search_snapshot.json` and restores a saved index

The default mode is `Public fixture`.

## Run the App

From `packages/searchlight/example`:

```bash
flutter pub get
flutter run -d chrome
```

## Verify the Example

From `packages/searchlight/example`:

```bash
flutter test
flutter build web
```

## Local Asset Workflow

Generate local assets from the package root:

```bash
cd ..
dart run tool/build_validation_assets.dart
```

Copy the generated files into this example app:

- `../.local/generated_search_corpus.json` ->
  `assets/local/generated_search_corpus.json`
- `../.local/generated_search_snapshot.json` ->
  `assets/local/generated_search_snapshot.json`

If the local files are still placeholders, the app fails with a clear
configuration error instead of pretending the local corpus loaded correctly.

## Why Both Corpus and Snapshot Modes Exist

`Local corpus asset` validates the extraction output directly.

`Local snapshot asset` validates the persisted-index path that a production app
would usually prefer for faster startup.

## Related Docs

- `../README.md`
- `../doc/app-integration.md`
- `../doc/validation-workflow.md`
