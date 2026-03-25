# Task Plan: Facets, Groups, and Sorter

## Goal
Implement Facets, Groups, and Sorter matching Orama's `facets.ts`, `groups.ts`, and `sorter.ts` exactly.

## Phases

### Phase 1: Types & Configuration
- Extend FacetConfig with `offset`, `sort`, `ranges` for number facets
- Add FacetResult type (count + values map)
- Ensure GroupBy, SortBy types are complete

### Phase 2: Facets (TDD cycles 1-5)
1. String facet: returns value counts sorted by count descending
2. String facet with limit: only returns top N values
3. Number facet with ranges: counts docs in each range
4. Boolean facet: counts true vs false
5. Facets integrated into search()

### Phase 3: Groups (TDD cycles 6-8)
6. GroupBy: groups results by field value
7. GroupBy with limit: limits docs per group
8. Groups integrated into search()

### Phase 4: Sorting (TDD cycles 9-12)
9. SortBy ascending
10. SortBy descending
11. SortBy overrides score-based sorting
12. Sort integrated into search()

## Files to Create/Modify
- Create: `lib/src/search/facets.dart`
- Create: `lib/src/search/grouping.dart`
- Create: `lib/src/indexing/sort_index.dart`
- Modify: `lib/src/core/types.dart` — extend FacetConfig, add FacetResult types
- Modify: `lib/src/core/database.dart` — wire facets/groups/sortBy into search()
- Modify: `lib/searchlight.dart` — export new files
- Create: `test/search/facets_test.dart`
- Create: `test/search/grouping_test.dart`
- Create: `test/search/sorting_test.dart`
