# Phase 8 Findings

## Codebase State
- Barrel file currently exports internal tree implementations and scoring internals
- No `document_adapter.dart` exists yet
- No integration test directory exists
- No README.md exists
- `stop_words.dart` exports `englishStopWords` (not `stopWordsForLanguage`)
- `format.dart` exports `currentFormatVersion` and `PersistenceFormat`
