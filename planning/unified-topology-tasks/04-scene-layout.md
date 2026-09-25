# Chunk 04: Scene and Layout

## Objective

Add pure browser adapters for projection-to-scene joins and deterministic geometry.

## Dependency

Chunk 03 must pass.

## Scope

- Add `src/assets/svelte/dashboard/graph/topology-scene.ts`.
- Add `src/assets/svelte/dashboard/graph/unified/layout.ts`.
- Add focused tests for both modules.
- Reuse useful geometry concepts from `NetworkCanvasLayout.ts`. Do not import its semantic projector.

## Scene rules

- Join projection records to graph entities by ID.
- Preserve issue and anchor data for UI consumers.
- Produce segments, attachments, policy groups, flow groups, and Unplaced items.
- Put missing projection references in Unplaced output.
- Do not infer graph meaning from raw edges.

## Layout rules

- Treat segment positions as stable world-space anchors.
- Pack hosts and services inside tight segment bounds.
- Keep attached context outside segment bounds.
- Prevent segment overlap during Arrange.
- Keep deterministic order and output.
- Preserve authored positions unless the user invokes Arrange or new items need initial placement.

## Acceptance

- Scene tests prove that raw-edge inference is absent.
- Layout tests cover stable output, tight bounds, non-overlap, and external context.
- The modules do not call the server and do not depend on Svelte component state.

## Focused checks

Run the new unit tests, TypeScript checks, and formatting.
