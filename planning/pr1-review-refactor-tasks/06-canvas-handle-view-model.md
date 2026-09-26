# Chunk 06: Canvas Handle View Model

## Objective

Address comment `4111199544`.

## Scope

Extract pure connection-handle data from host and service views.

The builder receives current detail plus host and service disclosure predicates. It returns node, position, side, and offset data. Pointer and keyboard callbacks stay in `TopologyCanvas.svelte`.

## Constraints

- Preserve connection source eligibility.
- Preserve pointer and keyboard start behavior.
- Preserve handle side and offset values.
- Do not capture Svelte closures in the pure builder.

## Acceptance

- The component has no nested host-service loop for handle derivation.
- Visible handles and accessible names do not change.
- Pointer and keyboard connection tests pass.

## Checks

Run `TopologyCanvas.svelte.test.ts`, editable-document graph tests, typecheck, Svelte checks, and formatting.
