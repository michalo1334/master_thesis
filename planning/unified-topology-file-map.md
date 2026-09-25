# Unified Topology File Map

Qwen38 explored the repository and produced this map. The map describes scope. It does not approve unresolved interface changes.

Labels:

- **Required**: The approved design requires this change.
- **Conditional**: The behavior is required, but the file or interface needs a decision.

## Current state

The implementation has not started.

- The Elixir `TopologyProjection` module does not exist.
- The browser derives network meaning in `NetworkCanvasProjection.ts` and `ownership.ts`.
- `DashboardLive` serves the saved-only `fetch_graph_projection` event.
- `GraphContract.to_domain/2` does not exist.
- `Graph.hydrate/4` already supports `validate_membership: false`.

## Add

### Elixir projector and contracts

| File | Change | Status |
|---|---|---|
| `src/lib/network_defense/graph/topology_projection.ex` | Add `NetworkDefense.Graph.TopologyProjection.project/1`. Derive membership, anchors, policy groups, flow groups, counts, order, and placement issues. Use `MaterializeReachability.operational_flows/1`. | Required |
| `src/lib/network_defense_web/contracts/dashboard/graph/topology_projection.ex` | Add the root projection contract. | Required |
| `src/lib/network_defense_web/contracts/dashboard/graph/topology_projection_segment.ex` | Add segment membership and count fields. | Required |
| `src/lib/network_defense_web/contracts/dashboard/graph/topology_projection_host.ex` | Add segment membership, service IDs, and counts. | Required |
| `src/lib/network_defense_web/contracts/dashboard/graph/topology_projection_service.ex` | Add host membership. | Required |
| `src/lib/network_defense_web/contracts/dashboard/graph/topology_projection_attachment.ex` | Add attached-context data. | Required |
| `src/lib/network_defense_web/contracts/dashboard/graph/topology_projection_anchor.ex` | Add node, edge, and relationship anchor data. | Required |
| `src/lib/network_defense_web/contracts/dashboard/graph/topology_projection_policy_group.ex` | Add grouped segment-policy edges. | Required |
| `src/lib/network_defense_web/contracts/dashboard/graph/topology_projection_flow_group.ex` | Add grouped operational flows. | Required |
| `src/lib/network_defense_web/contracts/dashboard/graph/topology_projection_issue.ex` | Add typed placement issues. | Required |
| `src/lib/network_defense_web/contracts/dashboard/graph/project_topology_draft_payload.ex` | Add `document_id`, `semantic_version`, and the full graph. | Required |
| `src/lib/network_defense_web/contracts/dashboard/graph/project_topology_draft_reply.ex` | Add status, request identity, projection, and validation errors. | Required |

### Browser model and view

The exact split is not fixed. Keep these names unless implementation finds a smaller split.

| File | Change | Status |
|---|---|---|
| `src/assets/svelte/dashboard/graph/topology-projection-model.svelte.ts` | Own request versions, semantic fingerprints, pending state, accepted projection, stale-response rejection, and save conflicts. | Required behavior; conditional name |
| `src/assets/svelte/dashboard/graph/topology-scene.ts` | Join projection IDs to graph entities. Produce segment, attachment, policy, flow, and Unplaced scene data. Do not inspect raw edges for network meaning. | Required behavior; conditional name |
| `src/assets/svelte/dashboard/graph/unified/TopologyCanvas.svelte` | Render the single modeless canvas. Own geometry, semantic zoom, focus lenses, pins, drag, and selection. | Required behavior; conditional path |
| `src/assets/svelte/dashboard/graph/unified/layout.ts` | Add deterministic Arrange behavior and stable segment bounds. | Required behavior; conditional path |
| `src/assets/svelte/dashboard/graph/unified/TopologyToolbar.svelte` | Add Add, Search, Arrange, Fit, Reset, Clear pins, Unplaced count, and Navigator controls. | Conditional split |
| `src/assets/svelte/dashboard/graph/unified/UnplacedTray.svelte` | Show projection issues and unplaced entities. | Conditional split |
| `src/assets/svelte/dashboard/graph/unified/TopologyNavigator.svelte` | Show a segment, host, service, attached-context, and Unplaced tree. | Conditional split |

## Modify

### Elixir

| File | Symbols and work | Dependency | Status |
|---|---|---|---|
| `src/lib/network_defense/graph/contracts/graph_contract.ex` | Add `GraphContract.to_domain/2`. Reuse `Graph.hydrate/4`. Draft projection sets `validate_membership: false`. Keep shape and dangling-edge validation. | None | Required |
| `src/lib/network_defense_web/contracts/dashboard/graph/open_graph_reply.ex` | Add `topology_projection`. | Projection contracts | Required |
| `src/lib/network_defense_web/contracts/dashboard/graph/save_graph_reply.ex` | Add `topology_projection`. | Projection contracts | Required |
| `src/lib/network_defense_web/live/web/dashboard/dashboard_live.ex` | Project Open and Save domain graphs. Add `handle_event("project_topology_draft", ...)`. Delete the saved-only projection event and helpers. | Projector, conversion, contracts | Required |

### Browser

| File | Symbols and work | Dependency | Status |
|---|---|---|---|
| `src/assets/svelte/dashboard/dashboard-api.ts` | Replace `fetchGraphProjection` with `projectTopologyDraft`. | Generated contracts and LiveView event | Required |
| `src/assets/svelte/dashboard/graph/EditableGraphDocument.svelte.ts` | Compose the projection model. Update load, save, recovery, and graph-mutation paths. Capture the semantic version at save start. Do not refresh projection after geometry-only changes. | Projection model | Required |
| `src/assets/svelte/dashboard/workspace/WorkspaceModel.svelte.ts` | Pass bundled projections into new editable documents. Treat a missing projection as invalid when an Open reply creates an editable document. | Editable document | Required |
| `src/assets/svelte/dashboard/inspector/graph/GraphInspector.svelte` | Show document-level projection state and placement issues where applicable. | Scene/model | Conditional placement |
| `src/assets/svelte/dashboard/inspector/graph/SelectionInspector.svelte` | Pass projection data to selection fields. Add pin, placement, relationship, and draft-reachability sections. | Scene/model | Required behavior; conditional split |
| `src/assets/svelte/dashboard/inspector/graph/selection-inspector-presentation.ts` | Add presentation metadata only if the inspector builds sections from this module. | Inspector decision | Conditional |
| `src/assets/svelte/dashboard/inspector/mission-capabilities/RequiredFlowsField.svelte` | Stop calling `fetchGraphProjection`. Read flow groups from the document's accepted projection or from another approved source. | Flow interface decision | Required change; blocked |
| `src/assets/svelte/dashboard/simulation-report/HeatmapCanvas.svelte` | Remove `NetworkCanvas` and `projectNetwork`. Use the unified read-only canvas. Decide how reports receive a projection. | Report projection decision | Required change; blocked |
| `src/assets/svelte/dashboard/simulation-report/SimulationReport.svelte` | Pass the projection if the report document owns it. | Report projection decision | Conditional |
| `src/assets/svelte/dashboard/simulation-report/SimulationReportDocument.svelte.ts` | Store or request the projection if report rendering needs it. | Report projection decision | Conditional |
| `src/assets/svelte/dashboard/graph/layout/ForceLayout.svelte.ts` | Delete force layout or replace `resolveOwnership` with accepted projection data. The design favors deletion. | Cutover decision | Required decision |
| `src/assets/svelte/Dashboard.svelte` | Remove force-layout actions. Move topology actions to the canvas toolbar. | Unified canvas | Conditional wiring |
| `src/assets/svelte/dashboard/ribbon/DashboardRibbon.svelte` | Remove moved Arrange and Force layout controls. | Toolbar decision | Conditional wiring |
| `src/assets/svelte/dashboard/graph/canvas/canvasState.ts` | Extend shared state only if semantic zoom, pins, or focus need shared primitives. | Unified canvas | Conditional |
| `src/assets/svelte/dashboard/graph/canvas/Canvas.svelte` | Extend shared rendering only if the unified canvas can reuse it without semantic coupling. | Unified canvas | Conditional |
| `src/assets/svelte/dashboard/graph/canvas/EditableCanvas.svelte` | Replace any old Network canvas integration with the unified canvas. | Unified canvas | Required consumer migration |
| `src/assets/svelte/ui-kit/workspace/DocumentOutline.svelte` | Change only if the topology Navigator can reuse this generic component. | Navigator decision | Conditional |

Update API mocks if TypeScript reports missing interface members:

- `src/assets/svelte/dashboard/__tests__/DashboardModel.svelte.test.ts`
- `src/assets/svelte/dashboard/manifest/ManifestModel.svelte.test.ts`

## Delete during coordinated cutover

### Elixir contracts

- `src/lib/network_defense_web/contracts/dashboard/graph/fetch_graph_projection_payload.ex`
- `src/lib/network_defense_web/contracts/dashboard/graph/fetch_graph_projection_reply.ex`
- `src/lib/network_defense_web/contracts/dashboard/graph/graph_projection_segment.ex`
- `src/lib/network_defense_web/contracts/dashboard/graph/graph_projection_host.ex`
- `src/lib/network_defense_web/contracts/dashboard/graph/graph_projection_policy_link.ex`
- `src/lib/network_defense_web/contracts/dashboard/graph/graph_projection_operational_flow.ex`

Delete these symbols from `dashboard_live.ex`:

- `handle_event("fetch_graph_projection", ...)`
- `graph_projection/1`
- `build_graph_projection/1`
- `projection_ids/2`
- `projection_links/2`
- `graph_projection_reply/1-2`

### Browser

Delete these files after all consumers use the unified path:

- `src/assets/svelte/dashboard/graph/network/NetworkCanvasProjection.ts`
- `src/assets/svelte/dashboard/graph/network/NetworkCanvasProjection.test.ts`
- `src/assets/svelte/dashboard/graph/network/NetworkCanvas.svelte`
- `src/assets/svelte/dashboard/graph/network/NetworkCanvas.svelte.test.ts`
- `src/assets/svelte/dashboard/graph/network/NetworkCanvasLayout.ts`
- `src/assets/svelte/dashboard/graph/network/NetworkCanvasLayout.test.ts`
- `src/assets/svelte/dashboard/graph/ownership.ts`

Extract reusable browser geometry before deletion. Do not keep a TypeScript semantic fallback.

## Generated outputs

Run `mix gen.contracts` after the Elixir contract changes. Do not edit these files by hand.

- `src/assets/svelte/contracts.generated.ts`
- `src/assets/svelte/contracts.generated.runtime.ts`
- `src/assets/svelte/contracts.generated/dashboard/graph.ts`

The generator can update other barrels. Check the generated diff.

## Tests

### Add

| File | Coverage |
|---|---|
| `src/test/network_defense/graph/topology_projection_test.exs` | Membership, attachments, anchors, self-policy, flow groups, counts, deterministic order, and each issue code. Port semantic fixtures from `NetworkCanvasProjection.test.ts`. |
| `src/assets/svelte/dashboard/graph/__tests__/TopologyProjectionModel.svelte.test.ts` | Fingerprints, urgency, request versions, stale replies, save conflicts, and deletion pruning. |
| `src/assets/svelte/dashboard/graph/__tests__/topology-scene.test.ts` | ID joins, missing references, Unplaced data, and absence of raw-edge inference. |
| Tests beside the unified canvas | Stable world coordinates, zoom hysteresis, keyboard focus, pins, drag rules, pending state, and placement issues. |

### Modify

| File | Coverage |
|---|---|
| `src/test/network_defense/graph/contracts_test.exs` | `GraphContract.to_domain/2`, best-effort membership, shape errors, and dangling edges. |
| `src/test/network_defense_web/live/dashboard_live_test.exs` | Bundled Open/Save projections and `project_topology_draft` results. Delete saved-only endpoint tests. |
| `src/test/network_defense_web/dashboard_contracts_test.exs` | New projection contracts and Open/Save fields. Delete old projection contract tests. |
| `src/assets/svelte/dashboard/dashboard-api.test.ts` | Draft projection event and updated Open/Save fixtures. |
| `src/assets/svelte/dashboard/graph/__tests__/EditableGraphDocument.svelte.test.ts` | Projection lifecycle and save conflicts. |
| `src/assets/svelte/dashboard/workspace/__tests__/WorkspaceModel.svelte.test.ts` | Bundled projection handoff and missing-projection errors for editable opens. |
| `src/assets/svelte/Dashboard.svelte.test.ts` | Toolbar wiring, if it changes. |
| `src/assets/svelte/dashboard/ribbon/DashboardRibbon.svelte.test.ts` | Removed ribbon actions, if they move. |
| `src/assets/svelte/dashboard/simulation-report/SimulationReport.svelte.test.ts` | Unified heatmap canvas, after the report projection decision. |
| `src/assets/svelte/dashboard/simulation-report/heatmap.test.ts` | Heat appearance on unified scene data, if needed. |

### Migrate before deletion

- Move semantic projection cases from `NetworkCanvasProjection.test.ts` to the Elixir projector tests.
- Move deterministic layout cases from `NetworkCanvasLayout.test.ts` to the unified layout tests.
- Move applicable interaction cases from `NetworkCanvas.svelte.test.ts` to unified canvas tests.
- Do not retain expand/collapse tests that conflict with stable segment geometry.

## Documentation

| File | Change | Status |
|---|---|---|
| `docs/design/dashboard.md` | Explain the single topology canvas, bundled projection lifecycle, draft requests, stale-response rejection, Unplaced behavior, and projection errors. | Required |
| `docs/concepts/graph.md` | Explain why Elixir owns graph meaning and the browser owns geometry. | Required |
| `docs/architecture.md` | Change only if its current diagrams or text describe the old projection flow. | Conditional |
| `docs/concepts/requirements.md` | Add user-observable requirements only if the existing requirements need them. | Conditional |
| `docs/concepts/vocabulary.md` | Define new terms only if readers cannot infer them from the UI. | Conditional |

## Files that should remain unchanged

- `src/lib/network_defense/graph/graph.ex`
- `src/lib/network_defense/graph/materialize_reachability.ex`
- `src/lib/network_defense/graph/contracts/save_graph_contract.ex`
- `src/lib/network_defense/nodes/*.ex`
- `src/lib/network_defense/relationships/*.ex`
- `src/assets/svelte/dashboard/graph/presentation/registry.ts`
- `src/assets/svelte/dashboard/graph/presentation/nodes/*`
- `src/assets/svelte/dashboard/graph/presentation/edges/*`
- `src/assets/svelte/dashboard/graph/canvas/CanvasNode.svelte`
- `src/assets/svelte/dashboard/graph/canvas/CanvasEdge.svelte`
- `src/assets/svelte/dashboard/graph/canvas/appearance.ts`
- `src/assets/svelte/dashboard/graph/canvas/geometry.ts`
- `src/assets/svelte/dashboard/graph/canvas/fitView.ts`
- `src/assets/svelte/ui-kit/workspace/WorkspaceModel.svelte.ts`
- `src/assets/svelte/ui-kit/workspace/WorkspaceDocument.svelte.ts`
- `src/assets/svelte/dashboard/workspace/workspace-persistence.ts`

A conditional canvas extension can still change a shared canvas file. Do not add graph semantics to a generic UI module.

## Dependency order

1. Add the pure Elixir projector and tests.
2. Add `GraphContract.to_domain/2` and tests.
3. Add the web contracts and Open/Save fields.
4. Regenerate TypeScript contracts.
5. Add the draft event. Bundle projections into Open and Save.
6. Replace the browser API method.
7. Add the browser projection model. Compose it into editable documents.
8. Add the scene adapter.
9. Add the unified canvas, layout, toolbar, Navigator, Unplaced tray, and inspector sections.
10. Migrate mission-flow and simulation-report consumers.
11. Delete the old projector, renderer, layout, endpoint, contracts, ownership helper, and obsolete controls.
12. Update documentation and run the full post-change checks.

## Decisions required before implementation

### Mission required-flow source

`RequiredFlowsField.svelte` calls the endpoint that the design deletes. Its replacement must use the accepted projection or a new approved input. The new flow-group shape must still provide source-segment and target-service choices.

### Simulation report projection

`HeatmapCanvas.svelte` calls `projectNetwork` directly. The report has a graph and operational flows, but it has no `TopologyProjection`. Choose one source:

- include a projection in the simulation report lifecycle, or
- request a projection for the report graph through an approved server interface.

Do not retain the TypeScript projector.

### Force layout

`ForceLayout.svelte.ts` calls `resolveOwnership`. Delete Force layout or drive it from the accepted projection. Deletion best matches the explicit Arrange design.

### Toolbar ownership

The application ribbon owns Arrange and Force layout today. The design places topology actions in the canvas toolbar. Confirm which ribbon actions move or disappear.

### Comparison Open replies

The graph-comparison picker calls `openGraph` to load a comparison base. It does not create an editable document. It can ignore the bundled projection. Editable opens must reject an otherwise successful reply that has no projection.
