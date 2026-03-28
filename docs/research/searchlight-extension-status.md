# Searchlight Extension Status

**Last updated:** 2026-03-28

This document tracks what the current Searchlight extension system implements,
where it intentionally differs from Orama, and which hook/component paths are
still incomplete.

## Implemented today

### Registration model

- `Searchlight.create()` and `Searchlight.fromJson()` accept:
  - `plugins: List<SearchlightPlugin<Object?>>`
  - `components: SearchlightComponents?`
- plugin registration order is preserved
- duplicate plugin names are rejected deterministically
- `SearchlightPlugin.name` is required
- `SearchlightPlugin.extra` is available as a plugin-owned data bag

### Hook surface

`SearchlightHooks` currently exposes these callback shapes:

- `afterCreate`: `(db) -> FutureOr<void>`
- single-record hooks:
  `(db, id, doc) -> FutureOr<void>`
- multiple-doc hooks:
  `(db, docs) -> FutureOr<void>`
- multiple-id hooks:
  `(db, ids) -> FutureOr<void>`
- `beforeSearch`: `(db, params, language) -> FutureOr<void>`
- `afterSearch`: `(db, params, language, results) -> FutureOr<void>`
- load hooks: `(db, raw) -> FutureOr<void>`

### Runtime behavior that is working

- `afterCreate` dispatch
- `beforeInsertMultiple` / `afterInsertMultiple` dispatch
- single-record insert/remove/update lifecycle dispatch
- `beforeRemoveMultiple` / `afterRemoveMultiple` dispatch
- `beforeUpdateMultiple` / `afterUpdateMultiple` dispatch
- `beforeSearch` / `afterSearch` dispatch
- deterministic hook ordering based on plugin registration order
- sync preflight before side effects for supported lifecycle paths

### Component surface

`SearchlightComponents` currently allows replacement of:

- `index`
- `sorter`
- final resolved `hooks`

The active `index` and `sorter` descriptors carry stable IDs. Those IDs are
serialized into snapshots and checked during restore.

### Proven component replacement

The extension test suite now proves that:

- a plugin-provided index component can replace the database index
- that replacement can force QPS/PT15 behavior independently of the top-level
  `algorithm` argument
- conflicting `index` / `sorter` registrations are rejected instead of falling
  back to last-writer-wins behavior

## Intentional differences from Orama right now

### Sync-only hooks

Searchlight's core operations are synchronous, so async hooks are rejected
before mutation or search work begins. Orama's type/runtime path supports async
hook batches.

### Restore compatibility is stricter than Orama

Searchlight snapshots include:

- `extensionCompatibility.plugins`
- `extensionCompatibility.components.index`
- `extensionCompatibility.components.sorter`

Restore validates those values against the supplied plugin/component graph
before loading serialized state. Legacy snapshots without this metadata are
still accepted.

This is stricter and more self-describing than Orama's current persistence
helper behavior.

## Important gaps and non-parity areas

### Component graph is still narrower than Orama

Searchlight does not yet expose replacements for Orama-style component slots
such as:

- tokenizer
- documents store
- pinning
- function components like schema validation or document property extraction

### Component merge semantics still differ

Current Searchlight behavior:

- `index` and `sorter` now reject duplicate claims across user components and
  plugins
- `hooks` still use Searchlight-specific final-resolution behavior rather than
  Orama's component graph rules

Orama's runtime applies conflict errors across its wider component graph, not
just these two slots.

### Public hook names that are not fully wired

These hooks are publicly declared but not currently dispatched by Searchlight's
database runtime:

- `beforeLoad`
- `afterLoad`
- `beforeUpsert`
- `afterUpsert`

The last two are inert because Searchlight does not yet expose `upsert()`.

### Missing Orama hook names

Searchlight does not yet expose:

- `beforeUpsertMultiple`
- `afterUpsertMultiple`

### Async plugin/component initialization

Searchlight does not support:

- async plugins
- async component factories
- async hook execution inside synchronous database operations

## Restore contract

If you persist a database that used plugins or replacement components:

1. restore with the same plugin order
2. restore with component descriptors carrying the same IDs
3. expect restore to fail fast if the graph is incompatible

This is the supported way to avoid loading extension-backed index data into the
wrong runtime shape.

## Practical guidance

The current extension system is ready for:

- lifecycle tracing plugins
- algorithm-style index replacement plugins
- controlled sorter replacement
- restore-time compatibility checks for extension-backed snapshots

It is not yet ready to claim full Orama extension parity.
