# Documentation

This folder contains package-level integration and validation guidance for
`searchlight`, a Dart package for in-memory search and indexing.

Current parity notes are tracked in the divergence ledger. That document is
useful if you need implementation-level comparison details or want to
understand intentional differences.

## Start here

- [App integration guide](app-integration.md)
- [Validation workflow](validation-workflow.md)
- [Divergence ledger](../docs/research/orama-divergence-ledger.md)

## What these docs cover

- how to shape records for Searchlight
- what the core package does and does not parse for you
- when indexes are built and when to persist them
- how to choose among BM25, QPS, and PT15
- how to structure a repository or service layer around Searchlight
- how to validate behavior with fixture data and local corpora
- how to benchmark whole-process memory and snapshot size against real corpora
- where highlighting now lives in the companion package ecosystem
- how the current create-time extension surface fits into the core package

## Out of Scope Today

- source extraction and PDF parsing in the core `searchlight` package
  Companion packages such as `searchlight_parsedoc` can sit above core.
- Flutter UI widgets
- extension features beyond the documented core extension contract
