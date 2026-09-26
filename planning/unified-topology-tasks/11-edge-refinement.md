# Chunk 11: Navigation and Edge Refinement

> Chunk 12 supersedes this chunk's far-only bundle scope and service-only popover rows. The hierarchy-panel removal and hidden `Contains` lines remain current.

## Objective

Remove the Navigator and reduce edge clutter at far zoom.

## Dependency

Commit `5b5e88567d17e0457a8da9f2f58a961f4082a021` is the implementation checkpoint on `feature/unified-topology-redesign`.

## Remove Navigator

- Delete `TopologyNavigator.svelte` and its tests.
- Remove its toolbar toggle, open state, panel, props, styles, and test fixtures.
- Keep Search. Search must still select, focus, pan, and activate the adjacency lens.
- Keep the Unplaced tray.
- Remove Navigator references from UX and implementation documentation.

## Remove Contains lines

Do not render the authored `Contains` relationship as a line at any zoom level. Segment containment is visible through spatial enclosure. Keep the relationship in graph data and projection semantics. Keep service ownership lines where the near-detail design requires them.

## Far-zoom edge bundles

At far zoom, replace detailed policy and operational-flow lines with one directed bundle per ordered segment pair.

Each bundle contains:

- the source and target segment IDs;
- unique policy edge IDs;
- unique operational flow IDs;
- unique service IDs;
- a connection count equal to the number of unique policy edge IDs plus unique flow IDs.

Render one line and one count label for each non-self bundle. Keep the existing self-policy indicator for self-segment policy. Do not render a loop line to the same segment.

The bundle popover opens on hover, keyboard focus, or click selection. It lists service labels in deterministic order. If the bundle has no service, show `No services`. The line and label must have an accessible name that includes direction, connection count, and service summary.

At medium and near zoom, retain the detailed policy and operational-flow lines.

## Boundaries

- Build bundles from accepted projection groups and scene membership only.
- Use graph data only to resolve service labels and existing edge selection metadata.
- Do not infer segment or host membership from raw edges.
- Do not change the server projection contract.
- Do not persist popover or bundle-selection state.

## Acceptance

- No Navigator component, toolbar control, state, documentation, or test remains.
- Search and Unplaced behavior still pass.
- No rendered structural connector has relationship type `Contains`.
- Far zoom renders one directed bundle per ordered segment pair.
- The bundle count and service list are correct and deterministic.
- Hover, focus, Escape, and click-selection popover behavior is tested.
- Medium and near zoom still render detailed policy and flow lines.
- Self-segment policy has no loop line.

## Focused checks

Run unified-canvas, toolbar, search, Unplaced, scene, layout, inspector, and editable-canvas tests. Run the full frontend suite, Svelte checks, accessibility checks, formatting, and deleted-reference searches.
