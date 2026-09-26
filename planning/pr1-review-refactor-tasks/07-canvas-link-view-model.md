# Chunk 07: Canvas Link View Model

## Objective

Address comments `4111202022`, `4111202356`, and `4111203497`.

## Scope

Extract pure builders for:

- service ownership links;
- focused attachment-anchor links;
- drawn entity IDs.

Service ownership traversal uses projected membership. A matching authored `Runs` edge remains required and supplies link identity, label, and appearance.

Context-link derivation receives the active lens, visible IDs, entity rectangles, and entity labels.

Drawn IDs merge projected entity IDs with visible attachments and unplaced floaters.

## Constraints

- Do not infer host-service membership from raw edges.
- Do not draw a service link without a matching `Runs` edge.
- Keep `Contains` lines hidden. That part of comment `4111202022` is already obsolete.
- Preserve bundle, focus, pin, and keyboard-focus cleanup behavior.

## Acceptance

- Link derivation has no nested traversal in the Svelte component.
- Structural link behavior and appearance remain unchanged.
- Unplaced entities remain valid drawn IDs.
- Existing relationship paths and labels remain unchanged.

## Checks

Run `TopologyCanvas.svelte.test.ts`, topology-lens, topology-scene, bundle, inspector, and Unplaced tests.
