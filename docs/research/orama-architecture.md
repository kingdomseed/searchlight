# Orama Architecture Reference

Source: [github.com/oramasearch/orama](https://github.com/oramasearch/orama) (Apache 2.0)

## Overview

Orama is a TypeScript full-text search engine (~2KB gzipped) that runs in browser, server, and edge environments. It uses **no database** — the entire index lives in memory using tree-based data structures, with optional serialization for persistence.

## Core API

```
create(config)         → Initialize database with schema
insert(db, doc)        → Add single document
insertMultiple(db, docs, batchSize) → Batch insert
update(db, id, doc)    → Update existing document
remove(db, id)         → Delete document
search(db, query)      → Execute search
```

## Schema Types (10 total)

| Type | Description |
|------|-------------|
| `string` | Full-text indexed, searchable |
| `number` | Numeric filtering and sorting |
| `boolean` | Boolean filtering |
| `enum` | Faceted filtering (categorical) |
| `geopoint` | Latitude/longitude pair for geosearch |
| `string[]` | Array of searchable strings |
| `number[]` | Array of numbers |
| `boolean[]` | Array of booleans |
| `enum[]` | Array of enums |
| Nested objects | e.g., `meta.rating: "number"` |

## Search Algorithms

### BM25 (Default)
- Term frequency + inverse document frequency + document length normalization
- Industry standard (Elasticsearch, Lucene)
- Best for general-purpose search across varied document lengths

### QPS (Quantum Proximity Scoring)
- Developed by Orama team (2024)
- Scores based on proximity of search terms within documents
- Smaller index size than BM25 (no TF/IDF metadata stored)
- Best for documentation, e-commerce, content search

### PT15 (Positional Token 15)
- Tokens in earlier positions score higher
- 15 fixed position buckets
- Best for structured text where position matters (titles, headings)
- Inspired by Flexsearch

Algorithm is chosen at database creation time — each stores different metadata in the index.

## Internal Architecture

### Components (Customizable)
- **Tokenizer** — tokenize(content, language, property) → List<token>
- **Index** — inverted index using tree-based structures
- **DocumentsStore** — document storage and retrieval
- **Sorter** — result sorting operations

### Data Structures
- Tree-based indexes (radix trees for prefix matching)
- Inverted index (HashMap-backed) for term → document mapping
- Each schema property creates its own index structure

### Search Features
- Full-text search with typo tolerance
- Field-level boosting
- Faceted navigation/aggregations
- Geo-spatial filtering (radius-based)
- Custom filters with boolean logic
- Result pinning/merchandising
- Multi-field sorting
- Offset/limit pagination
- Grouping by field

### Tokenization
- Stemming and tokenization in 30 languages
- Plugin-based text analysis pipeline

### Persistence
- `@orama/plugin-data-persistence`
- `persist(db, "json")` → serialized JSON
- `restore("json", data)` → restored database instance
- Content-hashing pattern for cache invalidation

## Package Ecosystem

| Package | Purpose |
|---------|---------|
| `@orama/orama` | Core search engine |
| `@orama/highlight` | Standalone text highlighting |
| `@orama/plugin-data-persistence` | Index serialization |
| `@orama/plugin-match-highlight` | Deprecated, replaced by @orama/highlight |
| `@orama/plugin-qps` | QPS scoring algorithm |
| `@orama/plugin-pt15` | PT15 scoring algorithm |
| `@orama/plugin-embeddings` | Vector generation (TensorFlow.js) |
| `@orama/plugin-secure-proxy` | Client-side OpenAI integration |
| `@orama/plugin-analytics` | Query instrumentation |

## Highlight Library

Separate package: [@orama/highlight](https://github.com/oramasearch/highlight)

### Constructor Options
| Option | Type | Default | Purpose |
|--------|------|---------|---------|
| `caseSensitive` | boolean | `false` | Case-sensitive matching |
| `wholeWords` | boolean | `false` | Only highlight entire words |
| `HTMLTag` | string | `"mark"` | Wrapper element for highlights |
| `CSSClass` | string | `"orama-highlight"` | CSS class on wrapper |

### API
```
highlight(inputString, searchTerm) → {
  positions: [{start, end}, ...],  // match locations
  HTML: string,                     // text with <mark> tags
  trim(characters): string          // truncated excerpt around matches
}
```
