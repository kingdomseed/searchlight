# Orama Extension Implementation Notes

## Purpose

Capture the source-level mechanics that matter most when designing a
Searchlight extension system, especially around algorithm plugins and
persistence.

## Primary references

- Official docs:
  - `https://docs.orama.com/docs/orama-js/search/changing-default-search-algorithm`
  - `https://docs.orama.com/docs/orama-js/plugins/plugin-data-persistence`
- Source:
  - `reference/orama/packages/orama/src/methods/create.ts`
  - `reference/orama/packages/orama/src/methods/serialization.ts`
  - `reference/orama/packages/plugin-qps/src/index.ts`
  - `reference/orama/packages/plugin-pt15/src/index.ts`
  - `reference/orama/packages/plugin-qps/test/index.test.ts`
  - `reference/orama/packages/plugin-pt15/test/index.test.ts`
  - `reference/orama/packages/plugin-data-persistence/src/index.ts`

## How QPS and PT15 plug into Orama

In Orama, BM25 is the default core search path. QPS and PT15 are not simple
flags on the core index. They are plugin-provided component replacements.

### QPS

`pluginQPS()` returns a plugin whose `getComponents(schema)` provides a custom
`index` component.

Source:

- `reference/orama/packages/plugin-qps/src/index.ts`

What that custom index does:

- builds a QPS-specific index datastore in `create`
- intercepts string / `string[]` insert and remove paths
- delegates non-string fields back to the core index implementation
- implements its own `search`
- implements its own `searchByWhereClause`

So QPS is not just a scoring function swap. It replaces the index component and
therefore owns string-field indexing/search behavior for the database.

### PT15

`pluginPT15()` does the same general thing: it provides a custom `index`
component through `getComponents(schema)`.

Source:

- `reference/orama/packages/plugin-pt15/src/index.ts`

What that custom index does:

- builds a PT15-specific index datastore in `create`
- intercepts string / `string[]` insert and remove paths
- delegates non-string fields back to the core index implementation
- implements its own `search`
- implements its own `searchByWhereClause`
- implements custom `save` / `load` for its special string-field storage

Again, this is a component replacement, not a small scoring toggle.

## What QPS and PT15 replace or extend

### Replaced

- the `index` component itself
- string-field indexing behavior
- string-field search behavior
- algorithm-specific persistence behavior inside `index.save` / `index.load`

### Reused from core

- non-string field indexing/removal delegates to core `Index.insert` /
  `Index.remove`
- the rest of the Orama instance shape still comes from core create
- document store, sorter, tokenizer, and pinning remain whatever the instance
  was created with unless separately replaced

## Persistence and installed components

Core serialization source:

- `reference/orama/packages/orama/src/methods/serialization.ts`

Important implementation fact:

- `save(orama)` delegates directly to the currently installed components:
  - `orama.internalDocumentIDStore.save(...)`
  - `orama.index.save(...)`
  - `orama.documentsStore.save(...)`
  - `orama.sorter.save(...)`
  - `orama.pinning.save(...)`
- `load(orama, raw)` delegates directly to the currently installed components:
  - `orama.internalDocumentIDStore.load(...)`
  - `orama.index.load(...)`
  - `orama.documentsStore.load(...)`
  - `orama.sorter.load(...)`
  - `orama.pinning.load(...)`

That means persistence is component-coupled.

It is not a schema-only generic restore path.

`internalDocumentIDStore` is part of the serialized payload itself, not just
hidden runtime glue.

## Whether restore requires matching plugins/components

Yes, effectively.

Source-backed reasoning:

- `plugin-qps/test/index.test.ts` restores data into a new Orama instance that
  is also created with `plugins: [pluginQPS()]`
- `plugin-pt15/test/index.test.ts` restores data into a new Orama instance that
  is also created with `plugins: [pluginPT15()]`
- `serialization.ts` calls the installed `orama.index.load(...)`

So the restore contract is:

- create a new Orama instance with the component/plugin setup you expect
- then call `load(...)` into that instance

If you saved with a plugin-provided `index` but restore into a plain BM25 core
instance, the wrong `index.load(...)` implementation would run.

This is the central persistence invariant behind Orama's plugin architecture.

## Important limitation in `plugin-data-persistence`

There is a second persistence reality beyond the core `save/load` mechanism.

The helper `restore(...)` in
`reference/orama/packages/plugin-data-persistence/src/index.ts` creates a bare
instance like this:

- `create({ schema: { __placeholder: 'string' } })`

Then it calls `load(db, deserialized)`.

That means the convenience restore helper does **not** recreate plugin-backed
component graphs on its own.

This is why the QPS and PT15 tests restore by:

1. creating a new instance with the same plugin installed
2. calling core `load(...)`

rather than relying on the persistence plugin to infer the right plugin set.

## Sharp edges and source-level realities

### 1. Algorithm selection is really component selection

Official docs present QPS/PT15 as alternative search algorithms. Source shows
that the implementation mechanism is stronger: each plugin swaps the `index`
component.

### 2. Persistence is not self-describing enough to recover missing plugins

Core `save(...)` stores component payloads plus `language`, but not a full
portable plugin manifest that can rebuild the right component graph on its own.

The host application is responsible for creating the compatible instance first.

The `plugin-data-persistence` convenience `restore(...)` helper currently
exposes this problem rather than solving it, because it restores into a bare
placeholder instance.

### 3. Plugin-specific save/load logic can differ materially

PT15 has custom `save` / `load` logic in its plugin index implementation.
QPS relies on its plugin-provided index implementation as well.

So Searchlight should not assume all extensions can share one generic passive
serialization shape.

### 4. Query limitations can be plugin-owned behavior

PT15 source enforces its own restrictions:

- no tolerance
- no exact matching
- no string-field where filters

Those are not merely docs-level differences; they live inside the plugin
implementation.

## Documented behavior vs source-level reality

### Docs-level framing

- BM25 is default
- QPS and PT15 are alternative plugins
- plugin-data-persistence persists and restores databases

### Source-level reality that matters for Searchlight

- algorithm plugins replace the index component
- persistence delegates to whatever components are installed
- restore assumes a compatible component/plugin graph already exists
- the convenience persistence plugin restore path does not reconstruct that
  graph for you

## Spec-critical invariants

- Extension registration must happen before the database instance is finalized.
- Algorithm plugins are component replacements, not just scoring callbacks.
- Persistence must either:
  - require compatible extensions/components to be installed at restore time,
    like Orama, or
  - become more self-describing by design as an intentional Searchlight
    divergence.
- If Searchlight wants to improve on Orama here, it should do so consciously:
  the working Orama pattern is manual `create(...) + load(...)` with matching
  plugins, not automatic plugin recreation during restore.
- Plugin-specific query limitations belong to the extension contract and must be
  enforced deterministically.
