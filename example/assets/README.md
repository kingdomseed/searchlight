# Search Validation Assets

This example app uses `assets/search_corpus.json` by default.

Optional local validation modes are available for:

- `assets/local/generated_search_corpus.json`
- `assets/local/generated_search_snapshot.json`

The desktop app can also index a live markdown folder directly without these
copied assets.

To validate the local asset modes with copied content:

1. Generate assets from `example/` with
   `dart run tool/build_validation_assets.dart`.
2. Copy these files from `.local/`:
   `generated_search_corpus.json`
   `generated_search_snapshot.json`
3. Replace the placeholder files in `assets/local/`.

If local files are missing or invalid, the app shows an error and no results.
