# Searchlight Validation Example

Thin Flutter web app for validating Searchlight behavior against fixture data.

Default mode:
- loads `assets/search_corpus.json`
- builds an in-memory Searchlight index
- searches `title` and `content` fields

Optional local modes:
- `assets/local/generated_search_corpus.json`
- `assets/local/generated_search_snapshot.json`

Generate local assets from package root:

```bash
cd ..
dart run tool/build_validation_assets.dart
```

Then copy generated files from `../.local/` into `example/assets/local/`.
