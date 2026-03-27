# Documentation

This folder contains package-level integration and validation guidance for
`searchlight`, a Dart reimplementation of Orama-style in-memory search and
indexing.

Current Orama parity notes are tracked in the divergence ledger. That document
is useful if you need implementation-level comparison details or want to
understand intentional differences from Orama.

## Start here

- [App integration guide](app-integration.md)
- [Validation workflow](validation-workflow.md)
- [Orama divergence ledger](../../docs/research/orama-divergence-ledger.md)

## What these docs cover

- how to shape records for Searchlight
- when indexes are built and when to persist them
- how to structure a repository or service layer around Searchlight
- how to validate behavior with fixture data and local corpora

## Out of Scope Today

- source extraction and PDF parsing
- Flutter UI widgets
- Orama-style extension registration (`components`, hooks, plugins)
