# Orama Plugin Package Map

## Purpose

Map the Orama open-source packages that matter for Searchlight's roadmap, and
separate them from Orama Cloud ingestion capabilities.

## Primary references

- Official docs:
  - `https://docs.orama.com/docs/orama-js/plugins`
  - `https://docs.orama.com/docs/orama-js/plugins/plugin-parsedoc`
  - `https://docs.orama.com/docs/orama-js/plugins/plugin-data-persistence`
  - `https://docs.orama.com/docs/orama-js/search/changing-default-search-algorithm`
- Monorepo source:
  - `reference/orama/packages/`

## Core package vs plugin packages

Open-source Orama keeps core search in `@orama/orama`, then adds capabilities
through separate packages under the monorepo.

## Open-source packages relevant to Searchlight

### Core

- `@orama/orama`
  - core search engine
  - plugin system
  - default BM25 search path

### Parsing / ingestion

- `@orama/plugin-parsedoc`
  - parses and populates indexes from HTML and Markdown
  - source confirms only two file types in the plugin API:
    - `html`
    - `md`
  - key source:
    `reference/orama/packages/plugin-parsedoc/src/index.ts`

### Persistence

- `@orama/plugin-data-persistence`
  - persistence and restore helpers above Orama's core `save` / `load`
  - supports multiple serialization formats in plugin code:
    - `json`
    - `dpack`
    - `binary`
    - `seqproto`
  - key source:
    `reference/orama/packages/plugin-data-persistence/src/index.ts`
  - important limitation:
    its convenience `restore(...)` helper creates a bare placeholder Orama
    instance and then calls core `load(...)`, so it does not automatically
    recreate plugin-backed component graphs

### Alternative ranking algorithms

- `@orama/plugin-qps`
  - swaps the index component for QPS behavior
  - key source:
    `reference/orama/packages/plugin-qps/src/index.ts`

- `@orama/plugin-pt15`
  - swaps the index component for PT15 behavior
  - key source:
    `reference/orama/packages/plugin-pt15/src/index.ts`

### Highlighting

- `@orama/highlight`
  - standalone highlight package according to Orama docs and package map docs

- `@orama/plugin-match-highlight`
  - older package
  - repo/docs history indicate it is deprecated in favor of `@orama/highlight`

### Other official plugin packages visible in the monorepo/docs

- `@orama/plugin-analytics`
- `@orama/plugin-embeddings`
- `@orama/plugin-secure-proxy`
- `@orama/plugin-docusaurus-v3`
- `@orama/switch`
- `@orama/stemmers`
- `@orama/stopwords`
- `@orama/tokenizers`

These are real plugin packages, but they are lower priority for Searchlight's
current roadmap than extension architecture, parsedoc, highlight, and
PDF-adjacent ingestion.

The last four are especially useful as architecture signals:

- `@orama/switch` shows Orama also builds client-abstraction packages around the
  search ecosystem
- `@orama/stemmers`, `@orama/stopwords`, and `@orama/tokenizers` show that
  text-analysis building blocks are factored into reusable satellite packages,
  not all kept inside core

## Where HTML and Markdown support live

Open-source HTML and Markdown parsing do not live in core.

They live in `@orama/plugin-parsedoc`.

Source-confirmed details from `plugin-parsedoc/src/index.ts`:

- `populateFromGlob(...)` reads files and infers a `FileType`
- the supported `FileType` union is:
  - `'html'`
  - `'md'`
- markdown goes through a remark/rehype pipeline
- HTML goes through rehype

This is the architecture Searchlight should mirror: parsing is a companion
package concern, not a core-engine concern.

## Whether there is an open-source PDF plugin

I found no open-source Orama PDF plugin/package in:

- official plugin docs pages surfaced for Orama JS
- the checked-in Orama monorepo under `reference/orama/packages/`

So the current evidence says:

- no open-source Orama PDF parser/plugin package is present in the public
  monorepo snapshot we have
- PDF should not be treated as an existing open-source Orama parity target in
  the same way as parsedoc or highlight

## Open-source plugin support vs Orama Cloud ingestion

This distinction matters.

### Open-source Orama JS

Source/doc-confirmed OSS ingestion/plugin support relevant here:

- HTML via `plugin-parsedoc`
- Markdown via `plugin-parsedoc`
- persistence via `plugin-data-persistence`
- QPS via `plugin-qps`
- PT15 via `plugin-pt15`

### Orama Cloud

Orama Cloud has a broader ingestion story than the open-source plugin set.

Based on the current official docs/search results we used during this session,
Cloud-oriented ingestion references include formats such as:

- JSON
- JSONL
- CSV
- XML
- PDF

Searchlight should not blur this distinction. Cloud ingestion breadth is not
evidence that the OSS Orama JS plugin ecosystem already exposes equivalent
packages.

## Packages most relevant to Searchlight

### 1. Extension system

Why first:

- every Orama add-on here depends on the plugin/component model
- Searchlight currently lacks that create-time surface

Relevant Orama baseline:

- `@orama/orama` plugin system
- create-time component replacement
- lifecycle hooks

### 2. Parsedoc-style package

Why second:

- this is the clearest OSS example of file parsing living outside core
- it provides the best architecture template for Searchlight companion parsing

Relevant Orama package:

- `@orama/plugin-parsedoc`

### 3. Standalone highlighter package

Why third:

- Orama treats highlighting as a separate reusable package
- Searchlight already has a core highlighter, but packaging and UX may still
  deserve a companion package or richer Flutter-facing layer later

Relevant Orama packages:

- `@orama/highlight`
- historical/deprecated `@orama/plugin-match-highlight`

### 4. PDF-related work

Why fourth:

- there is no clear OSS Orama PDF plugin parity target to copy directly
- this likely becomes a Searchlight-specific companion package design rather
  than a one-to-one Orama clone

## Direct implications for Searchlight planning

- Do not describe HTML or Markdown parsing as core-package support.
- Treat parsedoc as the first companion-package model after the extension
  surface exists.
- Treat PDF as a separate design problem, not as an already solved Orama OSS
  plugin parity item.
- Treat text-analysis helpers as possible future satellite-package candidates,
  not necessarily core-only internals.
