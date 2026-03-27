# Searchlight Validation Example

Thin Flutter web app for validating Searchlight behavior against fixture data.

Default behavior:
- Loads `assets/search_corpus.json` (public fixture)
- Builds an in-memory Searchlight index
- Searches `title` and `content` fields
- Renders result titles, URLs, and highlighted excerpts

Optional local modes:
- `assets/local/generated_search_corpus.json`
- `assets/local/generated_search_snapshot.json`

## Run

From this directory:

```bash
flutter pub get
flutter run -d chrome
```

Validation checks:

```bash
flutter test test/widget_test.dart
flutter build web
```

## Local Asset Workflow

Generate local assets from the package root (`packages/searchlight`):

```bash
cd ..
dart run tool/build_validation_assets.dart
```

Then copy generated files from `../.local/` into `assets/local/`:

- `../.local/generated_search_corpus.json` -> `assets/local/generated_search_corpus.json`
- `../.local/generated_search_snapshot.json` -> `assets/local/generated_search_snapshot.json`

Local modes intentionally fail with a clear error if placeholder assets are
still in place.
