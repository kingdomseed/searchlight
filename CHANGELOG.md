# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.2.3] - 2026-04-04

### Added

- Added a repository benchmark helper, `tool/memory_benchmark.dart`, for
  measuring whole-process RSS, serialize/restore peak memory, and JSON/CBOR
  snapshot sizes against an explicit corpus path.

### Changed

- Documented the benchmark helper and its caveats in the repository docs,
  including explicit corpus-path input, supported text extensions, and the
  distinction between whole-process RSS and isolated index memory.

## [0.2.2] - 2026-03-30

### Changed

- Removed a final round of extraneous README wording for the package-family
  documentation refresh.

## [0.2.1] - 2026-03-30

### Changed

- Simplified the README package-role guidance and removed extraneous companion
  package wording.

## [0.2.0] - 2026-03-30

### Changed

- Moved highlighting and excerpt generation guidance to the companion package
  `searchlight_highlight`.
- Expanded companion-package documentation for highlight and parsedoc package
  discovery.

### Removed

- Built-in highlighting helpers from the core `searchlight` package API.

## [0.1.0] - 2026-03-30

### Added

- Initial public release of the Searchlight core package.
- Schema-based full-text indexing, filtering, sorting, grouping, and facets.
- JSON and CBOR persistence APIs plus file-backed storage helpers.
- `SearchlightPlugin` extension hooks and component replacement support.
- Standalone text highlighting helpers and a Flutter validation example app.

### Changed

- Tightened persisted-index restore and locale-aware sorting behavior to better
  match Orama core semantics.
- Removed the internal `DocumentAdapter` abstraction from the public API
  surface.
- Polished package docs for publish readiness, including clearer pure Dart
  positioning and app-integration guidance.
