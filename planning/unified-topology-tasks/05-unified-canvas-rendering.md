# Chunk 05: Unified Canvas Rendering

## Objective

Render the projected graph on one stable, modeless topology canvas.

## Dependency

Chunk 04 must pass.

## Scope

- Add `src/assets/svelte/dashboard/graph/unified/TopologyCanvas.svelte` and small supporting components as needed.
- Connect the canvas to the active editable graph view.
- Reuse the existing presentation registry and generic canvas primitives where they fit.
- Add unified-canvas rendering and semantic-zoom tests.

Do not delete the old Network renderer in this chunk.

## Required rendering

- Segments are tight rounded containers.
- Hosts and services stay inside their segments.
- Vulnerabilities, credentials, and mission capabilities stay outside segment bounds.
- Policy and operational-flow relationships use grouped projection data.
- Zoom changes representation, not world positions.
- Far, medium, and near zoom use the detail rules in the UX design.
- Thresholds use hysteresis.
- Pending, placement-issue, projection-error, and draft-reachability states have distinct cues.
- A projection error keeps the last accepted scene visible and marks it stale.
- Dragging a segment moves its hosts and services. It does not move attached context.
- Dragging an entity changes geometry only. It does not author a graph relationship.

Expose a read-only mode and appearance hooks that the simulation heatmap can use in Chunk 08.

## Acceptance

- A single canvas renders the topology structure and attached context.
- Zoom-level changes preserve positions.
- Component tests cover semantic zoom, pending/error cues, and drag rules.
- No component calls the draft API directly. The document model owns requests.

## Focused checks

Run unified-canvas tests, changed graph-component tests, Svelte checks, and formatting.
