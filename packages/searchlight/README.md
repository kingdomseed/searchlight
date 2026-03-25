# Searchlight

A full-text search engine for Dart with BM25/QPS/PT15 scoring, filters, facets, geosearch, and highlighting.

Inspired by [Orama](https://github.com/oramasearch/orama).

## Features

- Full-text search with BM25, QPS, and PT15 scoring algorithms
- Schema-based document indexing with 10 field types
- Typo tolerance via Levenshtein fuzzy matching
- Filters (eq, gt, lt, between, in, geoRadius, and/or/not)
- Facets, groups, and field-based sorting
- Text highlighting with positions and trim
- JSON and CBOR persistence with format versioning
- 29-language tokenizer with stemming and stop words
