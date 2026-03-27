# Local Validation Assets

This directory is for local-only search validation data and generated artifacts.

Expected layout:

- `.local/source/` copied source content for extraction (markdown files)
- `.local/generated_search_corpus.json` generated corpus records
- `.local/generated_search_snapshot.json` generated Searchlight snapshot

Generate assets from package root:

```bash
dart run tool/build_validation_assets.dart
```

Notes:

- This directory is gitignored by repository root config.
- Keep proprietary or copyrighted content local only.
