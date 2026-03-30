# Searchlight Parsedoc Package Spec

## Purpose

Define the first companion package that sits beside `searchlight` core:
`searchlight_parsedoc`.

This package should be a Dart-based reimplementation of the open-source Orama
`plugin-parsedoc` package boundary, adapted to Searchlight's structured-record
API instead of Orama's direct `insertMultiple(...)` flow.

## Why This Is A Separate Package

`searchlight` core indexes structured records. It does not own raw file
ingestion.

That matches the Orama architecture we inspected:

- core search stays in the engine package
- HTML/Markdown parsing lives in a companion package
- the application or companion package decides how source files become records

Searchlight should keep that separation.

## Orama Parity Target

The parity target is the public open-source `@orama/plugin-parsedoc` package as
checked into `reference/orama/packages/plugin-parsedoc/`.

Source-confirmed behaviors worth matching:

- supported source types are only `html` and `md`
- Markdown is converted through a Markdown-to-HTML pipeline before extraction
- HTML and converted Markdown are walked structurally
- text-bearing elements become extracted records with:
  - tag/type
  - text content
  - structural path
  - element properties/attributes
- consecutive sibling text nodes with the same tag can be:
  - merged
  - split
  - both merged and split
- a transform callback can rewrite node tag/content/raw markup before records
  are emitted

Searchlight should match this package boundary and these rules where they are
clear from source.

## Searchlight Adaptation

Orama's package inserts directly into an Orama database. Searchlight should not
copy that coupling exactly because `searchlight` intentionally keeps extraction
outside core.

So `searchlight_parsedoc` should split the workflow into two layers:

1. Parse raw HTML/Markdown into a normalized parsed document model.
2. Provide mapping helpers that turn that parsed model into Searchlight-ready
   record maps.

This preserves the same architectural boundary while fitting Searchlight's
structured-record API.

`searchlight_parsedoc` should therefore be described as a parser-plus-mapper
package, not as a package that automatically creates or populates Searchlight
databases. Apps still own:

- loading files or remote content
- deciding when indexing happens
- calling `insert()` or `insertMultiple()` on their Searchlight instance
- deciding whether they index per document or per extracted block

## Supported Inputs In V1

V1 should support:

- raw Markdown strings
- raw HTML strings
- Markdown file paths
- HTML file paths

V1 should not require Flutter.

The package should remain pure Dart. String parsing APIs should work anywhere
the parser dependencies support Dart. File-path helpers should be clearly
documented as VM-only because they depend on `dart:io`.

## Unsupported Inputs In V1

V1 should not support:

- PDF
- DOCX
- plain-text autodetection
- front matter parsing
- CSV, XML, or JSON ingestion
- directory walking or globbing as a public API requirement
- OCR
- viewport geometry
- page rendering
- Flutter widget integration

If directory or glob helpers are added later, they should be layered above the
same single-file parse APIs instead of redefining the core model.

## Public Model

Orama's actual parsedoc output is flat and record-oriented. It does not expose a
first-class semantic document model.

Searchlight may add a small normalized wrapper for developer ergonomics, but the
core extraction contract should still be thought of as:

- ordered extracted blocks
- each block preserving tag, text, path, and attributes

The package should expose a normalized document model that wraps that flat block
list without pretending to understand full document semantics.

### `ParsedDocument`

Required fields:

- `format`: Markdown or HTML
- `sourcePath`: nullable original file path
- `title`: nullable convenience field derived from the extracted blocks and
  source document
- `blocks`: ordered extracted text blocks

Required derived getters:

- `plainText`: all block text joined in document order
- `bodyText`: body-oriented text joined in document order, excluding a promoted
  title block when applicable

### `ParsedBlock`

Required fields:

- `tag`: normalized structural tag, such as `title`, `h1`, `p`, `li`
- `text`: extracted text content
- `path`: stable structural path within the parsed tree
- `attributes`: normalized string-keyed attribute map

This preserves the parts of Orama's parsedoc output that matter for indexing:
tag, content, path, and element properties.

The package should not promise more than this in v1. In particular, it should
not imply:

- a heading tree
- section nesting
- front matter objects
- author/date metadata
- source offsets
- viewport coordinates

## Title Extraction Rules

Because Orama does not expose a dedicated title field, Searchlight's `title`
should be documented as a convenience adaptation layered above the extracted
blocks.

V1 should keep title extraction simple:

- HTML: prefer the `<title>` element if present
- Markdown: prefer the first extracted `h1` block if present
- if no title is found, leave `title` null

This should not become a speculative metadata system. YAML front matter,
OpenGraph metadata, or custom field extraction belong in later work if needed.

## Parse Configuration

V1 should expose the same high-level merge behavior Orama has.

### `MergeStrategy`

Required options:

- `merge`
- `split`
- `both`

Default:

- `merge`

Behavior:

- `merge`: merge consecutive sibling text blocks that share the same tag and
  structural container
- `split`: keep each emitted block separate
- `both`: emit both the separated blocks and the merged aggregate block

### Transform Callback

V1 should expose a transform callback equivalent in intent to Orama's
`transformFn`.

The callback should receive a normalized node view before block extraction,
including:

- tag
- text content
- raw markup
- attributes

The callback may return a rewritten node view. Raw-markup rewrites should take
precedence over tag/text rewrites, matching the Orama source behavior.

V1 does not need a broader plugin system inside parsedoc itself. One transform
callback is enough.

## Searchlight Mapping Helpers

V1 should ship direct helpers for converting parsed documents into Searchlight
record maps.

Required helper shapes:

- document-level mapping:
  - one Searchlight record per parsed document
  - intended for the most common app flow
- block-level mapping:
  - one Searchlight record per parsed block
  - intended for closer parity with Orama's structural indexing behavior

Document-level output should make it easy to index:

- title
- body content
- source path
- format

Block-level output should make it easy to index:

- tag
- block text
- structural path
- source path
- extracted attributes

The package should not assume a fixed Searchlight schema, but the helper APIs
should make schema wiring straightforward.

Ownership rule:

- parsing returns Searchlight-agnostic parsed models first
- mapping helpers then return generic `Map<String, Object?>` records
- callers remain responsible for choosing the final schema and for inserting the
  records into Searchlight

## File Loading Contract

V1 file helpers should stay narrow:

- read a single file from a path
- infer format from the file extension only when the extension is clearly
  supported
- otherwise require the caller to choose the parser explicitly

Accepted extensions in V1:

- `.md`
- `.markdown`
- `.html`
- `.htm`

This is intentionally simpler than a broad ingestion system.

## Error Handling

V1 should use predictable, typed package errors for:

- unsupported file type
- missing file
- invalid HTML/Markdown parse input when the underlying parser fails
- invalid transform output
- empty documents when the caller requests a non-empty parsed result contract

Errors should name the file path when a file-based API is used.

Empty-input behavior must be documented explicitly. Either:

- return a valid `ParsedDocument` with zero blocks and null `title`, or
- throw a typed empty-document error

Whichever contract is chosen, tests and README examples must match it.

## Platform Story

`searchlight_parsedoc` should remain a pure Dart package.

That means:

- no platform channels
- no Flutter plugin scaffolding
- no mobile/desktop/web-specific native code

Platform implications should be documented clearly:

- string-based parse APIs are the portable baseline
- file-path APIs work where `dart:io` is available
- web callers should load bytes/text through app code first, then call the
  string-based parse APIs

## Relationship To Future Packages

### `searchlight_highlight`

Parsedoc should not own snippet generation or inline highlighting. It only
extracts and normalizes searchable content.

### `searchlight_pdf`

Parsedoc should not become a PDF abstraction layer. PDF extraction is a
separate package because it has a different dependency profile, different parse
risks, and no open-source Orama package parity target in the reference tree.

If `searchlight_pdf` later extracts text blocks, it should map into a similar
normalized Searchlight-facing shape where that helps interoperability, but V1
parsedoc should not wait on that design.

## Acceptance Criteria

The package spec is satisfied when V1 can prove all of the following:

- Markdown strings parse into ordered structural blocks
- HTML strings parse into ordered structural blocks
- file-based Markdown and HTML parsing works from live local files
- merge, split, and both strategies behave predictably
- transform callbacks can rewrite tag/text/raw content
- title extraction is deterministic and documented
- document-level record mapping works for common Searchlight schemas
- block-level record mapping preserves structural search data
- the README clearly states that PDF and richer ingestion are out of scope

## Explicit Non-Goals For V1

Do not add any of the following during initial implementation:

- PDF parsing
- automatic recursive folder indexing
- glob APIs
- front matter parsing
- remote download helpers
- snapshot persistence
- Searchlight database creation helpers
- UI or widget wrappers
- highlighting/snippet rendering

Those may be valid later, but they are not needed to match the Orama parsedoc
boundary and they would blur package responsibilities.
