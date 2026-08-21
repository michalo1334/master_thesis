# Dashboard Workspace Persistence Simplification

## Goal

Reduce repeated dashboard workspace registration and report lifecycle code.
Keep the existing ID-only persistence contract and lazy recovery behavior.

## Scope

Change only the dashboard workspace registration, catalog open action, and shared async-report lifecycle.

Keep the localStorage write effect in `DashboardHost.svelte`.
Do not add debouncing, cancellation, a new storage layer, or a generic report-data abstraction.

## Existing Behavior To Keep

The workspace persistence envelope contains dashboard ribbon state and persisted documents.
Each document descriptor contains only:

```ts
{ kind, ids, title }
```

The descriptor must not contain report data, graph data, callbacks, API objects, or other loaded state.

`GenericWorkspaceModel.restore()` creates each persisted document with the registration factory. It calls `recover()` only for the selected document. The document fetches its data when it becomes active.

`DashboardHost.svelte` calls `workspace.toPersistence()` inside `$effect`. The snapshot reads reactive workspace state. Svelte reruns the effect after a relevant state change. The effect is the single model-to-localStorage bridge.

## Current Problems

`Dashboard.svelte` has a `document.kind === "document-catalog"` branch. The branch exists only because `DocumentCatalog.svelte` needs `onOpen` in addition to its normal `document` and `api` props.

`dashboard-registry.ts` has separate `views` and `factories` maps. Both map the same document kind to related behavior.

`WorkspaceModel.svelte.ts` has separate `documentTypes` and `documentCreators` lists for graph, catalog, and Runs creation.

`SimulationReportDocument`, `OptimizationReportDocument`, and `AnalysisReportDocument` repeat the same async-report state and lifecycle methods.

## Design

Use one `dashboardRegistry` entry per document kind.

```ts
type DashboardDocumentRegistration = {
  view: Component<{ document: WorkspaceDocument; api: DashboardApi }>;
  fromPersisted?: DocumentFactory<WorkspaceDocument, DashboardRecoveryContext>;
  createOption?: { id: string; label: string; icon?: string };
  create?(workspace: WorkspaceModel): void;
};
```

The registry is the source of truth for:

- Component rendering.
- Persisted-document restoration.
- Items in the Create document menu.
- Creation actions for menu items.

`comparison-report` has a view only. It has no restoration factory and no create action because it depends on live report document references.

The catalog document owns its `openItem(item)` action. The action delegates to `WorkspaceModel.openCatalogItem(api, item)`.

The document action must be bound in both creation paths:

1. `WorkspaceModel.openDocumentCatalog()` for a newly created catalog document.
2. `DocumentCatalogDocument.fromPersisted(data, context)` for a restored catalog document.

Do not bind the action only in `openDocumentCatalog()`. A restored catalog uses `fromPersisted()` and otherwise cannot open catalog rows after a page reload.

The catalog document may use a no-op opener only for workspace unit tests that construct a model without an API. The normal dashboard model must always bind a live API callback.

`AsyncReportDocument` owns behavior that is identical for all three async reports:

- `title`, `hasUnread`, and `errorReason` state.
- `needsRecovery()`.
- `canClose()`.
- `markRead()` and `markUnread()`.
- `markError()` and `markErrorMessage()`.
- `setProgress()`.

Each concrete report document keeps its own IDs, persistence validation, `toPersisted()`, `fromPersisted()`, `recover()`, API request, report-data assignment, and report-specific UI state.

Do not move `ComparisonReportDocument` into `AsyncReportDocument`. It references live documents and does not use the same fetch/recovery lifecycle.

## Document Audit

The dashboard workspace has one base class and eight document models.

Base class: `WorkspaceDocumentBase` (in `dashboard/workspace/WorkspaceDocument.svelte.ts`). It extends the kit `UiWorkspaceDocument` and adds `isAsyncReportDocument()`. It also hosts `AsyncReportDocument`, the shared async-report base.

The eight dashboard document models:

1. `SimulationReportDocument` (`simulation-report/SimulationReportDocument.svelte.ts`)
2. `OptimizationReportDocument` (`optimization-report/OptimizationReportDocument.svelte.ts`)
3. `AnalysisReportDocument` (`analysis-report/AnalysisReportDocument.svelte.ts`)
4. `ComparisonReportDocument` (`comparison-report/ComparisonReportDocument.svelte.ts`)
5. `EditableGraphDocument` (`graph/EditableGraphDocument.svelte.ts`)
6. `GraphDiffDocument` (`graph/GraphDiffDocument.svelte.ts`)
7. `DocumentCatalogDocument` (`document-catalog/DocumentCatalogDocument.svelte.ts`)
8. `RunsDocument` (`runs/RunsDocument.svelte.ts`)

### Exact duplicates

`SimulationReportDocument` and `OptimizationReportDocument` each declare the same three members, which are moved to `AsyncReportDocument`:

- `analysisId = $state<string>()`
- `analysisTitle = $state<string>()`
- `setAnalysis(analysis: { id: string; title: string } | null)`

`AnalysisReportDocument` does not use these members. It inherits them from `AsyncReportDocument` as harmless unused state; no intermediate base class is added.

### Explicit non-merges

- `ComparisonReportDocument` is not moved into `AsyncReportDocument`. It references live report documents and does not use the fetch/recovery lifecycle.
- `EditableGraphDocument`, `GraphDiffDocument`, `DocumentCatalogDocument`, and `RunsDocument` are not moved into `AsyncReportDocument`. They are not async reports.
- `DocumentCatalogDocument` and `RunsDocument` keep their own `fromPersisted` that ignores persisted data. Their guards are not changed because they accept no persisted data and do not validate it.

## Implementation Steps

1. Update `DocumentCatalogDocument.svelte.ts`.
   - Define the catalog-item opener type.
   - Store an opener callback on the document.
   - Add `openItem(item)` that calls the stored callback.
   - Accept the opener in the constructor or through one small binding method.
   - In `fromPersisted`, create the document with a callback that uses `context.workspace.openCatalogItem(context.api, item)`.
   - Keep its persisted descriptor exactly `{ kind: "document-catalog", ids: {}, title }`.

2. Update `WorkspaceModel.svelte.ts`.
   - Retain the constructor API reference so a newly created catalog can bind its opener.
   - Create catalog documents through one helper that binds `openCatalogItem` to that API.
   - Use that helper from `openDocumentCatalog()`.
   - Build the generic persistence factory map from registry `fromPersisted` entries.
   - Remove `documentCreators`.
   - Derive `documentTypes` from registry `createOption` entries.
   - Route `handleCreateDocument(typeId)` to the matching registry `create` action.
   - Preserve menu order: graph, Documents, Runs.

3. Update `dashboard-registry.ts`.
   - Replace the separate `views` and `factories` records with one registration record.
   - Use `fromPersisted` only for persistable document kinds.
   - Add `createOption` and `create` only for graph, document catalog, and Runs.
   - Graph creation must still open the topology picker. It must not create an empty graph document directly.
   - Catalog and Runs creation must retain their singleton behavior through existing workspace methods.

4. Update `DocumentCatalog.svelte` and `Dashboard.svelte`.
   - Remove the `onOpen` prop from `DocumentCatalog.svelte`.
   - Call `document.openItem(item)` in `openSelected()`.
   - Remove the direct `DocumentCatalog` import from `Dashboard.svelte`.
   - Render every view through `dashboardRegistry[document.kind]?.view` with `{ document, api }`.
   - Do not add a union of component prop types or a second rendering branch.

5. Update `WorkspaceDocument.svelte.ts` and the three async report documents.
   - Add the common state and methods to `AsyncReportDocument`.
   - Import `formatDashboardErrorCode` in the base class.
   - Remove only exact duplicates from the simulation, optimization, and analysis report classes.
   - Delete now-unused error-code and error-type imports from subclasses.
   - Keep all report-specific reset behavior. For example, `markReady()` and `markPending()` still clear report-specific loaded data.

6. Update tests.
   - Keep the existing singleton creation tests.
   - Add or update a unit test that restores a catalog descriptor and calls its opener. Assert that it delegates to `workspace.openCatalogItem` with the recovery-context API and item.
   - Keep tests for a non-selected restored report remaining unloaded until it becomes selected.
   - Update component tests only for the removed `onOpen` prop and unified registry lookup.

7. Move `analysisId`, `analysisTitle`, and `setAnalysis` to `AsyncReportDocument`.
   - Add the three members to `AsyncReportDocument` in `dashboard/workspace/WorkspaceDocument.svelte.ts`.
   - Remove the exact duplicates from `SimulationReportDocument` and `OptimizationReportDocument`.
   - Leave `AnalysisReportDocument` unchanged. It inherits the members as harmless unused state; do not add an intermediate base class.

8. Add one generic persisted-document validator and use it in the five guards.
   - Add `isPersistedDocumentOfKind<Ids extends Record<string, string>>(value, kind, idKeys)` to `ui-kit/workspace/workspace-persistence.ts`. It validates: object, exact `kind`, `ids` object, all required `idKeys` present as strings, and `title` as string. Return type is `value is PersistedWorkspaceDocument & { ids: Ids }`.
   - Replace the local guard in each of these five documents with a call to the helper:
     - `SimulationReportDocument` (`simulation-report`)
     - `OptimizationReportDocument` (`optimization-report`)
     - `AnalysisReportDocument` (`analysis-report`)
     - `EditableGraphDocument` (`graph`)
     - `GraphDiffDocument` (`graph-diff`)
   - Do not change `DocumentCatalogDocument` or `RunsDocument` guards. They accept no persisted data and do not validate it.
   - Keep the persistence descriptor contract exactly `{ kind, ids, title }` and lazy recovery unchanged. Do not touch `DashboardHost`'s `$effect`.

## Verification

Run these checks after the changes:

1. `npm run check` or the repository typecheck command from `src/assets`.
2. The affected Vitest workspace and dashboard tests.
3. The Svelte autofixer for changed `.svelte` files until it reports no suggestions.
4. `mix precommit` from `src`.
5. Manual browser check:
   - Open Documents, select an item, and open it.
   - Reload with Documents selected, then select and open an item again.
   - Reload with a report tab not selected. Confirm no report fetch starts until its tab is selected.
   - Change workspace state and reload. Confirm tabs, order, selected tab, ribbon state, and titles restore.

## Non-Goals

- Do not change the persistence version or descriptor schema.
- Do not persist comparison reports.
- Do not fetch all restored documents eagerly.
- Do not replace `$effect` with model mutation hooks.
- Do not add debounce logic until localStorage writes are a measured problem.
