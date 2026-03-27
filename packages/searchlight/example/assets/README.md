# Search Validation Assets

This example app uses `assets/search_corpus.json` by default.

Optional local validation modes are available for:

- `assets/local/generated_search_corpus.json`
- `assets/local/generated_search_snapshot.json`

To use local mode with real copied content:

1. Generate assets in the package root:
   `dart run tool/build_validation_assets.dart`
2. Copy generated files from:
   `../.local/generated_search_corpus.json`
   `../.local/generated_search_snapshot.json`
3. Into this example app:
   `assets/local/generated_search_corpus.json`
   `assets/local/generated_search_snapshot.json`

If local files are missing or invalid, the app shows an error and no results.
