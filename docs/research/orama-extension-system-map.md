# Orama Extension System Map

## Purpose

Map the Orama open-source extension surface as it actually exists in official
docs and source, so Searchlight can design a Dart-native equivalent without
guessing.

## Primary references

- Official docs:
  - `https://docs.orama.com/docs/orama-js/plugins`
  - `https://docs.orama.com/docs/orama-js/plugins/writing-your-own-plugins`
- Source:
  - `reference/orama/packages/orama/src/methods/create.ts`
  - `reference/orama/packages/orama/src/components/plugins.ts`
  - `reference/orama/packages/orama/src/components/hooks.ts`
  - `reference/orama/packages/orama/src/types.ts`

## High-level model

Orama keeps the core engine small and exposes extension behavior through:

- create-time component injection
- create-time plugin registration
- lifecycle hooks attached by plugins

The extension system is not an afterthought. `create(...)` is where plugins are
merged, conflicts are checked, default components are resolved, and hook lists
are assembled.

## Exact create-time extension surface

Source-defined `create(...)` arguments in
`reference/orama/packages/orama/src/methods/create.ts`:

- `schema`
- `sort?`
- `language?`
- `components?`
- `plugins?`
- `id?`

### `components`

`components` is a mix of object components and function components.

Object components from `components/hooks.ts`:

- `tokenizer`
- `index`
- `documentsStore`
- `sorter`
- `pinning`

Function components from `components/hooks.ts`:

- `validateSchema`
- `getDocumentIndexId`
- `getDocumentProperties`
- `formatElapsedTime`

Behavior in `create.ts`:

- if a function component is missing, Orama fills in the default implementation
- if a provided function component is not a function, create throws
  `COMPONENT_MUST_BE_FUNCTION`
- if an unknown component key is present, create throws
  `UNSUPPORTED_COMPONENT`

### `plugins`

`plugins` is an array passed to `create(...)`.

Each plugin can expose:

- lifecycle hooks such as `beforeInsert`, `afterSearch`, `afterCreate`
- `getComponents(schema)` returning a partial component map

The plugin shape is defined in `types.ts` as `OramaPluginSync` /
`OramaPlugin`.

Plugin type facts that matter:

- `name: string` is required on `OramaPluginSync`
- `extra?: T` is an optional plugin-owned data bag
- the type surface also allows `OramaPluginAsync = Promise<OramaPluginSync>`
  and `getComponents(...)` returning `SyncOrAsyncValue`
- however, `create(...)` currently processes plugins synchronously and does not
  `await` `getComponents(...)`

That makes async plugin typing a source-level tension: the type surface is
broader than the current runtime path.

### Direct hooks via `components`

There is an important type/runtime mismatch here.

Type-level:

- `Components<...>` includes `SingleOrArrayCallbackComponents<T>` in
  `types.ts`

Runtime-level:

- `validateComponents(...)` only accepts keys from `OBJECT_COMPONENTS` and
  `FUNCTION_COMPONENTS`
- callback hook names are in neither allow-list
- unknown keys throw `UNSUPPORTED_COMPONENT`

So the source suggests that direct hook registration via `components` is part
of the declared type surface, but the current `create(...)` implementation does
not appear to support it cleanly. Searchlight should not treat this as settled
runtime behavior parity.

## Hook names

Source of truth:
`reference/orama/packages/orama/src/components/plugins.ts`

Available plugin hook names:

- `beforeInsert`
- `afterInsert`
- `beforeRemove`
- `afterRemove`
- `beforeUpdate`
- `afterUpdate`
- `beforeUpsert`
- `afterUpsert`
- `beforeSearch`
- `afterSearch`
- `beforeInsertMultiple`
- `afterInsertMultiple`
- `beforeRemoveMultiple`
- `afterRemoveMultiple`
- `beforeUpdateMultiple`
- `afterUpdateMultiple`
- `beforeUpsertMultiple`
- `afterUpsertMultiple`
- `beforeLoad`
- `afterLoad`
- `afterCreate`

Callback shapes from `types.ts`:

- single-document lifecycle hooks such as `beforeInsert` / `afterRemove` use:
  `(orama, id, doc?) => SyncOrAsyncValue`
- multiple-document or multiple-id lifecycle hooks use:
  `(orama, docsOrIds) => SyncOrAsyncValue`
- `beforeSearch` uses:
  `(orama, params, language) => SyncOrAsyncValue`
- `afterSearch` uses:
  `(orama, params, language, results) => SyncOrAsyncValue`
- `afterCreate` uses:
  `(orama) => SyncOrAsyncValue`

Important source note:

- `AVAILABLE_PLUGIN_HOOKS` includes `beforeLoad` and `afterLoad`
- the current `create.ts` path explicitly initializes arrays for the insert /
  remove / update / search / multiple-operation hooks and `afterCreate`
- `beforeInsertMultiple` is initialized and participates in async-detection
  checks, but current `insert.ts` still dispatches only
  `afterInsertMultiple`
- `beforeLoad` / `afterLoad` are present in the plugin hook list, but are not
  visibly initialized on the Orama instance in `create.ts`
- there is no `beforeCreate`
- there are no `beforeSave` / `afterSave` hooks in the available hook list
- `beforeLoad` / `afterLoad` also do not appear in the visible
  `OramaPluginSync` type surface alongside the other hooks

That means Searchlight should treat the source, not the docs, as the real
contract baseline when deciding what parity means.

## Hook execution ordering

Hook runner source:
`reference/orama/packages/orama/src/components/hooks.ts`

Observed behavior:

- hooks run in array order
- async detection is done per hook batch via `hooks.some(isAsyncFunction)`
- if any hook in the batch is async, the whole batch runs through the async
  path
- async hooks are awaited sequentially in that batch path
- sync hooks also run sequentially in array order
- there is no parallel hook execution in the core runners

`beforeSearch` and `afterSearch` use dedicated runners with their own callback
shapes; they do not reuse the generic single- or multiple-hook runners.

Plugin hook collection source:
`reference/orama/packages/orama/src/components/plugins.ts`

Observed behavior:

- Orama iterates the `plugins` array in order
- for a given hook name, it appends each plugin's function to the hook list
- resulting hook execution order is the same as plugin registration order

This ordering is source-confirmed, not just inferred.

Plugin hook collection also has explicit error isolation:

- `getAllPluginsByHook(...)` wraps plugin hook access in `try/catch`
- failures are rethrown as `PLUGIN_CRASHED`

## How plugin components are merged

Component merge behavior lives in `create.ts`.

Process:

1. Start with `components ?? {}`
2. For each plugin in `plugins`:
   - if it has a callable `getComponents`, call it with `schema`
   - inspect the returned component keys
   - if any key already exists in `components`, throw
     `PLUGIN_COMPONENT_CONFLICT`
   - otherwise merge the plugin components into the current component map
3. Resolve defaults for missing function components
4. Resolve built-in defaults for object components that are still missing

Important implications:

- plugin components are merged before built-in default object components are
  created
- plugin component conflicts are checked against the already accumulated
  component map
- plugin order matters when two plugins want the same component slot

## Component conflict behavior

Source-confirmed conflict rule from `create.ts`:

- if a plugin tries to register a component key that already exists in
  `components`, create throws `PLUGIN_COMPONENT_CONFLICT`

This covers:

- user-supplied component versus plugin component
- earlier plugin component versus later plugin component

There is no silent override.

## Bookkeeping and instance identity

Source: `create.ts`

- each Orama instance gets an `id`
- if no `id` is supplied, `uniqueId()` generates one
- the created instance stores the `plugins` array on `orama.plugins`
- plugin hook discovery later reads from `orama.plugins`
- the instance also separates component interfaces from component-created data:
  - `orama.index`, `orama.sorter`, `orama.documentsStore`, `orama.pinning`
    hold component interfaces
  - `orama.data.index`, `orama.data.docs`, `orama.data.sorting`,
    `orama.data.pinning` hold the runtime data created by those components

This is lightweight bookkeeping, but it matters because plugin ordering and
plugin presence are part of the runtime behavior.

## Documented API vs source-confirmed behavior

### Documented by Orama docs

- Orama has a plugin system
- plugins extend core behavior
- official plugins live in the monorepo
- users can write custom plugins

### Source-confirmed and especially important for parity work

- components are merged at `create(...)` time
- component conflicts throw immediately
- hook order follows plugin registration order
- hook execution is sequential
- plugins may replace core components such as `index`

## Implications for Searchlight spec work

- The Dart design needs a create-time extension surface, not a bolt-on helper.
- Component replacement and lifecycle hooks are separate concerns in Orama and
  should be modeled separately in the spec.
- Deterministic ordering and deterministic conflict failures are not optional
  details; they are part of the architecture contract.
- The spec should decide explicitly whether to include only the currently
  exercised hooks or to match Orama's wider hook-name surface, including the
  load-related names present in source.
