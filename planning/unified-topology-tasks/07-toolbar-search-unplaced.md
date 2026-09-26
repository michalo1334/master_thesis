# Chunk 07: Toolbar, Search, and Unplaced

## Objective

Add canvas-local controls, search, and placement feedback for the unified topology.

## Dependency

Chunk 06 must pass.

## Scope

- Add a compact topology toolbar.
- Add search.
- Add the Unplaced tray.
- Move Arrange from the application ribbon to the canvas toolbar.
- Remove the Force layout action and implementation.
- Update dashboard, ribbon, canvas, and search tests.

## Toolbar

Provide Add, Search, Arrange, Fit, Reset, Clear pins, and the Unplaced count. Disable or hide actions only when the existing document state requires it.

## Search

Search results select and focus the same canvas entity. Search does not create a second semantic model.

## Unplaced tray

- Read its content from scene projection issues.
- Show the reason and related entities.
- Selection focuses the entity and opens its inspector.
- Do not let drag gestures invent ownership or anchoring relationships.

## Arrange

Arrange uses the deterministic layout. Fit and Reset change viewport state only. None of these actions requests a projection.

## Acceptance

- The application ribbon no longer owns topology Arrange or Force layout.
- `ForceLayout.svelte.ts` and its tests are removed if no caller remains.
- Toolbar, search, and Unplaced actions share selection and focus state with the canvas.
- Tests cover action wiring and geometry-only behavior.

## Focused checks

Run dashboard, ribbon, search, Unplaced, unified-canvas, and layout tests. Run Svelte checks and formatting.
