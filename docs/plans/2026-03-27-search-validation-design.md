# Search Validation Design

**Date:** 2026-03-27

## Goal

Add a realistic, repeatable way to validate that Searchlight can extract content into records, build an index, persist or reload that index, and return sensible search results against a non-trivial corpus.

## Current Package State

The repository currently contains only the core package:

- `packages/searchlight`

The longer-term package split remains:

- `searchlight` for the pure Dart core
- `searchlight_flutter` for Flutter rendering helpers and widgets
- `searchlight_pdf` for PDF extraction adapters

Those future packages should remain planned work, not a blocker for validating the current core implementation.

## Design Summary

Searchlight should follow the same high-level pipeline used by Orama integrations:

1. Extract source material into plain records.
2. Build a search index from those records.
3. Save a corpus or serialized index as a local asset.
4. Load that asset in tests or a lightweight app.
5. Run representative searches and inspect ranking, filtering, and highlighting.

This mirrors Orama's architecture more closely than writing only synthetic unit tests. Orama core builds indexes from records, while content extraction is handled by the host app or a plugin. Searchlight should do the same.

## Orama-Parity Pipeline

### What Orama core does

- Accepts a schema and creates tokenizer/index/store state.
- Inserts validated documents into the configured indexes.
- Persists and restores index snapshots.

### What Orama-based apps and plugins do

- Read source files or content trees.
- Transform them into a stable document schema.
- Batch-insert the resulting records.
- Persist the built index for runtime loading.

Searchlight should match that split. The core package should not own source-specific extraction logic for arbitrary content. Instead, repo tooling should transform content into a stable record set that Searchlight indexes.

## Corpus Strategy

### Public corpus

Commit a generalized, non-copyright corpus to the repository for automated validation:

- path: `packages/searchlight/test/fixtures/`
- format: JSON
- fields: `url`, `title`, `content`, `type`, `group`

This corpus should be small enough to keep tests fast, but diverse enough to exercise:

- title hits
- body hits
- close or ambiguous matches
- multiple content types
- grouping/filtering fields
- highlightable excerpts

### Private local corpus

Support a local, gitignored corpus or serialized index inside this repository for personal validation against real-world data:

- path: `packages/searchlight/.local/`

The important boundary is that real content is copied into local assets inside this repo before testing. The validation workflow should not depend on reading a sibling repository at runtime.

## Validation Layers

### 1. Dataset-backed integration tests

Add deterministic integration tests that load the public corpus and assert:

- expected top hit for representative queries
- stable filtering behavior
- basic ranking sanity
- highlight position or excerpt sanity
- persistence/load behavior where relevant

These tests are the primary regression gate.

### 2. Corpus or index generation tooling

Add a local tool that:

- reads source content
- maps it into the shared record schema
- writes either:
  - a corpus JSON file, or
  - a serialized Searchlight snapshot

This tool should follow the Orama-style flow used in Nimblenomicon:

- collect records
- derive metadata from path structure
- cap content where appropriate
- create database
- batch insert
- save output for later runtime loading

### 3. Flutter web example

Add a minimal Flutter web example under:

- `packages/searchlight/example`

This app is validation infrastructure, not the first version of `searchlight_flutter`.

Its job is to:

- load the public corpus by default
- optionally load a local generated corpus or snapshot when present
- build or restore a Searchlight index
- let a human run searches and inspect results

The UI should stay thin:

- query input
- result list
- excerpt rendering
- basic highlighting
- optional algorithm selector if it adds diagnostic value

## Shared Data Contract

Tests and the example app should consume the same record schema so that:

- automated verification and manual inspection stay aligned
- corpus changes are cheap to propagate
- switching between public and private corpora does not require separate search code paths

If a serialized index format is added to the workflow, keep the raw corpus format as the source of truth for fixture readability and regeneration.

## Documentation Requirements

Document the following clearly:

- why the repo fixture is generalized and public-safe
- where local private validation artifacts belong
- how the generation pipeline maps source content into search records
- how this matches Orama's extraction-plus-indexing model
- that `searchlight_flutter` and `searchlight_pdf` remain future packages

## Non-Goals

This design does not:

- scaffold `searchlight_flutter`
- implement PDF extraction now
- promise wire compatibility with Orama persistence formats
- turn the example app into a polished product UI

## Recommended Next Steps

1. Add the public corpus fixture and expectations fixture.
2. Write failing integration tests against that fixture.
3. Add local generation tooling for private corpora or snapshots.
4. Add the minimal Flutter web example that uses the same fixture contract.
5. Document how later `searchlight_flutter` and `searchlight_pdf` work will plug into this pipeline.
