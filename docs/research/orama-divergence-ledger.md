# Searchlight vs Orama Divergence Ledger

**Last updated:** 2026-03-29

This document is the publish gate for Orama-related claims in `searchlight`.
If a behavior is not listed here as matched, it should be treated as either an
intentional divergence or an unresolved gap.

## Matched or materially aligned

- external string document IDs with internal integer IDs
- schema-first validation that ignores extra record properties
- `enum` / `enum[]` acceptance for string and numeric values
- batch insert abort semantics
- `remove()` / `removeMultiple()` return values
- create-time tokenizer controls on `Searchlight.create()`:
  `stemming`, `stemmer`, `stopWords`, `useDefaultStopWords`,
  `allowDuplicates`, `tokenizeSkipProperties`, `stemmerSkipProperties`,
  and injected `tokenizer`
- no default stemming at `Searchlight.create()` time
- deterministic rejection of `language` plus injected custom tokenizer
- tokenizer language mismatch validation at tokenize time
- deterministic runtime rejection for unsupported tokenizer languages
- persistence honesty for tokenizer configuration:
  reconstructible built-in tokenizer settings serialize and restore;
  injected tokenizers and custom stemmers fail fast
- persistence now serializes and restores index and sorter component state
  directly instead of rebuilding them through reinsertion; legacy snapshots
  without those component payloads still fall back to reinsertion
- `reindex()` preserves reconstructible tokenizer settings and rejects
  non-reconstructible tokenizer/stemmer cases
- locale-aware string sorting now includes explicit non-English ordering
  support for Norwegian, Danish, Swedish, and German-specific cases
- the public barrel no longer exports Searchlight-only `DocumentAdapter`;
  adapter-style extraction remains an internal concern for future extensions
- create-time extension registration now exists for ordered plugins, named
  plugin metadata, lifecycle hooks, and `index` / `sorter` component
  replacement
- the extension component graph now also supports Orama-style `tokenizer`,
  `validateSchema`, `getDocumentIndexId`, and `getDocumentProperties`
  overrides at `Searchlight.create(...)` time
- plugin-provided index replacement is now proven end-to-end in tests,
  including QPS/PT15 behavior routed through the plugin component path
- `upsert()` / `upsertMultiple()` now exist with Orama-style nested lifecycle
  behavior and the corresponding upsert hook paths
- persisted snapshots now record extension compatibility metadata and restore
  validates plugin order plus component IDs before loading extension-backed
  state

## Intentional divergences

- non-English stemming support is broader than Orama.
  Searchlight uses Snowball stemmers for supported non-English languages,
  while Orama only has a built-in English stemmer and otherwise requires a
  custom stemmer.
- tokenizer configuration uses Dart-native named parameters instead of
  Orama's nested config-object and callback surface. Core behavior is aligned
  for the supported options, but shapes such as `stopWords: false` or
  stop-word callback hooks are intentionally represented differently.
- some BM25 bookkeeping for repeated tokens and `string[]` fields is hardened
  relative to Orama to avoid corrupted stats after deletes.
- locale-aware string collation uses targeted rules for Norwegian, Danish,
  Swedish, and German plus diacritic folding elsewhere; it is not a full
  host-platform `localeCompare` equivalent across every language.
- Dart's typed API replaces several JavaScript runtime validation branches.
  Where the type system already forbids the invalid shape, Searchlight does not
  reproduce the exact Orama error path.
- extension hooks are currently sync-only in Searchlight's core runtime.
  Orama's type/runtime surface supports async hook batches; Searchlight rejects
  async hooks before side effects.
- persisted snapshots are more self-describing than Orama's current helper
  path. Searchlight records extension compatibility metadata and fails fast on
  mismatched restore graphs instead of relying on the caller to recreate the
  right plugin/component setup manually.
- Searchlight intentionally keeps async plugins and async component factories
  unsupported. Orama's types allow them, but the current runtime does not
  await them during `create()`, so Searchlight treats them as non-contractual.

## Remaining gaps before publish-ready parity claims

- Searchlight's extension component surface is still narrower than Orama's:
  no documents store replacement, no pinning replacement, and no surfaced
  `formatElapsedTime` override
- component merge semantics still diverge from Orama:
  Searchlight still lacks the rest of Orama's broader component graph,
  especially documents-store and pinning paths
- `beforeInsertMultiple`, `beforeLoad`, and `afterLoad` are public in the
  Searchlight hook surface but are not currently dispatched because the current
  Orama runtime does not visibly dispatch them either

## Extension detail

See [Searchlight extension status](searchlight-extension-status.md) for the
current implementation matrix and restore contract notes.

## Working references

- [Orama parity plan](../plans/2026-03-27-searchlight-orama-parity-plan.md)
- [Functional audit phase 1](orama-functional-audit-phase1.md)
- [Functional audit phase 2](orama-functional-audit-phase2.md)
