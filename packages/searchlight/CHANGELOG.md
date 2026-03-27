# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

- Tightened persisted-index restore and locale-aware sorting behavior to better
  match Orama core semantics.
- Removed the internal `DocumentAdapter` abstraction from the public API
  surface.
- Polished package docs for publish readiness, including clearer pure Dart
  positioning and app-integration guidance.

## [0.1.0]

- Initial public release of the Searchlight core package.
- Added schema-based full-text indexing, filtering, sorting, grouping, and
  facets.
- Added JSON and CBOR persistence APIs plus file-backed storage helpers.
- Added standalone text highlighting helpers and a validation example app.
