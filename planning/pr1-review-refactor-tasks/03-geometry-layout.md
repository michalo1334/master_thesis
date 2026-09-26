# Chunk 03: Geometry and Layout

## Objective

Address comments `4111188415`, `4111190565`, `4111191622`, `4111193501`, `4111194037`, and `4111194754`.

## Scope

- Import `Point` from `canvas/canvasState.ts`.
- Put shared `Size` and `Rect` types in `unified/canvas-geometry.ts`.
- Replace local rectangle construction with the shared helper.
- Move rectangle inflation, overlap, and strict interior containment into `unified/canvas-geometry.ts`.
- Keep inclusive pointer hit-testing separate from strict layout containment.
- Add `unified/ordering.ts` only if layout and `topology-bundles.ts` share the comparator.
- Replace repeated nested member traversal with one tested member visitor or flat member sequence.

## Constraints

- Preserve exact Arrange and measure output.
- Do not use locale-dependent ordering.
- Do not merge strict interior containment with inclusive pointer hit-testing.
- Do not move topology placement policy into generic geometry helpers.

## Acceptance

- `layout.ts` contains placement policy, not duplicate geometry primitives.
- Serialized Arrange and measure results remain unchanged.
- Rectangle boundary semantics have focused tests.

## Checks

Run `unified/layout.test.ts`, `unified/canvas-geometry.test.ts`, graph tests, typecheck, formatting, and style checks.
