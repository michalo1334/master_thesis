# Dashboard Interface → App-Agnostic UI Kit

> Untangle in place in chunks, then extract in chunks. Every phase = one reviewable PR.
> Decisions locked: (1) full polymorphism, (2) polymorphic `canClose()`, (3) `Icon: string`, (4) lazy `src/assets/svelte/ui-kit/` with barrel, (5) rename `--ds-*` → `--ui-*` now, (6) registry owns `View` (no `Document ↔ View` cycle), (7) **workspace is kit** — generic `WorkspaceDocument` / `WorkspaceModel` / `WorkspaceShell` / `DocumentOutline` move to `ui-kit/workspace/`.

## 1. Context & scope

Single Phoenix 1.8 + Svelte 5 runes + bits-ui ^2.18 + Tailwind v4 app.
LiveView `src/lib/network_defense_web/live/web/dashboard/dashboard_live.ex`
hosts `src/assets/svelte/DashboardHost.svelte` → `src/assets/svelte/Dashboard.svelte`.
All dashboard chrome lives under `src/assets/svelte/dashboard/` (72 .svelte, 95 .ts).

```
src/assets/
  css/
    design-tokens.css      # 153 lines, --ds-*, 3 themes
    dashboard.css          # bits-ui menu chrome
    app.css                # Tailwind v4 + Skeleton cerberus, imports tokens
  svelte/
    Dashboard.svelte       # grid: appbar / ribbon / workspace / statusbar
    DashboardHost.svelte   # creates DashboardModel, wires live events
    dashboard/
      ui/                  # Icon, Checkbox, Slider, Select, NumberInput, RibbonButton, SplitButton, OptionPickerDialog
      controls/            # FilterableTable, MultiSelectFilter
      ribbon/              # Ribbon, RibbonTab, RibbonSection, ribbon-context, DashboardRibbon
      shell/               # AppBar, StatusBar
      workspace/           # Workspace.svelte, DocumentOutline.svelte, WorkspaceModel.svelte.ts, WorkspaceDocument.svelte.ts
      inspector/           # Inspector, InspectorField, DashboardInspector + per-type panels
      graph/               # canvas, network, presentation, layout — DOMAIN, stays
      simulation-report/   # DOMAIN — concrete doc + view
      optimization-report/ # DOMAIN
      comparison-report/   # DOMAIN
      document-catalog/    # DOMAIN
      analysis/            # DOMAIN
      contract.ts          # re-exports contracts.generated.ts
      types.ts             # IconName union
      DashboardModel.svelte.ts
```

Build: Vite root `src/assets/` (`src/assets/vite.config.mjs` → `svelte({css:"injected"})`,
`@tailwindcss/vite`, `liveSveltePlugin({entrypoint:"./js/server.ts"})`).
SSR via `src/assets/js/server.ts` → `src/priv/svelte`. No workspaces, no `$lib` alias,
no existing library (`src/package.json:1`, `src/assets/svelte.config.js:1`,
`src/assets/tsconfig.json:1`, `src/vitest.config.ts:1`).

Styling: 753 `var(--ds-*)` usages across 45 .svelte files, Svelte scoped `<style>`
+ `:global(...)` for bits-ui internals. Stylelint plugin `stylelint-plugin-ds-colors`
hardcodes token path.

Contracts: Elixir `src/lib/network_defense_web/contracts/dashboard/**` + `mix gen.contracts`
→ `src/assets/svelte/contracts.generated.ts` (1002 lines, CI `git diff --exit-code`),
re-exported `src/assets/svelte/dashboard/contract.ts` (168 lines). Kit imports **zero** contracts.

Verify every phase: `npm run check` (svelte-check), `npm test` (vitest `assets/svelte/dashboard/**/*.test.ts`,
setup `src/assets/svelte/test-setup.ts`), `mix precommit`, visual check of `DashboardLive`.

### What moves to kit vs. stays

```
KIT  src/assets/svelte/ui-kit/                ← lazy, no contracts
  workspace/  WorkspaceDocument (generic base), GenericWorkspaceModel<D>,
              WorkspaceShell, DocumentOutline (generic), document-outline helpers, registry types
  primitives/ Icon (string), Checkbox, Slider, Select, NumberInput, RibbonButton, SplitButton
  composites/ FilterableTable, MultiSelectFilter (icon-free), OptionPickerDialog
  layout/     Ribbon family, AppBar, StatusBar, Inspector, InspectorField
  styles/     tokens.css (--ui-* + --ds-* alias)

APP  src/assets/svelte/dashboard/              ← domain
  6 concrete docs: EditableGraphDocument, GraphDiffDocument, SimulationReportDocument,
                   OptimizationReportDocument, ComparisonReportDocument, DocumentCatalogDocument
  graph/**, per-type inspector/*NodeInfo, simulation/optimization/comparison/document-catalog/analysis/**
  ribbon/DashboardRibbon.svelte (app instance), dashboard-registry.ts (kind → View), buildDashboardRows()
  contract.ts, contracts.generated.ts, dashboard-api.ts, DashboardModel, types.ts (DomainIconName)
```

`WorkspaceModel` today (920 lines) mixes **generic** (documents / selection / reorder / canClose / tabs)
with **domain** (`graphSummaries: GraphSummary[]`, `folders: FolderSummary[]`, `analysisOptions`,
`topologyPicker*`, `activeFootholdHosts`, `ensureInitialFoothold`). Kit takes the generic core;
domain stays app-side via composition (see A3).

---

## 2. Coupling map

```
                        ┌─────────────────────────────────┐
                        │         dashboard/ (today)        │
                        │                                 │
  LOW ───────────────►  │  ui/Checkbox,Select,NumberInput  │  ← zero domain imports
                        │  ui/Slider,RibbonButton         │    → kit primitives
                        │  controls/FilterableTable       │    → kit composites
                        │  ribbon/Ribbon family           │    → kit layout
                        │  shell/AppBar,StatusBar         │    → kit layout
                        │  inspector/Inspector,Field      │    → kit layout
                        ├─────────────────────────────────┤
  MEDIUM ───────────►   │  ui/Icon  ──► types/IconName    │  ← leaks DomainIconName
                        │  ui/SplitButton ──► IconName    │    → kit Icon: string
                        │  ui/OptionPickerDialog ──►      │
                        │      controls/FilterableTable   │    ui → controls cycle
                        │  controls/MultiSelectFilter ──► │
                        │      ui/Icon ("filter")         │    controls → ui cycle
                        │  ribbon/DashboardRibbon ──►     │
                        │      contract, ForceParams      │    type-only, stays app
                        │  workspace/DocumentOutline ──►  │
                        │      contract, WorkspaceDoc     │    → kit generic Outline
                        ├─────────────────────────────────┤
  HIGH (now kit) ───►   │  workspace/WorkspaceDocument    │  ← thin base, now kit base
                        │  workspace/WorkspaceModel       │  ← god-factory → GenericWM (kit)
                        │  workspace/Workspace.svelte     │  ← model: WorkspaceModel → prop-driven Shell (kit)
                        │  Dashboard.svelte (root)        │  ← arrangeNetwork, #if ladder → registry
                        │      arrangeNetwork import      │
                        └─────────────────────────────────┘

  Cross-cutting: design-tokens.css  (--ds-* → --ui-*, dead theme selectors,
                 missing --ds-text-xl / --ds-color-accent-contrast)
```

| Area | Coupling | Destination | Fix |
|------|----------|-------------|-----|
| Primitives, FilterableTable, Ribbon shell, shell/inspector shells | LOW | kit | location + prefix rename only |
| Icon / SplitButton | MEDIUM | kit | `name: string` generic, `icon?: string` |
| OptionPickerDialog ↔ FilterableTable | MEDIUM | kit | move together in B2 |
| MultiSelectFilter | MEDIUM | kit | inline SVG, drop `ui/Icon` import |
| **WorkspaceDocument base** | **HIGH→kit** | **kit/workspace** | abstract `id/kind/title/icon/documentLabel/canClose()` + `string` icon |
| **WorkspaceModel** | **HIGH→kit** | **kit/workspace** | `GenericWorkspaceModel<D>` (documents only); app composes domain via `DashboardWorkspaceModel` |
| **Workspace.svelte** | **HIGH→kit** | **kit/workspace** | keep `model: GenericWorkspaceModel<D>` prop (intra-kit), fix inspector slot ownership |
| **DocumentOutline** | **MEDIUM→kit** | **kit/workspace** | generic `rows: OutlineRow[]` + `rowSnippet`; app supplies `buildDashboardRows()` |
| Dashboard.svelte dispatch | HIGH | app | registry `views[document.kind]` replaces `#if` ladder, no `as` casts |

---

## 3. Document ladder — before / after (registry, no cycle)

### Before (today) — `src/assets/svelte/dashboard/workspace/WorkspaceDocument.svelte.ts:10`

```
WorkspaceDocumentBase
  │  isReportDocument(): boolean          ← only member, no id/title/icon/kind
  │  isAsyncReportDocument()
  │
  ├── AsyncReportDocument<Kind>           ← reportKind, setReportData(), markError()
  │     ├── SimulationReportDocument  kind="simulation-report"  icon="simulation-report"
  │     └── OptimizationReportDocument kind="optimization-report" icon="shield"
  │
  ├── EditableGraphDocument            kind="graph"              icon="graph"
  ├── GraphDiffDocument                kind="graph-diff"         icon="graph-diff"
  ├── DocumentCatalogDocument          kind="document-catalog"   icon="squares-2x2"
  └── ComparisonReportDocument         kind="comparison-report"  icon="simulation-report"
         └─ overrides isReportDocument(): true  (does NOT extend AsyncReportDocument)

  Union: WorkspaceDocument = 6 members, guards: isReport / isGraphDiff / isAsyncReportDocument
  Each doc declares: readonly id, kind, title, icon: IconName, documentLabel  — NOT enforced by base
  WorkspaceModel (920 lines) hard-imports all 6 docs + FolderSummary/GraphSummary + analyses

  View dispatch: Dashboard.svelte:162  #if ladder + 6 casts
  WorkspaceModel → 6 docs (hard)
  View .svelte ──type──► Document
```

**Non-polymorphic call sites (why it hurts):**

```ts
// Dashboard.svelte:162 — today: switch + 6 casts, TS already narrows on kind
{#if document.kind === "graph"}
  <EditableCanvas document={document as EditableGraphDocument} ... />
{:else if document.kind === "simulation-report"}
  <SimulationReport document={document as SimulationReportDocument} ... />
{/if}

// DashboardModel.svelte.ts:125 — two patterns for same lookup
const r = documents.find(d => d.kind === "simulation-report" && ...) as SimulationReportDocument  // manual
const r = findReport(id, "simulation")  // polymorphic isAsyncReportDocument() + reportKind

// WorkspaceModel.svelte.ts:351 — logic outside the document
canCloseDocument(d: WorkspaceDocument) {
  return (d.kind !== "simulation-report" && d.kind !== "optimization-report")
      || d.status === "loaded" || d.status === "error";
}
```

### Why storing `View` inside the document causes a cycle

```
Today (no cycle, one-way):
  EditableGraphDocument.svelte.ts ──X (no .svelte import)──► EditableCanvas.svelte:7
  EditableCanvas.svelte ──type──► EditableGraphDocument  (erased, Props)

If Document stores View:
  EditableGraphDocument.svelte.ts ──runtime──► EditableCanvas.svelte  (needs value import: readonly View = EditableCanvas)
          ▲                                                    │
          └──────────── type (or runtime if instanceof) ───────┘
  Bundler: Circular dependency. Model now drags bits-ui/echarts/d3-force into WorkspaceModel graph.
  Fix: registry owns both.

Registry (no cycle):
  workspace-registry.ts ──runtime──► Document (6 classes)
                        ──runtime──► View (6 .svelte)
  Document ──X──► View        View ──type──► Document (erased)
```

### After (target) — kit base + registry + kit workspace

```
KIT  src/assets/svelte/ui-kit/workspace/WorkspaceDocument.svelte.ts
  export abstract class UiWorkspaceDocument        ← ENFORCES shared contract
    abstract readonly id: string
    abstract readonly kind: string
    abstract readonly title: string
    abstract readonly icon: string                ← was IconName, now string (locked)
    abstract readonly documentLabel: string
    canClose(): boolean { return true }           ← override in reports
    isReportDocument(): boolean
    isAsyncReportDocument(): this is UiAsyncReportDocument<ReportKind>

KIT  src/assets/svelte/ui-kit/workspace/WorkspaceModel.svelte.ts
  export class GenericWorkspaceModel<D extends UiWorkspaceDocument>  ← documents/selection/reorder/canClose only
    documents = $state<D[]>([]); selectedDocumentId = $state<string|undefined>();
    reorderDocuments(a,b), canCloseDocument(d) { return d.canClose(); }, activeDocument, hasUnreadReport …

APP  src/assets/svelte/dashboard/workspace/DashboardWorkspaceModel.svelte.ts (or extends)
  export class DashboardWorkspaceModel extends GenericWorkspaceModel<WorkspaceDocument> {
    // domain only: graphSummaries: GraphSummary[], folders: FolderSummary[], analysisOptions, pickers, ensureInitialFoothold …
  }
  // OR composition: dashboard has { generic: GenericWorkspaceModel; domain: DomainState }
  // Chosen: composition via GenericWorkspaceModel<D> + DashboardWorkspaceModel wrapper (cleaner, no diamond)

APP  6 concrete docs  extends UiWorkspaceDocument  (in dashboard/graph, simulation-report, …)
  EditableGraphDocument            canClose() { return true }
  SimulationReportDocument         canClose() { return status==="loaded"||status==="error" }
  OptimizationReportDocument       canClose() { return status==="loaded"||status==="error" }
  GraphDiffDocument                canClose() { return true }
  DocumentCatalogDocument          canClose() { return true }
  ComparisonReportDocument         canClose() { return true }  (aligned, extends base or Async)

APP  src/assets/svelte/dashboard/workspace/dashboard-registry.ts
  export const dashboardRegistry: DocumentRegistry<WorkspaceDocument> = {
    views: { graph: EditableCanvas, "graph-diff": GraphDiff, "simulation-report": SimulationReport, … },
    kinds: { graph: { label:"Graph", icon:"graph", create:()=>new EditableGraphDocument() }, … },
    create(kind) { return kinds[kind].create(); }
  }
  Dashboard.svelte:162 → {@const View = dashboardRegistry.views[document.kind]} <View {document} {api} />
```

**After — call sites become polymorphic + registry-driven:**

```ts
// Dashboard.svelte — no #if, no casts, Svelte 5 runes: <View> where View is a variable (svelte/legacy-svelte-component: <svelte:component> is legacy)
{#snippet content(document: UiWorkspaceDocument)}
  {@const View = dashboardRegistry.views[document.kind]}
  <View {document} {api} />
{/snippet}
// alternative snippet: {@render dashboardRegistry.snippets[document.kind](document)}  Snippet<[D]> from 'svelte' — equivalent

// WorkspaceModel — delegates to document
canCloseDocument(d: UiWorkspaceDocument) { return d.canClose(); }

// Icon — kit is generic
// kit:  <Icon name: string />
// app:  type DomainIconName = UiIconName | "shield" | "graph" | "graph-diff" | ...
//       <Icon name={(doc.icon as DomainIconName)} />
```

```
Before:  WorkspaceModel ──► 6 docs (hard) ──► contract
         Dashboard.svelte ──► 6 Views via #if ladder + casts
After:   GenericWorkspaceModel<D> ──► UiWorkspaceDocument (interface, no concrete imports)
         DashboardWorkspaceModel (app) ──► 6 docs + GenericWM (composition)
         registry ──► docs + views (outside classes, no cycle)
         Dashboard.svelte ──► registry[document.kind]
```

---

## 3b. Audit — additional ladders / missed polymorphic spots (explorer_fast)

> Found by `explorer_fast` grep across `src/assets/svelte` for `kind/status/strategy/type` switches.
> Ranked: **HIGH** → add to A2/A3, **MEDIUM (strategy axis)** → defer, **LOW** → keep as-is.

### HIGH — add to plan (same document-kind axis, no new concepts)

```
WorkspaceModel.setReportAnalysis:231 ── if report.kind === "simulation-report" ? experimentId : optimizationId
                                        + ? "simulation_report" : "optimization_report"
ReportInspector.svelte:16 ────────────  document.kind === "simulation-report" ? experimentId : optimizationId
WorkspaceModel.handleCreateDocument:873  if typeId==="graph" … else if==="document-catalog"  (documentTypes[] already exists)
WorkspaceModel.openCatalogItem:568 ──── if item.kind==="graph" … if==="simulation_report" … else optimization
WorkspaceModel.createPending*:694/728  near-identical find-by-correlationId+push+activate (differs by budget/fields)
DashboardInspector.svelte:72 ─────────  #if selection?.kind==="graph" / selectable.type==="MissionCapability" / selectable / report
                                        + graph/presentation/registry.ts inspectorFor() is DEAD CODE (registered but never rendered)
```

**Why high:** same shape as already-planned `canClose` / `findReport` polymorphism. Fixing them in A2/A3 costs one accessor
per site, removes the last `kind` switches outside the registry, and for `DashboardInspector` also revives existing
polymorphic code (`registry.inspectorFor`) instead of writing new code.

**Target (added to A2/A3):**

```ts
// KIT — UiAsyncReportDocument (extends UiWorkspaceDocument)
abstract get reportId(): string | null;          // was status-guarded experimentId/optimizationId
abstract get reportApiKind(): "simulation_report" | "optimization_report"; // was ternary on kind

// APP — concrete
class SimulationReportDocument extends UiAsyncReportDocument<"simulation"> {
  get reportId() { return this.experimentId; }
  get reportApiKind() { return "simulation_report" as const; }
}
class OptimizationReportDocument extends UiAsyncReportDocument<"optimization"> {
  get reportId() { return this.optimizationId; }
  get reportApiKind() { return "optimization_report" as const; }
}

// Call sites — no if
// BEFORE — WorkspaceModel.setReportAnalysis:231 + ReportInspector.svelte:16
const reportId = report.kind === "simulation-report" ? report.experimentId : report.optimizationId;
const apiKind  = report.kind === "simulation-report" ? "simulation_report" : "optimization_report";
// AFTER
const reportId = report.reportId; const apiKind = report.reportApiKind;

// BEFORE — handleCreateDocument:873 / openCatalogItem:568
if (typeId === "graph") this.topologyPickerOpen = true; else if (typeId === "document-catalog") this.openDocumentCatalog();
if (item.kind === "graph") … else if (item.kind === "simulation_report") …
// AFTER — registry.create / catalogRegistry.open
dashboardRegistry.create(typeId);          // DashboardRegistry.kinds[typeId].create()
catalogRegistry.open(item, api);           // or registry-driven map kind → handler

// BEFORE — DashboardInspector.svelte:72 ladder (4 branches)
// AFTER — presentation registry (already exists, now wired)
import { inspectorFor } from "../graph/presentation/registry";
const Inspector = selection?.selectable ? (inspectorFor(selection.selectable.type) ?? EditableSelectionInspector) : null;
// MissionCapability branch kept as one extra check before registry, or registered as its own entry
```

**Note on `createPending*` dedupe (694/728):** collapse to `createPendingAsyncReport<Kind>(info)` only if `budget`
/ `strategy` fields align; otherwise **leave as two methods** — low value, defer unless budgets unified.

### MEDIUM — strategy axis (defer, separate follow-up)

```
OptimizationReport.svelte:165  #if strategy==="cvss" → 4 strategy panels (Cvss / SimulationInformed / TopologySegmentation / SimulatedAnnealing)
DashboardRibbon.svelte:228     #if activeOptimizationId==="simulation_informed"||"simulated_annealing" …
AnalysisModel.svelte.ts:66     needsSimulationSettings / needsFoothold predicates over runnableStrategies[]
optimization-report/to-analysis.ts:13  switch(strategy)  +  comparison-report.ts:76 formatStrategy
WorkspaceModel.catalogOptimizationStrategy:898  switch(strategy) default→"cvss"
```

Same axis (`OptimizationStrategy`), not document dispatch. Would be a `strategy → panel/config` registry
mirroring `graph/presentation/registry.ts`. **Out of scope for B3** — same wall as document registry but distinct.
Flag and do not block workspace extraction. If pursued, do as `C1 — Strategy panel registry` after B4.

### LOW — keep as-is (data narrowing / already polymorphic / state machine)

```
EditableGraphDocument:111 CanvasSelection kind==="node"/"edge" — closed 2-variant, domain-specific
GraphDiff.svelte:14 status==="added"/"removed"/"unchanged" — 3-value diff appearance
NetworkCanvas* / heatmap / ownership / SimulationReport — node.type edge.type narrowing for data access
  (presentation already via registry.nodePresentation/edgePresentation; these are data reads)
document.status==="pending"/"loading"/"error"/"ready"/"loaded" — per-report state machines (different sets)
CanvasNode/Edge — already registry-driven, no ladder
DocumentCatalog.kindLabels — already a map, not a ladder
DashboardModel optimization handlers — already via findOptimizationReport, no ladder
WorkspaceModel activeGraph/hasActiveGraph/ensureInitialFoothold/findOpenGraph — legitimate graph narrowing
```

**Decision:** **Include HIGH in A2/A3**, **exclude strategy axis** from this plan (note as `C1` follow-up), **no change** for LOW.

---

## 3d. TODO — DocumentOutline builder generic (algorithm decoupled from concrete documents)

> Analysis by `explorer_fast` (synced from `document-outline.ts` / `DocumentOutline.svelte`).
> Option chosen: **B — normalized OutlineNode** (kit is a dumb assembler over plain data, app owns domain).
> Full coupling table + adapter-vs-normalized comparison was in agent scratch; summarized below with diagrams.

### Why the current builder is not generic

```
                 ┌──────────────────────────────────────────────────┐
                 │  document-outline.ts  (today, 10 coupled sites) │
                 │                                                  │
  FolderSummary ─┼─► buildRows(documents, folders, summaries)       │
  GraphSummary  ─┤   OutlineRow { document: WorkspaceDocument }     │
  WorkspaceDoc  ─┤   isReport / isGraphDiff / kind==="graph"        │
                 │   analysisId, graphRevisionId, baseRevisionId    │
                 │   parentDocument() via parent_revision_id chain  │
                 │   folderIdForDocument() via GraphSummary lookup  │
                 │   rowKey() from document.id                      │
                 │   SvelteMap / SvelteSet (reactive, not needed)   │
                 └──────────────┬───────────────────────────────────┘
                                │ OutlineRow[] with domain objects
                                ▼
                 ┌──────────────────────────────────┐
                 │  DocumentOutline.svelte (shell)   │
                 │  row.document.title/icon/label    │
                 │  graphId(row.document) for drag   │
                 │  row.folder.name/id for headers   │
                 └──────────────────────────────────┘

  Kit cannot import FolderSummary / GraphSummary / WorkspaceDocument.
  Tree shape (nesting, buckets, "Reports"/"Analyses" headers, depth, cycle guard)
  is mixed with domain meaning (which doc is a report, which revision is parent).
```

**Coupling inventory (10 sites in `document-outline.ts`):**

| # | Code | Domain |
|---|------|--------|
| 1 | `buildRows(docs: WorkspaceDocument[], folders: FolderSummary[], summaries: GraphSummary[])` | signature names app types |
| 2 | `OutlineRow { document: WorkspaceDocument }` | row carries domain object |
| 3 | `ReportDocument Extract<WorkspaceDocument, {kind: "simulation-report" ...}>` | literal kind union |
| 4 | `hasAnalysisMetadata(d) = isReport(d) && analysisId` | reads `analysisId/Title` |
| 5 | `kind==="graph" && loadedRevisionId` → index | revision chain |
| 6 | `parentDocument()` — report→`graphRevisionId`, diff→`baseRevisionId`, graph→`parent_revision_id` | nesting |
| 7 | `folderIdForDocument()` via `GraphSummary[]` | folder buckets |
| 8 | `appendRoots filter isReport` → "Reports" header | section |
| 9 | `rowKey` from `document.id` / `folder.id` | keys |
| 10 | `graphIdForDocument()` for drag payload | drag |

Template also reads `documentLabel/icon/title`, `folder.name/id`.

### Generic replacement — Option B (normalized OutlineNode)

```
App (owns meaning)                          Kit (owns shape, no domain imports)
─────────────────                           ─────────────────
documents                                   OutlineNode[] ──┐
folders  ──► buildDashboardNodes() ──┐                      │
summaries                            ├─► OutlineNode[] ─────┤
             buildDashboardGroups() ─┘   OutlineGroup[] ───┤─► buildOutline() ─► OutlineRow[] ─► DocumentOutline
                                            plain data      │    pure, Map/Set, cycle guard
                                                            │    flat list, no WorkspaceDocument
```

**File tree — A4 (in place) vs B3 (kit extract):**

```
A4 — in place (still dashboard/)              B3 — after kit extract
──────────────────────────────                ──────────────────────
dashboard/workspace/                          ui-kit/workspace/
  document-outline.ts  (helpers only)           outline.ts  ← kit assembler (NEW)
    parentDocument()                             OutlineNode, OutlineGroup, OutlineRow
    folderIdForDocument()                        buildOutline(nodes, groups): OutlineRow[]
    hasAnalysisMetadata()                        → no SvelteMap, plain Map
    graphIdForDocument()                       DocumentOutline.svelte  (pure shell)
  build-dashboard-rows.ts (adapter, app)         rows: OutlineRow[] + rowSnippet
    buildDashboardNodes()                      dashboard/workspace/
    buildDashboardGroups()                       document-outline.ts (helpers stay)
    buildDashboardRows()                         build-dashboard-rows.ts (adapter, app)
  DocumentOutline.svelte (shell, still            DocumentOutline.svelte → re-export kit shell
    documents/folders props for now)
```

**Kit interfaces (new in `ui-kit/workspace/outline.ts`):**

```ts
// ui-kit/workspace/outline.ts — zero app imports, pure data

export interface OutlineNode {
  id: string;        // document id
  label: string;     // title
  icon: string;      // icon string (generic)
  kind: string;      // document kind, passes through for snippet dispatch
  groupId: string;   // folder id, "analyses", or "root"
  parentId?: string; // nesting within same group (revision parent)
  section?: { key: string; title: string }; // e.g. {key:"reports", title:"Reports"}
  ariaLabel?: string; // e.g. "Graph Untitled"
  dragData?: string;  // e.g. graph.id for drag-and-drop
}

export interface OutlineGroup {
  id: string;        // folder id or "analyses"
  label: string;     // folder name
  icon?: string;
  depth?: number;    // base document depth (folders=1, analyses=0, root=0)
}

export type OutlineRow =
  | { type: "item";   id: string; label: string; icon: string; kind: string;
      depth: number; ariaLabel?: string; dragData?: string }
  | { type: "header"; id: string; label: string; icon?: string;
      kind: "folder" | "section" | "group" };

export function buildOutline(
  nodes: readonly OutlineNode[],
  groups: readonly OutlineGroup[],
): OutlineRow[] {
  // 1. bucket = groupId if present in groups, else "root"
  // 2. children = parentId edges, only when parent is in same bucket
  // 3. cycle guard: node whose parentId chain revisits itself → bucket root
  // 4. emit per group (in order): header, plain roots at group.depth,
  //    per section (first-seen): section header, section roots at depth+1
  // 5. emit root bucket last, depth 0, no header
}
```

**App adapter — reuses existing helpers verbatim (no rewrite):**

```ts
// dashboard/workspace/build-dashboard-rows.ts — domain → normalized

import { buildOutline, type OutlineGroup, type OutlineNode, type OutlineRow } from "../../ui-kit/workspace/outline";
import { folderIdForDocument, graphIdForDocument, hasAnalysisMetadata, parentDocument } from "./document-outline";
import type { FolderSummary, GraphSummary } from "../contract";
import type { WorkspaceDocument } from "./WorkspaceDocument.svelte";

export function buildDashboardNodes(
  documents: readonly WorkspaceDocument[],
  folders: readonly FolderSummary[],
  graphSummaries: readonly GraphSummary[],
): OutlineNode[] {
  const graphsByRevisionId = new Map<string, WorkspaceDocument>();
  const folderIds = new Set(folders.map((f) => f.id));
  for (const d of documents)
    if (d.kind === "graph" && d.loadedRevisionId)
      graphsByRevisionId.set(d.loadedRevisionId, d);

  return documents.map((d) => {
    if (hasAnalysisMetadata(d)) {
      // Analysis reports leave the folder tree → "analyses" group, section per analysisId
      return {
        id: d.id, label: d.title, icon: d.icon, kind: d.kind,
        groupId: "analyses",
        section: { key: d.analysisId ?? d.analysisTitle ?? "Analysis",
                   title: d.analysisTitle ?? d.analysisId ?? "Analysis" },
        ariaLabel: `${d.documentLabel} ${d.title}`,
      };
    }
    const parent = parentDocument(d, graphsByRevisionId);
    const folderId = folderIdForDocument(d, graphSummaries);
    const groupId = folderId && folderIds.has(folderId) ? folderId : "root";
    return {
      id: d.id, label: d.title, icon: d.icon, kind: d.kind,
      groupId,
      parentId: parent?.id,
      section: !parent && isReport(d) ? { key: "reports", title: "Reports" } : undefined,
      ariaLabel: `${d.documentLabel} ${d.title}`,
      dragData: graphIdForDocument(d),
    };
  });
}

export function buildDashboardGroups(
  folders: readonly FolderSummary[],
  hasAnalyses: boolean,
): OutlineGroup[] {
  return [
    ...folders.map((f) => ({ id: f.id, label: f.name, icon: "folder", depth: 1 })),
    ...(hasAnalyses ? [{ id: "analyses", label: "Analyses", depth: 0 }] : []),
  ];
}

export function buildDashboardRows(
  documents: readonly WorkspaceDocument[],
  folders: readonly FolderSummary[],
  graphSummaries: readonly GraphSummary[],
): OutlineRow[] {
  const nodes = buildDashboardNodes(documents, folders, graphSummaries);
  const groups = buildDashboardGroups(folders, nodes.some((n) => n.groupId === "analyses"));
  return buildOutline(nodes, groups);
}

// Before: Document svelte held document objects, template read row.document.title
// After:  row is plain {label, icon, depth, ariaLabel} — no WorkspaceDocument in kit
```

**Before / after — DocumentOutline props:**

```svelte
<!-- BEFORE — A3 and earlier (today after A4 stub) -->
<DocumentOutline
  documents={model.documents}
  folders={model.folders}
  graphSummaries={model.graphSummaries}
  selectedDocumentId={model.selectedDocumentId}
  onSelectDocument={(id) => model.selectDocument(id)}
  onDeleteFolder={(id) => model.deleteFolder(id)}
  onMoveGraph={(graphId, folderId) => model.moveGraph(graphId, folderId)}
/>

<!-- AFTER — B3 (kit) -->
<script>
  import { buildDashboardRows } from "./build-dashboard-rows";
  const rows = $derived(buildDashboardRows(model.documents, model.folders, model.graphSummaries));
</script>

<DocumentOutline
  rows={rows}
  selectedId={model.selectedDocumentId}
  onSelect={(id) => model.selectDocument(id)}
  collapsed={outlineCollapsed}
  onCollapsedChange={(c) => (outlineCollapsed = c)}
>
  {#snippet rowSnippet(row)}
    {#if row.type === "header" && row.kind === "folder"}
      <span>{row.label}</span>
      <button onclick={() => model.deleteFolder(row.id)}>Delete</button>
    {:else if row.type === "item"}
      <!-- kit default: button with icon + label at depth indent -->
      <!-- app snippet adds move-menu for row.dragData -->
    {/if}
  {/snippet}
</DocumentOutline>
```

Depth / grouping preserved: folders emit plain docs at depth 1, orphan reports at depth 2;
"Analyses" emits reports at depth 1; root emits plain docs at depth 0, orphan reports at depth 1.
Cycle guard and `SvelteMap`→`Map` change keep the builder pure (called from `$derived`, recomputes wholesale).

See A4 code block below for the kit shell after B3. `document-outline.ts` shrinks to helpers only;
`build-dashboard-rows.ts` grows normalization; `DocumentOutline.svelte` becomes `rows + rowSnippet`.

---

## 3c. TODO — Inspector generic / Document → Inspector coupling (brainstorm, not yet implemented)

> A3 partially wired `inspectorFor` for the selectable branch only (`DashboardInspector.svelte:103` → `registry.inspectorFor`).
> Remaining ladder has 3 document/mode branches + heterogeneous inspector props. This TODO designs the fully generic,
> kit-extractable inspector that also couples `Document → Inspector` (like `Document → View` via `dashboardRegistry`).

### Current state (after A3)

```
DashboardInspector.svelte:72 — still 4 branches

  {#if selection?.kind === "graph"}                → GraphInspector
    props: { graph, parentTitle, onTitleChange, onOpenParent, analysisIds, analyses, … }
  {:else if selectable.type === "MissionCapability"}→ MissionCapabilityInspector
    props: { selectable: MissionCapabilityNode, graph, revisionId, canEditFlows, api, onUpdate }
  {:else if selectable}                             → inspectorFor(selectable)  ★ wired in A3
    props: { selectable: Host|Service|…, onUpdate }  (uniform for 12 types, heterogeneous only for MissionCapability)
  {:else if isReport}                               → ReportInspector
    props: { document: SimulationReportDocument|OptimizationReportDocument, analyses, onAnalysisChange }

  Registry: src/assets/svelte/dashboard/graph/presentation/registry.ts:68
    nodeRegistry (6) + edgeRegistry (7) → allInspectors[selectable.type] → Component<any>
    inspectorFor(selectable) now used, but only inside one branch. Two other branches bypass it.

  Kit already has: Inspector.svelte + InspectorField.svelte → ui-kit/layout (B4)
  App has: 12 per-type inspectors in inspector/{hosts,services,credentials,…}/ + ReportInspector + GraphInspector
```

**Why not yet generic:** document-level inspector depends on `document.kind` (graph vs report) while selectable
inspector depends on `selectable.type`. Props are heterogeneous: most need `{selectable}`, one needs
`{selectable, graph, api, revisionId, canEditFlows}`, report needs `{document}`. A generic kit cannot import any
of these domain types. Same layering problem as `Document → View` — solved there by `dashboardRegistry`.

### Goal

Make `DashboardInspector` a kit component (or leave a thin app `DashboardInspector` that delegates to registry) where
**both levels are registry-driven and `WorkspaceDocument` optionally couples to its inspector**:

```
Kit:   InspectorShell + InspectorRegistry<D, Sel, InspectorProps>  (no Selectable import)
App:   dashboardInspectorRegistry: { documentInspectors: Record<DocumentKind, Component>,
                                     selectableInspectors: Record<SelectableType, Component> }
       Document → Inspector via registry (not via class field, to avoid Document ↔ Inspector cycle)

WorkspaceDocument (optional coupling):  abstract getInspectorKind(): string
       or DocumentRegistry entry already holds  views + inspectors together:
       dashboardRegistry: { views, inspectors, kinds/create }  → single source of truth
```

Kit stays `contracts.generated.ts`-free; `Selectable` (`Node|Edge`) is a contract type so the kit registry must be
generic over `Selectable` as well (`InspectorRegistry<Doc, Sel>`), or accept `string` keys.

### Options — tradeoffs

```
Option A — Registry owns Inspector (recommended, lazy, mirrors Document→View)
  ┌─────────────────────────────────────────────────────────────────────────┐
  │  Kit: ui-kit/workspace/inspector-registry.ts (or workspace-registry.ts) │
  │    export interface InspectorRegistry<Doc extends UiWorkspaceDocument,   │
  │      Sel extends { type: string }> {                                    │
  │      documentInspectors: Record<string, Component<{document: Doc}>>;    │
  │      selectableInspectors: Record<string, Component<{selectable: Sel,   │
  │        context: InspectorContext }>>;                                   │
  │      fallback: Component;  // EditableSelectionInspector or Empty       │
  │    }                                                                    │
  │    export type InspectorContext = { graph?: LoadedGraph; api?: unknown; │
  │      revisionId?: string|null; canEditFlows?: boolean; onUpdate?: fn } │
  │  App: dashboard/inspector/dashboard-inspector-registry.ts               │
  │    export const dashboardInspectorRegistry = {                           │
  │      documentInspectors: { graph: GraphInspector, report: ReportInspector },│
  │      selectableInspectors: { Host: hostNode.inspector, …,               │
  │        MissionCapability: MissionCapabilityInspector, … }                │
  │    }  // reuses presentation nodeRegistry/edgeRegistry + report/graph   │
  │  DashboardInspector.svelte (kit or thin app wrapper) then:              │
  │    if (selection?.selectable)                                           │
  │      {@const C = registry.selectableInspectors[selection.type] ?? fallback} │
  │      <C selectable={selection} context={{graph, api, revisionId}} />   │
  │    else if (document) <DocInspector document={document} />              │
  └─────────────────────────────────────────────────────────────────────────┘
  Pros: no Document↔Inspector cycle (registry owns both), reuses existing
        presentation registry, uniform component signature via context bag,
        kit extractable without contract types (string keys).
  Cons: MissionCapability still needs extra context; solved by context bag
        (all inspectors receive same superset, ignore extras). Slight prop
        widening from strict HostNode to Selectable.

Option B — Document exposes inspector (polymorphic, Document→Inspector coupling)
  abstract class UiWorkspaceDocument { abstract get inspector(): Component | null; }
  // or getInspector(selection?: Selectable): Component
  Pros: true polymorphism, Document knows its inspector.
  Cons: Document must import Component (runtime) → same cycle risk as Document→View;
        needs registry indirection anyway to avoid bundling inspectors into model graph;
        selection-dependent inspector (graph vs selectable) doesn't fit single getter.
  Verdict: do not use — use Option A registry; keep Document agnostic, registry couples.

Option C — DocumentRegistry holds views + inspectors together (single registry)
  dashboardRegistry: { views: Record<kind, Component>, inspectors: Record<kind|type, Component> }
  Pros: one registry file, single import in Dashboard.svelte.
  Cons: mixes concerns (document chrome vs inspector detail); same as A but co-located.
  Verdict: acceptable — implement as dashboardRegistry extended with .inspectors if desired.
```

**Normalization for heterogeneous props (required for any option):**

Current mismatch: `HostInspector: {selectable: HostNode}`, `MissionCapabilityInspector: {selectable, graph, api, revisionId, canEditFlows, onUpdate}`,
`GraphInspector: {graph, parentTitle, …}` (no selectable), `ReportInspector: {document}`.

Kit uniform signature options:
- `Component<{ selectable?: Sel; document?: Doc; context?: { graph, api, revisionId, canEditFlows, onUpdate } }>` — all inspectors receive superset.
- Or two registries: `documentInspectors: Component<{document}>` and `selectableInspectors: Component<{selectable, context}>`.

Either works; pick **two registries + context bag** to keep graph/report level separate from selectable level.

**Recommendation (for A4/B3):**

1. Keep A3's partial `inspectorFor` wiring as is (no regression, 12 types now render correctly).
2. In **A4** (still in-place) introduce `src/assets/svelte/dashboard/inspector/inspector-registry.ts` (app-side stub)
   that re-exports `selectableInspectors = { …nodeRegistry, …edgeRegistry }` + `documentInspectors = { graph: GraphInspector, report: ReportInspector }`
   and change `DashboardInspector.svelte` to read from it (still 3 `{#if}` branches but driven by registry maps, not hard imports).
3. In **B3** (kit extraction) move `Inspector`/`InspectorField` + `InspectorRegistry` types to `ui-kit/layout/` or `ui-kit/workspace/`,
   and replace the remaining `{#if selection}` / `{#if isReport}` ladder with registry lookup:
   ```
   Before (A3): 4 branches, one registry-driven
   After (B3):  1 lookup: registry.documentInspectors[document.kind] ?? registry.selectableInspectors[selectable.type] ?? EmptyInspector
   ```
   With `documentInspectors` handling `graph` + `report` kinds and `selectableInspectors` handling node/edge types,
   `DashboardInspector` becomes a 10-line kit-style shell; per-type inspectors stay app-side.
4. Document→Inspector coupling is thus **registry-based**, not class-field-based — consistent with Document→View
   and avoids the `Document ↔ Inspector` cycle. If a future `UiWorkspaceDocument.getInspectorKind()` is desired,
   add it as `abstract get inspectorKind(): string` returning `selectable.type` or `kind`, but still resolve via registry.

Open question for next PR: whether to collapse `GraphInspector` (graph-level) into the same document-inspector registry
or keep it as a distinct `graphInspector` prop — keep distinct for now (different selection model).

---

## 4. Target architecture (after all phases)

```
src/assets/svelte/ui-kit/                         ← lazy location (locked)
  styles/
    tokens.css          ← --ui-* primary, --ds-* compat alias, --ui-text-xl, --ui-color-accent-contrast
    variants.css
  workspace/            ← ★ NEW — generic workspace is kit
    WorkspaceDocument.svelte.ts   ← UiWorkspaceDocument (+ UiAsyncReportDocument)
    WorkspaceModel.svelte.ts      ← GenericWorkspaceModel<D extends UiWorkspaceDocument>
    WorkspaceShell.svelte         ← generic tabs chrome (prop-driven, no model import)
    DocumentOutline.svelte        ← generic: rows + rowSnippet: Snippet<[Row]>
    document-outline.ts           ← generic helpers (pure), outline row types
    workspace-registry.ts         ← DocumentRegistry<D>, UiDocument types
    index.ts
  primitives/
    Icon.svelte              (name: string)
    Checkbox.svelte
    Slider.svelte
    Select.svelte
    NumberInput.svelte
    RibbonButton.svelte
    SplitButton.svelte       (icon?: string)
    index.ts
  composites/
    FilterableTable.svelte
    FilterableTable.types.ts
    MultiSelectFilter.svelte (icon-free, inline SVG)
    OptionPickerDialog.svelte
    OptionPickerDialogContent.svelte
    index.ts
  layout/
    Ribbon.svelte
    RibbonTab.svelte
    RibbonSection.svelte
    ribbon-context.ts
    AppBar.svelte
    StatusBar.svelte
    Inspector.svelte
    InspectorField.svelte
    index.ts
  types.ts                   ← UiIconName
  index.ts                   ← re-export

src/assets/svelte/dashboard/                      ← stays app-side
  graph/EditableGraphDocument.svelte.ts  extends UiWorkspaceDocument
  graph/canvas/EditableCanvas.svelte
  simulation-report/SimulationReportDocument.svelte.ts + SimulationReport.svelte
  optimization-report/OptimizationReportDocument.svelte.ts + …
  comparison-report/ComparisonReportDocument.svelte.ts
  document-catalog/DocumentCatalogDocument.svelte.ts
  graph/GraphDiffDocument.svelte.ts + GraphDiff.svelte
  workspace/
    DashboardWorkspaceModel.svelte.ts   ← domain: graphSummaries/folders/analyses/pickers + GenericWM
    dashboard-registry.ts               ← views: Record<kind, Component> + kinds/create
    build-dashboard-rows.ts             ← buildDashboardRows(docs, folders, summaries) → OutlineRow[] (app-side)
  ribbon/DashboardRibbon.svelte         ← app instance (type-only contract, stays)
  inspector/DashboardInspector.svelte
  contract.ts, contracts.generated.ts, dashboard-api.ts, DashboardModel.svelte.ts

  # After B3 compat leaves:
  dashboard/workspace/WorkspaceDocument.svelte.ts  → re-export from ui-kit
  dashboard/workspace/WorkspaceModel.svelte.ts     → re-export Generic (compat)
  dashboard/workspace/Workspace.svelte             → re-export WorkspaceShell (compat)
```

Build stays `svelte css:"injected"`; kit is SSR-safe (`src/assets/js/server.ts`).
Tests move with components; kit `vitest` uses same `bits-ui` inline + `ResizeObserver` mock
from `src/assets/svelte/test-setup.ts`. Cross-cutting fixes (dead `data-dashboard-theme`,
missing tokens, stylelint path) owned by A1.

**Workspace composition — two rungs (choose A):**

```
Option A (chosen, lazy):                     Option B (heavier generics):
  kit: GenericWorkspaceModel<D>                 kit: WorkspaceModel<D, F, G>
         documents + selection only                  + folders/summaries generics
  app: DashboardWorkspaceModel                   app: every consumer becomes generic
         extends GenericWM + adds                    <D,F,G> everywhere
         graph/folders/analyses                      — heavier, not lazy
         composition wins
```

```
Option A ascii:
  GenericWorkspaceModel<D>  ──► UiWorkspaceDocument
         ▲
         │ extends / wraps
  DashboardWorkspaceModel ──► GraphSummary[], FolderSummary[], AnalysisOption[], pickers …
         │
  Dashboard.svelte ──► generic.documents + app.domain.graphSummaries
```

---

## 5. Phased execution

Sequencing (each phase = one PR, one reviewer). Workspace core promoted to B3 (was B4).

```
A1 ──► A2 ──► A3 ──► A4 ──► B1 ──► B2 ──► B3 ──► B4
 │      │      │      │      │      │      │      │
 tokens  docs   registry  WS  primi  comp.  WORKSPACE  shell
 LOW    MED   HIGH   HIGH   LOW    MED    HIGH     LOW
                 +GenericWM  shell+         ★ kit workspace
                             outline        (core)
```

Must pass per phase: `npm run check` • `npm test` • `mix precommit` • visual `DashboardLive`.
Keep compat re-exports one release, delete next.

---

### A1 — Tokens + Icon / SplitButton / MultiSelectFilter  (prereq, LOW)

**Goal:** make the smallest reusable atoms app-agnostic and fix theming/tokens.

**File tree**

```
Before                              After (in place, no moves yet)
src/assets/css/                     src/assets/css/
  design-tokens.css  --ds-*           design-tokens.css  --ui-* (+ --ds-* alias)
  dashboard.css                      dashboard.css
src/assets/svelte/dashboard/        src/assets/svelte/dashboard/
  types.ts  IconName (19)              types.ts  DomainIconName extends UiIconName
  ui/Icon.svelte  name: IconName       ui/Icon.svelte  name: string
  ui/SplitButton.svelte               ui/SplitButton.svelte  icon?: string
  controls/MultiSelectFilter.svelte    controls/MultiSelectFilter.svelte  (inline SVG)
```

**Code — Icon**

```ts
// BEFORE — dashboard/types.ts + ui/Icon.svelte
export type IconName = "search" | "filter" | ... | "shield" | "graph" | "graph-diff" | "simulation-report";
 //              generic ^^^^^^^^^^^^^^^^^^^        domain ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
export let { name }: { name: IconName } = $props();

// AFTER — ui-kit/types.ts (kit) + dashboard/types.ts (app)
 // kit:  export type UiIconName = "search" | "filter" | "chevron-down" | ...; // generic only
 //       <Icon name: string />
 // app:  export type DomainIconName = UiIconName | "shield" | "graph" | "graph-diff" | "simulation-report";
export let { name }: { name: string } = $props();
```

**Code — tokens + theme fix**

```css
/* BEFORE — Dashboard.svelte:117 sets data attribute on div, CSS targets :root → dead */
<div class="dashboard-app" data-dashboard-theme="topology">
:root[data-dashboard-theme="simulation"] { ... }  /* never matches */
:root[data-dashboard-theme="dark"] { ... }

/* AFTER — A1: option A (preferred) — move selectors to .dashboard-app */
.dashboard-app[data-dashboard-theme="simulation"] { ... }
.dashboard-app[data-dashboard-theme="dark"] { ... }
/* also define missing tokens */
:root { --ui-text-xl: 1.25rem; --ui-color-accent-contrast: #fff; /* + --ds-* alias */ }
```

**Code — SplitButton + MultiSelectFilter**

```ts
// BEFORE
export type SplitButtonOption = { icon?: IconName; title: string; id: string };
import Icon from "../ui/Icon.svelte"; <Icon name="filter" />

// AFTER
export type SplitButtonOption = { icon?: string; title: string; id: string };
// MultiSelectFilter: inline SVG, no import
<svg aria-hidden="true" viewBox="0 0 16 16"><path d="M3 5h10l-3 3v3l-2 1v-4z"/></svg>
```

**Dependency**

```
Before:  MultiSelectFilter ──► Icon ──► IconName
         SplitButton ──► IconName
After:   MultiSelectFilter ──► (inline SVG)      Icon ──► string
         SplitButton ──► string
         FilterableTable rows: optionally reuse ui/Checkbox instead of duplicating CSS
```

**Checklist**

- [ ] `--ui-*` primary + `--ds-*` alias, add `--ui-text-xl`, `--ui-color-accent-contrast`
- [ ] theme selectors fixed (`.dashboard-app[data-...]`)
- [ ] `Icon: string`, `SplitButton icon?: string`, `MultiSelectFilter` icon-free
- [ ] update `stylelint-plugin-ds-colors` token path if needed
- [ ] `npm run check` • `npm test` • visual parity (no pixel diff)

---

### A2 — Documents: base enforces polymorphism  (MEDIUM)

**Goal:** enforce shared contract on the base (soon to be `ui-kit/workspace`), remove `as` casts, make `canClose` polymorphic,
and add **report-kind accessors** so the remaining `kind==="simulation-report"` ladders in §3b disappear.
Prepares the kit base without moving files yet.

**File tree**

```
Before                                      After (in place, prepares kit)
workspace/WorkspaceDocument.svelte.ts        workspace/WorkspaceDocument.svelte.ts
  class WorkspaceDocumentBase {}               abstract class WorkspaceDocumentBase {  // will become UiWorkspaceDocument in kit
  // no id/title/icon/kind/canClose              abstract readonly id/title/kind/icon/documentLabel
  type WorkspaceDocument = 6 union               canClose(): boolean; isReportDocument() ...
                                               }
*Document.svelte.ts (6 files)               *Document.svelte.ts  extends base, icon: string
Dashboard.svelte:162  {document as ...}     Dashboard.svelte:162  {document} (narrowed)
DashboardModel.svelte.ts:125  manual find   DashboardModel.svelte.ts  findReport() unified
WorkspaceModel.svelte.ts:351  switch(kind)  WorkspaceModel.svelte.ts  d.canClose()
```

**Code — base**

```ts
// BEFORE — src/assets/svelte/dashboard/workspace/WorkspaceDocument.svelte.ts:10
export class WorkspaceDocumentBase {
  isReportDocument(): boolean { return false; }
  isAsyncReportDocument(): this is AsyncReportDocument<ReportKind> { return false; }
}

// AFTER — will move to src/assets/svelte/ui-kit/workspace/WorkspaceDocument.svelte.ts in B3
export abstract class UiWorkspaceDocument {
  abstract readonly id: string;
  abstract readonly kind: string;
  abstract readonly title: string;
  abstract readonly icon: string;
  abstract readonly documentLabel: string;
  canClose(): boolean { return true; }
  isReportDocument(): boolean { return false; }
  isAsyncReportDocument(): this is UiAsyncReportDocument<ReportKind> { return false; }
}
// compat: export type WorkspaceDocumentBase = UiWorkspaceDocument;
```

**Code — concrete docs (now includes §3b HIGH: report accessors)**

```ts
// BEFORE — EditableGraphDocument.svelte.ts:46  etc.
readonly icon = "graph" as const satisfies IconName;

// AFTER
import type { UiWorkspaceDocument } from "../../ui-kit/workspace/WorkspaceDocument.svelte"; // after B3; in A2 still local
readonly icon = "graph" as const satisfies string; // DomainIconName stays app-side
canClose(): boolean { return true; }

// SimulationReportDocument / OptimizationReportDocument — now also expose report-kind accessors (§3b)
abstract get reportId(): string | null;        // kit: UiAsyncReportDocument
abstract get reportApiKind(): "simulation_report" | "optimization_report";
class SimulationReportDocument extends UiAsyncReportDocument<"simulation"> {
  get reportId() { return this.experimentId; }
  get reportApiKind() { return "simulation_report" as const; }
  canClose(): boolean { return this.status === "loaded" || this.status === "error"; }
}
class OptimizationReportDocument extends UiAsyncReportDocument<"optimization"> {
  get reportId() { return this.optimizationId; }
  get reportApiKind() { return "optimization_report" as const; }
  canClose(): boolean { return this.status === "loaded" || this.status === "error"; }
}
```

**Code — call sites**

```ts
// BEFORE — Dashboard.svelte:162 + DashboardModel.svelte.ts:125 + WorkspaceModel.svelte.ts:351
{#if document.kind === "graph"} <EditableCanvas document={document as EditableGraphDocument} /> {/if}
const r = documents.find(d => d.kind==="simulation-report" && ...) as SimulationReportDocument;
canCloseDocument(d) { return (d.kind!=="simulation-report" && ...) || d.status==="loaded"||"error"; }

// AFTER — A2 still uses #if ladder, but without casts; registry replaces ladder in A3/B3
{#if document.kind === "graph"} <EditableCanvas {document} /> {/if}  // narrowed, no cast
const r = findReport(id, "simulation"); // unified polymorphic
canCloseDocument(d: UiWorkspaceDocument) { return d.canClose(); }
```

**Dependency**

```
Before:  Dashboard.svelte ──► 6 concrete docs (casts)
         WorkspaceModel ──► canClose switch(kind)
After:   Dashboard.svelte ──► UiWorkspaceDocument (narrowed, #if stays until registry)
         WorkspaceModel ──► document.canClose()
         6 docs ──► UiWorkspaceDocument (enforced)
```

**Checklist**

- [ ] base enforces `id/kind/title/icon/documentLabel/canClose` + `reportId/reportApiKind` on `UiAsyncReportDocument`
- [ ] 6 docs extend base, `icon: string`, `ComparisonReportDocument` aligned, report docs expose `reportId/reportApiKind`
- [ ] zero `as EditableGraphDocument` etc. in `Dashboard.svelte:162`
- [ ] `DashboardModel` unified to `isAsyncReportDocument()+findReport:166`
- [ ] `WorkspaceModel.canCloseDocument:351` delegates to `canClose()`; `WorkspaceModel.setReportAnalysis:231` + `ReportInspector.svelte:16` use `report.reportId/reportApiKind` (no `kind` ternary)
- [ ] audit: grep `kind === "simulation-report"` — only remaining occurrences are `reportId/reportApiKind` impls + tests

---

### A3 — Registry + GenericWorkspaceModel shim  (HIGH, additive only)

**Goal:** introduce registry (eliminates `#if` ladder + Document↔View cycle), collapse the remaining
document/catalog ladders from §3b (`handleCreateDocument:873`, `openCatalogItem:568`, `DashboardInspector:72`
via `inspectorFor`), and make `WorkspaceModel` injectable so workspace can move to
`ui-kit/workspace/` in B3. No concrete import removal yet — compat overload keeps old call sites green.
Strategy axis (§3b MEDIUM) is out of scope here — noted as `C1` follow-up.

**File tree**

```
Before                                      After (additive)
workspace/WorkspaceModel.svelte.ts           workspace/WorkspaceModel.svelte.ts
  import { EditableGraphDocument } ...         // same imports kept
  type OptimizationParamsChange = ...          // moved to contract.ts
  class WorkspaceModel {                       // compat shim:
    constructor(summaries, folders)              class WorkspaceModel extends GenericWorkspaceModel<WorkspaceDocument> {
                                                // forwards to GenericWorkspaceModel
                                              }
Dashboard.svelte:25  import {arrangeNetwork}  Dashboard.svelte  no longer imports arrangeNetwork
dashboard/contract.ts                          dashboard/contract.ts  + OptimizationParamsChange
                                             // NEW — workspace-registry.ts (or ui-kit shim ahead of B3)
                                             dashboard/workspace/workspace-registry.ts
                                               export type DocumentRegistry<D> { views, kinds, create }
                                             dashboard/workspace/build-dashboard-rows.ts (stub)
                                             src/assets/svelte/dashboard/workspace/dashboard-registry.ts
                                               export const dashboardRegistry: DocumentRegistry<WorkspaceDocument> = { views: { graph: EditableCanvas, … } }
                                             // NEW — ui-kit shim ahead of B3 (or dashboard-side first)
                                             src/assets/svelte/ui-kit/workspace/  (created, types only)
                                               WorkspaceModel.svelte.ts  GenericWorkspaceModel<D>
                                               WorkspaceDocument.svelte.ts  UiWorkspaceDocument (re-export until B3)
```

**Code — contract + registry**

```ts
// BEFORE — WorkspaceModel.svelte.ts:29
export type OptimizationParamsChange = Omit<Partial<OptimizationParams>, "simulation_params">
  & { simulation_params?: Partial<SimulationParams> };

// AFTER — dashboard/contract.ts
export type OptimizationParamsChange = Omit<Partial<OptimizationParams>, "simulation_params">
  & { simulation_params?: Partial<SimulationParams> };

// NEW — ui-kit/workspace/workspace-registry.ts (kit, contract-free)
import type { Component, Snippet } from "svelte";
import type { UiWorkspaceDocument } from "./WorkspaceDocument.svelte";
import type { DashboardApi } from "../../dashboard/dashboard-api"; // ← stays app-side; kit uses generic Api param
// kit version is generic over Api:
export interface DocumentRegistry<D extends UiWorkspaceDocument, Api = unknown> {
  readonly views: Record<string, Component<{ document: D; api: Api }>>;
  readonly kinds: Record<string, { label: string; icon: string; create: () => D }>;
  create(kind: string): D;
  snippetFor?(doc: D): Snippet<[D]>; // optional snippet variant
}

// App instance — dashboard/workspace/dashboard-registry.ts
import EditableCanvas from "../graph/canvas/EditableCanvas.svelte";
import SimulationReport from "../simulation-report/SimulationReport.svelte";
// …
export const dashboardRegistry: DocumentRegistry<WorkspaceDocument, DashboardApi> = {
  views: {
    graph: EditableCanvas as Component<{document: WorkspaceDocument; api: DashboardApi}>,
    "graph-diff": GraphDiff,
    "simulation-report": SimulationReport,
    "optimization-report": OptimizationReport,
    "comparison-report": ComparisonReport,
    "document-catalog": DocumentCatalog,
  },
  kinds: {
    graph: { label: "Graph", icon: "graph", create: () => new EditableGraphDocument() },
    "document-catalog": { label: "Documents", icon: "squares-2x2", create: () => new DocumentCatalogDocument() },
  },
  create(kind) { return this.kinds[kind]!.create(); },
};
```

**Code — GenericWorkspaceModel (Option A, chosen)**

```ts
// NEW — src/assets/svelte/ui-kit/workspace/WorkspaceModel.svelte.ts  (kit, generic, no domain imports)
import type { UiWorkspaceDocument } from "./WorkspaceDocument.svelte";

export class GenericWorkspaceModel<D extends UiWorkspaceDocument> {
  documents = $state<D[]>([]);
  selectedDocumentId = $state<string | undefined>();
  // — only generic chrome state + behavior

  get activeDocument(): D | undefined { return this.documents.find(d => d.id === this.selectedDocumentId); }
  get hasUnreadReport(): boolean { return this.documents.some(d => d.isReportDocument() && (d as any).hasUnread); }
  canCloseDocument(d: D): boolean { return d.canClose(); }
  selectDocument(id: string) { this.selectedDocumentId = id; }
  reorderDocuments(a: string, b: string) { /* generic reorder */ }
  closeDocument(id: string) { if (!this.canCloseDocument(this.documents.find(d=>d.id===id)!)) return; /* … */ }
  // NO graphSummaries, folders, analysisOptions, pickers — those live in app wrapper
}

// App wrapper — composition
// dashboard/workspace/DashboardWorkspaceModel.svelte.ts
import { GenericWorkspaceModel } from "../../ui-kit/workspace/WorkspaceModel.svelte";
import type { WorkspaceDocument } from "./WorkspaceDocument.svelte";
export class DashboardWorkspaceModel extends GenericWorkspaceModel<WorkspaceDocument> {
  graphSummaries = $state<GraphSummary[]>([]);
  folders = $state<FolderSummary[]>([]);
  // domain methods: openLoadedGraph, createPendingReport, ensureInitialFoothold …
  // delegates generic ops to super
}
```

**Code — arrangeNetwork + #if ladder → registry + remaining §3b ladders**

```ts
// BEFORE — Dashboard.svelte:25,67
import { arrangeNetwork } from "./dashboard/graph/network/NetworkCanvasLayout";
function arrangeDocumentNetwork(doc: EditableGraphDocument) { doc.graph = arrangeNetwork(doc.graph); }

// AFTER — EditableGraphDocument.svelte.ts
arrangeNetwork(): void { this.graph = arrangeNetwork(this.graph); } // method on document
// GenericWorkspaceModel
arrangeActiveNetwork(): void { (this.activeDocument as any)?.arrangeNetwork?.(); }
// Dashboard.svelte: no graph/network import

// BEFORE — Dashboard.svelte:162 ladder
{#snippet content(document: WorkspaceDocument)}
  {#if document.kind === "graph"} <EditableCanvas {document as EditableGraphDocument} />
  {:else if …} …
  {/if}
{/snippet}

// AFTER — A3 onward (both A3 and B3)
{#snippet content(document: UiWorkspaceDocument)}
  {@const View = dashboardRegistry.views[document.kind]}
  <View {document} {api} />
{/snippet}
// Svelte 5 runes: <View> where View is a variable is valid; <svelte:component> is legacy (svelte/legacy-svelte-component).

// BEFORE — WorkspaceModel.handleCreateDocument:873 + openCatalogItem:568
if (typeId === "graph") this.topologyPickerOpen = true; else if (typeId === "document-catalog") this.openDocumentCatalog();
if (item.kind === "graph") return this.openGraphRevision(api, item.graph_revision_id);
if (item.kind === "simulation_report") return this.openHistoricalSimulationReport(api, item);
// AFTER — registry-driven (A3)
dashboardRegistry.create(typeId); // kinds[typeId].create()
catalogRegistry.open(item, api);  // map kind → handler, no if chain

// BEFORE — DashboardInspector.svelte:72 (4-branch) + dead registry.inspectorFor
{#if selection?.kind === "graph"} <GraphInspector …/>
{:else if selectable.type === "MissionCapability"} <MissionCapabilityInspector …/>
{:else if selectable} <EditableSelectionInspector …/>
{:else if isReport} <ReportInspector …/>{/if}
// AFTER — registry.inspectorFor wired (A3, graph/presentation/registry.ts already exists)
// MissionCapability kept as one extra branch before registry, or registered as its own entry
import { inspectorFor } from "../graph/presentation/registry";
const KnownInspector = selection?.selectable ? inspectorFor(selection.selectable.type) : null;
{#if KnownInspector} <KnownInspector {selection} {api} /> {:else if selection?.selectable} <EditableSelectionInspector …/> {/if}
```

*Note on `createPending*:694/728` dedupe:* collapse to `createPendingAsyncReport<Kind>` only if `budget/strategy` align;
otherwise **leave as two methods** — low value, do not block A3.

**Dependency**

```
Before:  WorkspaceModel ──► 6 docs (hard) ──► contract
         Dashboard.svelte ──► graph/network/NetworkCanvasLayout
         Dashboard.svelte ──► 6 Views via #if ladder + casts
         DashboardRibbon ──► WorkspaceModel (for OptimizationParamsChange type)
After:   GenericWorkspaceModel<D> ──► UiWorkspaceDocument (interface, no concretes)
         DashboardWorkspaceModel (app) ──► GenericWM + 6 docs + GraphSummary/FolderSummary
         registry ──► docs + views (outside classes, no Document↔View cycle)
         contract ──► OptimizationParamsChange (DashboardRibbon imports from contract)
         EditableGraphDocument ──► arrangeNetwork (shell no longer does)
         Dashboard.svelte ──► registry[document.kind] (no ladder)
```

**Checklist**

- [ ] `OptimizationParamsChange` in `contract.ts`, ribbon no longer imports `WorkspaceModel`
- [ ] `arrangeNetwork` moved off shell onto document
- [ ] `DocumentRegistry<D>` + `GenericWorkspaceModel<D>` + `UiWorkspaceDocument` introduced, `Dashboard.svelte` uses `registry`
- [ ] compat: old `new WorkspaceModel(summaries, folders)` still compiles via shim subclass / overload
- [ ] `#if` ladder deleted, no `as` casts remain
- [ ] §3b HIGH: `handleCreateDocument:873` → `registry.create`, `openCatalogItem:568` → catalog registry, `DashboardInspector:72` wired to `inspectorFor` (dead code revived)
- [ ] `createPending*` dedupe only if budgets align — otherwise keep two methods
- [ ] strategy axis (§3b MEDIUM) explicitly **not** in this PR — flagged as `C1`

---

### A4 — Workspace chrome + DocumentOutline decoupling  (MEDIUM)

**Goal:** decouple outline tree logic + fix inspector slot ownership. **No longer prop-driven** — `WorkspaceModel`
moves to `ui-kit/workspace/` in A3/B3 as `GenericWorkspaceModel<D>`, so `Workspace.svelte` keeps
`model: GenericWorkspaceModel<D>` (intra-kit prop). The granular `documents/onSelect/onClose/...` split
previously planned for A4 is unnecessary; both live in the kit. A4 now does only what still matters
before `B3` extraction. Also makes the outline builder **algorithm-generic** (see §3d) so B3's
`ui-kit/workspace/DocumentOutline` is contract-free and `OutlineRow` no longer carries `WorkspaceDocument`.

**File tree**

```
Before                                      After (in place, prepares kit)
workspace/Workspace.svelte                   workspace/Workspace.svelte  (still model: GenericWorkspaceModel<D>)
  props: model: WorkspaceModel                 props: model: GenericWorkspaceModel<UiWorkspaceDocument>
  reads model.documents/folders/...            reads model.documents/selectedDocumentId/documentTypes
  calls model.close/select/reorder             calls model.close/select/reorder (same — model is now kit type)
  embeds DocumentOutline with                   embeds DocumentOutline via OutlineRow[] (already normalized)
    folders/graphSummaries directly            // outline no longer receives FolderSummary/GraphSummary
  owns inspector grid slot                      // inspector slot moved to parent:
    grid: inspector at grid-column:2           // Dashboard.svelte grid composes <Workspace> + <Inspector> side-by-side
workspace/DocumentOutline.svelte              workspace/DocumentOutline.svelte  (pure shell: rows + rowSnippet)
  buildRows / parentDocument inline             workspace/document-outline.ts  (app helpers: parentDocument helpers stay)
                                               workspace/outline.ts  (kit-generic assembler, NEW in B3 stub here)
                                               workspace/build-dashboard-rows.ts → normalized OutlineNode → OutlineRow
dashboard/ui/OptionPickerDialog.svelte        // ui→controls dep resolved: inline FilterableTableColumn or note for B2
inspector/inspector-registry.ts               inspector/inspector-registry.ts  (app stub for §3c TODO)
```

**Code — Workspace.svelte stays model-driven (now kit-compatible)**

```svelte
<!-- BEFORE — dashboard/workspace/Workspace.svelte:13 -->
<script>
  import type { WorkspaceModel } from "./WorkspaceModel.svelte"; // app type
  let { model, inspector, content }: { model: WorkspaceModel; inspector?: Snippet; content?: Snippet<[WorkspaceDocument]> } = $props();
</script>
<Tabs.Root value={model.selectedDocumentId} onValueChange={model.selectDocument}>
  {#each model.documents as doc} <Tabs.Trigger value={doc.id}>{doc.title}</Tabs.Trigger> {/each}
</Tabs.Root>
<DocumentOutline documents={model.documents} folders={model.folders} graphSummaries={model.graphSummaries} ... />
{@render inspector?.()} <!-- owns inspector slot at grid-column:2 -->

<!-- AFTER — A4 in place (model is now kit type after A3), B3 moves verbatim to ui-kit/workspace/WorkspaceShell.svelte -->
<script>
  import type { GenericWorkspaceModel } from "./WorkspaceModel.svelte"; // after A3: kit/workspace/WorkspaceModel.svelte re-export
  import type { UiWorkspaceDocument } from "./WorkspaceDocument.svelte";
  import type { OutlineRow } from "./document-outline";
  let { model, outlineRows, outlineRowSnippet, inspector, content }: {
    model: GenericWorkspaceModel<UiWorkspaceDocument>;
    outlineRows: OutlineRow[]; outlineRowSnippet?: import("svelte").Snippet<[OutlineRow]>;
    inspector?: Snippet; content?: Snippet<[UiWorkspaceDocument]>;
  } = $props();
</script>
<!-- DocumentOutline now generic: rows + snippet, no FolderSummary in kit -->
<DocumentOutline rows={outlineRows} rowSnippet={outlineRowSnippet} onSelectDocument={model.selectDocument} />
<Tabs.Root value={model.selectedDocumentId} onValueChange={model.selectDocument}>
  {#each model.documents as doc} <Tabs.Trigger value={doc.id}>{doc.title}</Tabs.Trigger> {/each}
</Tabs.Root>
<!-- inspector NOT rendered at grid-column:2 — Dashboard.svelte composes <Workspace> + <Inspector> side-by-side -->
```

Computed in the parent (app) — `outlineRows` stays app-side:

```ts
// dashboard/workspace/build-dashboard-rows.ts (app impl, NEW in A4)
import type { OutlineRow } from "../../ui-kit/workspace/DocumentOutline.svelte"; // kit type after B3; app-local type in A4
import type { UiWorkspaceDocument } from "./WorkspaceDocument.svelte";
export function buildDashboardRows(
  documents: UiWorkspaceDocument[], folders: FolderSummary[], summaries: GraphSummary[]
): OutlineRow[] { /* folder grouping + revision nesting + report grouping — app-specific */ return rows; }

// Dashboard.svelte
import { buildDashboardRows } from "./dashboard/workspace/build-dashboard-rows";
const outlineRows = $derived(buildDashboardRows(wm.documents, wm.folders, wm.graphSummaries));
// <Workspace {model} {outlineRows} outlineRowSnippet={dashboardRowSnippet} inspector={...} content={registrySnippet} />
```

**Diagram — A4 vs B3 outline flow:**

```
A4 — helpers extracted, still domain-aware          B3 — kit assembler, app adapter normalized
──────────────────────────────                     ──────────────────────────────
documents ──┐                                      documents ─┐
folders   ──┼─► document-outline.ts (helpers)      folders  ─┼─► buildDashboardNodes() ─► OutlineNode[]
summaries ──┘   buildRows(docs,folders,summaries)  summaries─┘   (app, reuses helpers verbatim)
                │ OutlineRow{ document }           buildDashboardGroups(folders) ─► OutlineGroup[]
                ▼                                                         │
        DocumentOutline(documents,folders,…)                 buildOutline(nodes, groups) ─► OutlineRow[]
                                                             │  kit/workspace/outline.ts — no WorkspaceDocument
                                                             │  Map/Set, bucket→children→section, cycle guard
                                                             ▼
                                                     DocumentOutline(rows, rowSnippet)
                                                     │  kit shell: depth indent, ariaLabel, dragData
                                                     └─► rowSnippet renders folder delete/move
```

**Code — Outline builder generic (kit) vs app adapter (§3d, Option B):**

```ts
// BEFORE — DocumentOutline.svelte inline, coupled to FolderSummary + GraphSummary + WorkspaceDocument
function buildRows(documents, folders, summaries) { /* folder grouping + revision nesting + report grouping */ }
function parentDocument(doc) { /* walk parent_revision_id chain with cycle guard */ }

// AFTER — A4: extract helpers + introduce normalized nodes (app-side first, then kit generic)
// workspace/document-outline.ts  (app helpers stay: parentDocument, folderIdForDocument, etc.)
export function parentDocument(doc, graphsByRevisionId): WorkspaceDocument|undefined { /* unchanged */ }
export function folderIdForDocument(doc, summaries): string|null|undefined { /* unchanged */ }

// workspace/build-dashboard-rows.ts  (app adapter: domain → normalized)
// Converts existing helpers into plain data so kit has zero contract imports.
export interface OutlineNode {
  id: string; label: string; icon: string; kind: string;
  groupId: string;            // folder id, "analyses", or "root"
  parentId?: string;          // revision nesting within same group
  section?: { key: string; title: string }; // "reports" or analysis grouping
  ariaLabel?: string; dragData?: string;    // passes through to row
}
export function buildDashboardNodes(docs, folders, summaries): OutlineNode[] { /* uses parentDocument etc. */ }
export function buildDashboardGroups(folders, hasAnalyses): OutlineGroup[] { /* folders → groups */ }
export function buildDashboardRows(docs, folders, summaries): OutlineRow[] {
  return buildOutline(buildDashboardNodes(…), buildDashboardGroups(…)); // kit assembler (available after B3 stub)
}

// Kit generic outline — B3: ui-kit/workspace/outline.ts (pure, no app imports)
export interface OutlineGroup { id: string; label: string; icon?: string; depth?: number }
export type OutlineRow =
  | { type: "item"; id: string; label: string; icon: string; kind: string; depth: number; ariaLabel?: string; dragData?: string }
  | { type: "header"; id: string; label: string; icon?: string; kind: "folder"|"section"|"group" };
export function buildOutline(nodes: readonly OutlineNode[], groups: readonly OutlineGroup[]): OutlineRow[] { /* walk parentId, groupId, section, cycle guard */ }

// Kit shell — B3: ui-kit/workspace/DocumentOutline.svelte (pure shell, no business logic)
// Props: rows: OutlineRow[]  +  rowSnippet?: Snippet<[OutlineRow]>  (svelte/snippet)
<script lang="ts">
  import type { Snippet } from "svelte";
  import type { OutlineRow } from "./outline";
  let { rows, rowSnippet, selectedId, onSelect, collapsed, onCollapsedChange }:
    { rows: OutlineRow[]; rowSnippet?: Snippet<[OutlineRow]>; selectedId?: string; onSelect: (id:string)=>void; collapsed:boolean; onCollapsedChange:(c:boolean)=>void } = $props();
</script>
{#each rows as row (row.id)}
  {#if rowSnippet}{@render rowSnippet(row)}{:else}<button onclick={()=>onSelect(row.id)}>{row.label}</button>{/if}
{/each}
// Default kit row honours ariaLabel/depth/draggable dragData. App snippet renders folder delete/move chrome.
```

**Before / after — DocumentOutline props + Template coupling:**

```svelte
<!-- BEFORE — today after A4 stub (still domain objects in rows) -->
{#each rows as row (rowKey(row))}
  {#if row.type === "folder"}          <span>{row.folder.name}</span>
  {:else}                               <button>{row.document.title}</button>
    <!-- reads row.document.icon / label / folder.name — domain in kit -->
  {/if}
{/each}

<!-- AFTER — B3 (kit: plain rows, app snippet owns domain chrome) -->
{#each rows as row (row.id)}           <!-- row.id already unique: item: / group: / section: -->
  {#if row.type === "header"}           <span>{row.label}</span>   <!-- kit default -->
  {:else}                               <button aria-label={row.ariaLabel}
                                          style:--depth={row.depth}
                                          draggable={row.dragData ? true : undefined}>
                                          {row.label}            <!-- icon via row.icon -->
                                        </button>
  {/if}
  {#if rowSnippet} {@render rowSnippet(row)} {/if}  <!-- app snippet adds delete/move menu -->
{/each}

<!-- Dashboard.svelte / Workspace.svelte wiring -->
<script>
  import { buildDashboardRows } from "./workspace/build-dashboard-rows";
  const rows = $derived(buildDashboardRows(model.documents, model.folders, model.graphSummaries));
</script>
<DocumentOutline {rows} selectedId={model.selectedDocumentId} onSelect={(id)=>model.selectDocument(id)} />
```

**Dependency**

```
Before:  Workspace.svelte ──► WorkspaceModel (app, 920 lines, domain) ──► 6 docs + FolderSummary/GraphSummary
         Workspace.svelte owns .dashboard-inspector grid slot (grid-column:2)
         DocumentOutline.svelte ──► buildRows inline (untested, domain types)
After:   Workspace.svelte ──► GenericWorkspaceModel<D> (kit, documents only)  — intra-kit, no split needed
         Workspace.svelte ──► outlineRows: OutlineRow[] (app builds, kit renders)
         Dashboard.svelte ──► Workspace (kit) + Inspector (kit/layout) at parent grid — slot fixed
         DocumentOutline (kit) ──► OutlineRow[] + rowSnippet  (no domain types)
         buildDashboardRows (app) ──► FolderSummary/GraphSummary → OutlineRow[]
         document-outline.ts (pure) ◄── DocumentOutline.svelte (shell)
         // No granular documents/onSelect/onClose split — model prop stays, because both live in kit
```

**Checklist**

- [ ] `Workspace.svelte` keeps `model: GenericWorkspaceModel<D>` (intra-kit, no prop explosion); type now resolves to `ui-kit/workspace`
- [ ] `DocumentOutline` no longer receives `folders/graphSummaries` — receives `rows: OutlineRow[] + rowSnippet` (generic kit contract, `OutlineRow` no longer carries `WorkspaceDocument`)
- [ ] `build-dashboard-rows.ts` adapter uses `buildDashboardNodes` + `buildDashboardGroups` → `buildOutline` (kit純粋 assembler, §3d Option B); `document-outline.ts` keeps only domain helpers (parentDocument etc.), not `buildRows`
- [ ] inspector slot moved: `Workspace.svelte` no longer renders inspector at `grid-column:2`; `Dashboard.svelte:246` parent grid composes `<Workspace>` + `<Inspector>` side-by-side
- [ ] `OptionPickerDialog` ui→controls dep resolved for B2
- [ ] optional: Ribbon button media queries moved `Ribbon.svelte` → `RibbonButton.svelte`

---

### Stage B — Extract in chunks (each PR: move verbatim, barrel, compat re-exports)

Prereq (if barrel forces alias): add once in `src/assets/vite.config.mjs`, `src/vitest.config.ts`
(fix divergent `@` roots), `src/assets/tsconfig.json` `paths`; prefer relative imports.
Build stays `svelte css:"injected"`; kit SSR-safe; kit `vitest` reuses `bits-ui` inline + `ResizeObserver` mock.

---

### B1 — Primitives + tokens  (~12 files, no behavior change)

**File tree**

```
Before (after A)                            After
src/assets/css/design-tokens.css             src/assets/svelte/ui-kit/styles/tokens.css  (--ui-* + --ds-* alias)
src/assets/css/dashboard.css                 src/assets/svelte/ui-kit/styles/variants.css
src/assets/svelte/dashboard/ui/              src/assets/svelte/ui-kit/primitives/
  Icon.svelte                                  Icon.svelte
  Checkbox.svelte                              Checkbox.svelte
  Slider.svelte                                Slider.svelte
  Select.svelte                                Select.svelte
  NumberInput.svelte                           NumberInput.svelte
  RibbonButton.svelte                          RibbonButton.svelte
  SplitButton.svelte                           SplitButton.svelte
                                               index.ts  ← barrel
                                             src/assets/svelte/dashboard/ui/  ← compat re-exports
                                               export { default as Icon } from "../../ui-kit/primitives/Icon.svelte";
```

**Code — barrel**

```ts
// src/assets/svelte/ui-kit/primitives/index.ts
export { default as Icon } from "./Icon.svelte";
export { default as Checkbox } from "./Checkbox.svelte";
export { default as Slider } from "./Slider.svelte";
export { default as Select } from "./Select.svelte";
export { default as NumberInput } from "./NumberInput.svelte";
export { default as RibbonButton } from "./RibbonButton.svelte";
export { default as SplitButton } from "./SplitButton.svelte";
export type { SplitButtonOption } from "./SplitButton.svelte";

// dashboard/ui/Icon.svelte (compat, one release)
export { default } from "../../ui-kit/primitives/Icon.svelte";
```

**Checklist**

- [ ] `ui-kit/styles/tokens.css` shipped, `app.css` imports from new path (or both)
- [ ] primitives moved verbatim, tests moved with them
- [ ] compat re-exports kept, `npm run check` green, `lint:color` green

---

### B2 — Composites  (resolves ui↔controls cycle, one package)

**File tree**

```
Before                                      After
dashboard/controls/                          src/assets/svelte/ui-kit/composites/
  FilterableTable.svelte                       FilterableTable.svelte
  FilterableTable.types.ts                     FilterableTable.types.ts
  MultiSelectFilter.svelte                     MultiSelectFilter.svelte
dashboard/ui/                                src/assets/svelte/ui-kit/composites/
  OptionPickerDialog.svelte                    OptionPickerDialog.svelte
  OptionPickerDialogContent.svelte             OptionPickerDialogContent.svelte
                                               index.ts
                                             dashboard/controls/*, dashboard/ui/OptionPicker* ← compat re-exports
```

**Code — why together**

```ts
// OptionPickerDialog.svelte imports FilterableTable types — ui → controls cycle
import type { FilterableTableColumn } from "../controls/FilterableTable.types";
// If extracted separately, either package would depend on the other.
// B2 moves ui+controls together as one composites package → no cycle.

// MultiSelectFilter is already icon-free after A1, so controls no longer imports ui.
```

**Checklist**

- [ ] `FilterableTable` generics `Item` preserved, no `contracts.generated.ts` coupling
- [ ] `DocumentCatalog`, `GraphInspector`, `EditableCanvas` instantiate via `ui-kit/composites`

---

### B3 — Workspace core → kit  ★ (only after A3+A4, HIGH — promoted)

**Goal:** move generic workspace chrome to `ui-kit/workspace/` — this is the layout you flagged as kit.
Specific is the 6 concrete doc Views + `dashboardRegistry` + `buildDashboardRows()` which stay app-side.
`Workspace.svelte` moves **verbatim** with its `model: GenericWorkspaceModel<D>` prop (intra-kit) — no granular split.

**File tree**

```
Before (after A4)                           After
dashboard/workspace/                         src/assets/svelte/ui-kit/workspace/
  WorkspaceDocument.svelte.ts  (abstract)     WorkspaceDocument.svelte.ts  ← UiWorkspaceDocument, UiAsyncReportDocument
  WorkspaceModel.svelte.ts  (shim)             WorkspaceModel.svelte.ts   ← GenericWorkspaceModel<D>
  Workspace.svelte  (model: GenericWM)         Workspace.svelte           ← tabs chrome, model: GenericWorkspaceModel<D>, outlineRows + inspector/content
  DocumentOutline.svelte  (shell)              DocumentOutline.svelte    ← generic: rows + rowSnippet
  document-outline.ts  (pure, app)             document-outline.ts      ← generic helpers + OutlineRow types
  workspace-registry.ts / dashboard-            workspace-registry.ts    ← DocumentRegistry<D,Api> types
    registry.ts  (app)                        index.ts
                                              src/assets/svelte/dashboard/workspace/  (app-side, stays)
                                                DashboardWorkspaceModel.svelte.ts  ← domain wrapper (graphSummaries/folders/analyses)
                                                dashboard-registry.ts              ← views: Record<kind, Component> (app instance)
                                                build-dashboard-rows.ts            ← buildDashboardRows() (app impl)
                                                WorkspaceDocument.svelte.ts        ← compat re-export of UiWorkspaceDocument
                                                WorkspaceModel.svelte.ts           ← compat re-export of GenericWorkspaceModel
                                                Workspace.svelte / DocumentOutline ← compat re-exports of kit Workspace/Outline
```

**Code — kit generic vs app specifics**

```ts
// KIT — ui-kit/workspace/WorkspaceDocument.svelte.ts
export abstract class UiWorkspaceDocument {
  abstract readonly id: string; abstract readonly kind: string;
  abstract readonly title: string; abstract readonly icon: string; abstract readonly documentLabel: string;
  canClose(): boolean { return true; }
}

// KIT — ui-kit/workspace/WorkspaceModel.svelte.ts
export class GenericWorkspaceModel<D extends UiWorkspaceDocument> {
  documents = $state<D[]>([]); selectedDocumentId = $state<string|undefined>();
  get activeDocument(): D | undefined { return this.documents.find(d=>d.id===this.selectedDocumentId); }
  canCloseDocument(d: D): boolean { return d.canClose(); }
  // reorder/select/close — generic only
}

// APP — dashboard/workspace/DashboardWorkspaceModel.svelte.ts
import { GenericWorkspaceModel } from "../../ui-kit/workspace/WorkspaceModel.svelte";
import type { UiWorkspaceDocument } from "../../ui-kit/workspace/WorkspaceDocument.svelte";
export class DashboardWorkspaceModel extends GenericWorkspaceModel<UiWorkspaceDocument> {
  graphSummaries = $state<GraphSummary[]>([]); // domain
  folders = $state<FolderSummary[]>([]);
  // openLoadedGraph, createPendingReport, ensureInitialFoothold … — domain methods
}

// KIT — ui-kit/workspace/DocumentOutline.svelte (generic)
<script lang="ts">
  import type { Snippet } from "svelte";
  export type OutlineRow = { id: string; label: string; icon: string; children?: OutlineRow[]; kind: string };
  let { rows, rowSnippet, onSelectDocument }: { rows: OutlineRow[]; rowSnippet?: Snippet<[OutlineRow]>; onSelectDocument: (id:string)=>void } = $props();
</script>
{#each rows as row (row.id)}
  {@render rowSnippet ? rowSnippet(row) : defaultRow(row)}
{/each}

// APP — dashboard/workspace/build-dashboard-rows.ts (domain → generic)
import type { OutlineRow } from "../../ui-kit/workspace/DocumentOutline.svelte";
export function buildDashboardRows(documents: UiWorkspaceDocument[], folders: FolderSummary[], summaries: GraphSummary[]): OutlineRow[] {
  // folder grouping + revision nesting + report grouping — app-specific
  return rows;
}
// Dashboard.svelte wires: const rows = $derived(buildDashboardRows(wm.documents, wm.folders, wm.graphSummaries));
// <DocumentOutline {rows} rowSnippet={dashboardRowSnippet} … />

// KIT — ui-kit/workspace/workspace-registry.ts
export interface DocumentRegistry<D extends UiWorkspaceDocument, Api = unknown> {
  readonly views: Record<string, import("svelte").Component<{ document: D; api: Api }>>;
  readonly kinds: Record<string, { label: string; icon: string; create: () => D }>;
  create(kind: string): D;
}
// APP — dashboard-registry.ts is the concrete instance with 6 views (no cycle: registry owns both)
```

**Code — Dashboard.svelte after (no #if ladder)**

```svelte
<script>
  import { dashboardRegistry } from "./dashboard/workspace/dashboard-registry";
  import Workspace from "../ui-kit/workspace/Workspace.svelte";
  import { buildDashboardRows } from "./dashboard/workspace/build-dashboard-rows";
  const outlineRows = $derived(buildDashboardRows(wm.documents, wm.folders, wm.graphSummaries));
</script>

<Workspace model={wm} {outlineRows} inspector={inspectorSnippet} content={contentSnippet} />

{#snippet contentSnippet(document: UiWorkspaceDocument)}
  {@const View = dashboardRegistry.views[document.kind]}
  <View {document} {api} />
{/snippet}
```

`Dashboard.svelte` still passes `model` — workspace is kit, no prop explosion. `outlineRows` is the only extra input
(the outline's folder/form logic batches with the kit model in `B3` clean).

**Dependency**

```
Before (A4): WorkspaceModel ──► 6 docs + domain (mixed)
             Workspace.svelte ──► WorkspaceModel (still dashboard/, after A3 wraps GenericWM)
             DocumentOutline ──► FolderSummary/GraphSummary (domain)
After:       GenericWorkspaceModel<D> ──► UiWorkspaceDocument (kit, no domain, no contracts)
             DashboardWorkspaceModel (app) ──► GenericWM + 6 docs + FolderSummary/GraphSummary
             Workspace (kit) ──► model: GenericWorkspaceModel<D> + outlineRows + inspector/content (intra-kit)
             DocumentOutline (kit) ──► OutlineRow[] + rowSnippet (no domain)
             buildDashboardRows (app) ──► domain → OutlineRow[]
             dashboardRegistry (app) ──► docs + views (outside classes, no cycle)
```

**Checklist**

- [ ] `UiWorkspaceDocument` + `GenericWorkspaceModel<D>` + `DocumentRegistry` in `ui-kit/workspace/`
- [ ] `Workspace` (model-driven) + generic `DocumentOutline` (+ `OutlineRow` types) in `ui-kit/workspace/` — same `model` prop as before
- [ ] `DashboardWorkspaceModel` (app) wraps generic + adds domain; old `WorkspaceModel` compat re-exports generic
- [ ] `buildDashboardRows()` stays app-side, `DocumentOutline` receives `rows + Snippet` (svelte/snippet)
- [ ] `dashboardRegistry` replaces `#if` ladder in `Dashboard.svelte:162`, no `as` casts, no Document↔View cycle
- [ ] folder/form-picker browsing state moved with kit model (batch with `B3`, no separate A4 split)
- [ ] delete concrete doc imports from kit `GenericWorkspaceModel` (only after registry works)
- [ ] if A3 slips, skip B3 — leave workspace app-side, light polymorphism (A2) suffices

---

### B4 — Shell + Ribbon (generic)  (DashboardRibbon stays app-side, LOW)

**File tree**

```
Before                                      After
dashboard/ribbon/                            src/assets/svelte/ui-kit/layout/
  Ribbon.svelte                                Ribbon.svelte
  RibbonTab.svelte                             RibbonTab.svelte
  RibbonSection.svelte                         RibbonSection.svelte
  ribbon-context.ts                            ribbon-context.ts
  DashboardRibbon.svelte  (stays)              // stays in dashboard/ribbon/
dashboard/shell/                             src/assets/svelte/ui-kit/layout/
  AppBar.svelte                                AppBar.svelte
  StatusBar.svelte                             StatusBar.svelte
dashboard/inspector/                         src/assets/svelte/ui-kit/layout/
  Inspector.svelte                             Inspector.svelte
  InspectorField.svelte                        InspectorField.svelte
                                               index.ts
```

**Code — DashboardRibbon stays**

```svelte
<!-- DashboardRibbon.svelte stays app-side: app instance, type-only contract -->
<script>
  import { Ribbon } from "../../ui-kit/layout";
  import type { OptimizationParams, SimulationParams } from "../contract"; // type-only, fine
  // no longer imports WorkspaceModel — OptimizationParamsChange now from contract (A3)
</script>
<Ribbon><Ribbon.Tab title="Home">...<Slider/> <Checkbox/> ...</Ribbon.Tab></Ribbon>
```

**Checklist**

- [ ] ribbon `Tabs` context still internal to `ui-kit/layout`
- [ ] `AppBar`/`StatusBar` `grid-area` contracts preserved
- [ ] `DashboardRibbon` remains app-side (specific), generic `Ribbon` is kit

---

## 6. Risks & mitigations

```
Risk: 753 token usages + --ds-*→--ui-* touches 45 files
Mitigate: compat aliases (--ui-* primary, --ds-* alias one release) + codemod var(--ds- → var(--ui-

Risk: WorkspaceModel 920 lines + 6 doc imports (gnarliest coupling) — now split kit/app
Mitigate: GenericWorkspaceModel<D> (kit, documents only) + DashboardWorkspaceModel (app, domain)
          via composition (Option A). Additive shim in A3 before delete; B3 last.

Risk: DocumentOutline today couples to FolderSummary/GraphSummary
Mitigate: kit Outline takes OutlineRow[] + Snippet; app buildDashboardRows() maps domain → generic rows

Risk: Dashboard.svelte:117 theme dead code ships dead variants into kit
Mitigate: fix in A1 (.dashboard-app[data-...])

Risk: tests co-located *.test.ts move with components
Mitigate: update src/vitest.config.ts include glob + @ alias for ui-kit

Risk: Document↔View cycle if View stored inside class
Mitigate: registry owns View; Document never imports .svelte

Risk: DashboardInspector hand-rolled ladder hides dead registry code
Mitigate: wire inspectorFor in A3 (revives existing per-type inspectors); keep MissionCapability as one extra branch

Risk: strategy axis scope creep (OptimizationReport panels, DashboardRibbon strategy settings)
Mitigate: explicitly out-of-scope (C1 follow-up); A2/A3 touch only document-kind ladders

Risk: createPendingReport dedupe looks easy but budgets differ
Mitigate: defer unless OptimizationParams.budget unified; keep two methods
```

- A1 lowest risk / highest unblock; workspace core is now B3 (requires A3+A4); defer B3 if A3 slips — primitives/composites/shell still shippable.

---

## 7. Definition of done per phase

- [ ] `svelte-check` zero errors
- [ ] `vitest run assets/svelte/dashboard` green, relocated `ui-kit` tests green
- [ ] `mix precommit` green
- [ ] `DashboardLive` visual parity (no pixel diff)
- [ ] compat re-exports present (delete next release)
- [ ] plan updated

Sequencing (workspace is kit):

```
A1 ──► A2 ──► A3 ──► A4 ──► B1 ──► B2 ──► B3 ──► B4
tokens  docs  registry WS   primi  comp.  WORKSPACE  shell
 LOW   MED   HIGH   HIGH   LOW    MED    HIGH     LOW
                          +GenericWM     ★ ui-kit/workspace
```
