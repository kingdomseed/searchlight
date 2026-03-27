# Documentation

This folder contains package-level integration and validation guidance for
`searchlight`, a Dart reimplementation of Orama-style in-memory search and
indexing.

Current parity status is tracked in the Orama divergence ledger and the active
parity plan. Those documents are the source of truth for what currently
matches, what intentionally differs, and what still blocks publish-ready
claims.

## Start here

- [App integration guide](app-integration.md)
- [Validation workflow](validation-workflow.md)
- [Orama divergence ledger](../../docs/research/orama-divergence-ledger.md)

## What these docs cover

- how to shape records for Searchlight
- when indexes are built and when to persist them
- how to structure a repository or service layer around Searchlight
- how to validate behavior with fixture data and local corpora

## Package boundaries

- `searchlight`: core indexing, querying, persistence, highlighting
- `searchlight_flutter`: planned Flutter UI helpers and widgets
- `searchlight_pdf`: planned PDF extraction and indexing helpers
