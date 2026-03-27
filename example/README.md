# Searchlight Validation Example

This example app is a Flutter validation harness for checking how Searchlight
behaves with realistic content records and live markdown folders.

It is not intended to be a production search UI package. Its job is to make it
easy to verify:

- corpus extraction output
- live folder extraction and indexing
- index build and restore behavior
- query behavior over `title` and `content`
- excerpt highlighting in UI

The core `searchlight` package itself is pure Dart and is not limited to
Flutter. This example is only a validation harness.

## Data Sources

The app supports four modes:

- `Public fixture`: loads `assets/search_corpus.json` and builds an in-memory
  index
- `Desktop folder`: picks a local folder, recursively reads `.md` files, and
  builds an in-memory index from live content
- `Local corpus asset`: loads `assets/local/generated_search_corpus.json` and
  builds an in-memory index
- `Local snapshot asset`: loads
  `assets/local/generated_search_snapshot.json` and restores a saved index

The default mode is `Public fixture`.

`Desktop folder` is only available on desktop builds. Web and mobile builds
still show the mode, but folder picking itself is intentionally desktop-only.

Supported formats in this example:

- live `.md` files in desktop folder mode
- JSON corpus assets in fixture/local corpus modes
- JSON snapshot assets in local snapshot mode

This example does not currently parse HTML, PDF, CSV, or XML sources.

## Run the App

From `example/`:

```bash
flutter pub get
flutter run -d chrome
```

For desktop folder validation on macOS:

```bash
flutter run -d macos
```

## Verify the Example

From `example/`:

```bash
flutter test
flutter build web
```

Desktop smoke validation:

```bash
flutter build macos
```

## Local Asset Workflow

Generate local assets from the repository root:

```bash
dart run example/tool/build_validation_assets.dart
```

Or, from `example/` directly:

```bash
dart run tool/build_validation_assets.dart
```

Copy the generated files from `.local/` into this example app:

- `.local/generated_search_corpus.json` ->
  `assets/local/generated_search_corpus.json`
- `.local/generated_search_snapshot.json` ->
  `assets/local/generated_search_snapshot.json`

If the local files are still placeholders, the app fails with a clear
configuration error instead of pretending the local corpus loaded correctly.

## Why Both Corpus and Snapshot Modes Exist

`Desktop folder` validates the live extraction path that many desktop apps will
use during development or local import flows.

`Local corpus asset` validates the extraction output directly.

`Local snapshot asset` validates the persisted-index path that a production app
would usually prefer for faster startup.

## Related Docs

- `../README.md`
- `../doc/app-integration.md`
- `../doc/validation-workflow.md`
