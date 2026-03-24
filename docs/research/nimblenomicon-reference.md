# Nimblenomicon Orama Implementation Reference

How Orama is used in the Nimblenomicon project — serves as the primary use-case reference for Searchlight.

## Architecture

### Build-Time Indexing
- `scripts/postbuild.mjs` generates the search index after `next build`
- Build command: `"build": "node scripts/postbuild.mjs && next build"`

### Schema
```javascript
{
  url: "string",
  title: "string",
  content: "string",
  type: "enum",    // legendary, monster, spell, ancestry, etc.
  group: "enum"    // spell school, monster family
}
```

### Document Sources
- ~385 markdown files from `src/content/` (content capped at 3000 chars)
- Glossary terms from `tooltip-library.yaml`
- Batch insert: `insertMultiple(db, records, 500)`

### Content-Hashing Strategy
1. MD5 hash of serialized index (8 chars) → `search-index.{hash}.json`
2. Old hashes cleaned up automatically
3. Manifest pattern: `search-manifest.json` → `search-index.{hash}.json`

### Runtime Index Loading
1. Fetch `search-manifest.json` to discover current hash
2. Fetch content-hashed index file
3. Restore: `await restore("json", data)`
4. Cached for subsequent searches

## Search Configuration
```javascript
oramaSearch(db, {
  term: query,
  tolerance: 1,
  limit: 8,
  properties: ["title", "content"]
})
```

## Highlight Usage
```javascript
const highlighter = new Highlight();
const result = highlighter.highlight(content, query);
// result.positions → match indexes
// result.trim(trimLen, true) → excerpt with <mark> tags
```

### Styling
```css
[&_mark]:bg-amber-200 [&_mark]:text-gray-900
```

## Search UI/UX
- Modal overlay (z-50, backdrop blur) via custom event
- Input with magnifying glass icon + "esc" hint
- Max 8 results with title + excerpt (line-clamped to 2 lines)
- Hover states with amber background
- Keyboard: Escape closes, "/" opens
- Two trigger variants: "hero" (homepage) and "compact"
- Loading states, empty state messaging

## Key Takeaways for Searchlight
1. Build-time indexing with persistence works well for static content
2. For user-generated content (Flutter), need runtime indexing + incremental updates
3. Highlight with trim() is essential for search result excerpts
4. Content capping (3000 chars) may be needed for mobile memory constraints
5. Batch insert with configurable batch size is important for large imports
6. The manifest/hash pattern is elegant for cache invalidation
