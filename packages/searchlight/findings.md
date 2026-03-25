# Findings

## Orama Analysis

### facets.ts
- Post-search aggregation on result doc IDs
- String facets: count values, sort by count desc (or asc), apply offset/limit (default limit=10)
- Number facets: count docs in user-defined ranges (e.g., `{from: 0, to: 10}`)
- Boolean facets: count `true` vs `false`
- Array fields: count each individual element
- Returns `{count: N, values: {key: count}}` per facet field

### groups.ts
- Post-search grouping by field values
- Supports multiple properties (cross-product combinations)
- Each group has values array + result array of docs
- maxResult limits docs per group
- Uses `DEFAULT_REDUCE` which just collects docs into array
- Only allowed on string, number, boolean types (not arrays)

### sorter.ts
- Index built at insert time
- `create()`: builds sortable properties from schema (string/number/boolean only)
- `insert()`: stores (internalId, value) pairs per sortable property
- `remove()`: marks docs for lazy deletion
- `sortBy()`: sorts results by pre-computed position index
- Supports lazy sorting: sorts on first query, then maintains sorted order
- String sort is locale-aware, number sort is numeric

## Our Simplifications for Searchlight
- GroupBy: support single field (not multi-property cross-product) to match our GroupBy type
- FacetResult: adapt to our existing types but match Orama's data shape
- SortIndex: follow Orama's lazy sort pattern
