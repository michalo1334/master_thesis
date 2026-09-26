# Chunk 05: Canvas Spatial View Model

## Objective

Address comments `4111198083` and `4111198350`.

## Scope

Extract pure builders for:

- entity and frame rectangles;
- host rows with nested visible service rows.

Use the graph-level scene index and layout output.

## Constraints

- Do not move Svelte state or event callbacks into pure modules.
- Preserve semantic zoom and focus disclosure.
- Preserve map keys and deterministic view order.

## Acceptance

- The component consumes flat rectangle and host-view data.
- Pure builders have focused tests.
- Visible cards and positions do not change.

## Checks

Run `TopologyCanvas.svelte.test.ts`, scene-index tests, semantic-zoom tests, graph tests, and typecheck.
