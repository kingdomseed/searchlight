# Searchlight vs Orama Divergence Ledger

**Last updated:** 2026-03-27

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

## Intentional divergences

- non-English stemming support is broader than Orama.
  Searchlight uses Snowball stemmers for supported non-English languages,
  while Orama only has a built-in English stemmer and otherwise requires a
  custom stemmer.
- some BM25 bookkeeping for repeated tokens and `string[]` fields is hardened
  relative to Orama to avoid corrupted stats after deletes.
- Dart's typed API replaces several JavaScript runtime validation branches.
  Where the type system already forbids the invalid shape, Searchlight does not
  reproduce the exact Orama error path.

## Remaining gaps before publish-ready parity claims

- no Orama-style create-time extension surface yet:
  components, hooks, and plugin registration are still missing
- locale-aware string sort parity is not complete for every supported language;
  current support is targeted rather than a full `localeCompare` equivalent
- `DocumentAdapter` still needs either stronger stabilization or demotion from
  the public surface
- tokenizer/config parity is not complete for every Orama configuration shape;
  Searchlight exposes a Dart-native surface rather than a direct config-object
  clone

## Working references

- [Orama parity plan](../plans/2026-03-27-searchlight-orama-parity-plan.md)
- [Functional audit phase 1](orama-functional-audit-phase1.md)
- [Functional audit phase 2](orama-functional-audit-phase2.md)
