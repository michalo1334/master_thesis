# Chunk 08: Gesture Math

## Objective

Address comments `4111202899` and `4111203073`.

## Scope

Add a pure pointer-math module next to `canvas/canvasState.ts`. Extract and reuse:

- pointer delta;
- drag-threshold detection;
- screen delta to world delta;
- translated position maps when this removes another duplicate loop.

Use the helpers in unified canvas pan and entity drag. Use them in the generic canvas when event behavior matches.

## Constraints

- Do not place shared helpers under `unified/`.
- Preserve request-animation-frame coalescing.
- Preserve click suppression after a real drag.
- Preserve pointer capture and keyboard behavior.

## Acceptance

- Pan and drag use the same threshold math.
- Zoom scaling remains correct.
- The generic canvas does not depend on the unified renderer.

## Checks

Run generic canvas tests, `TopologyCanvas.svelte.test.ts`, editable-document tests, graph tests, typecheck, and Svelte checks.
