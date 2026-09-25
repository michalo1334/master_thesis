# Chunk 07: Toolbar, Navigator, and Unplaced

## Objective

Add canvas-local controls and alternate navigation for the unified topology.

## Dependency

Chunk 06 must pass.

## Scope

- Add a compact topology toolbar.
- Add search and the topology Navigator.
- Add the Unplaced tray.
- Move Arrange from the application ribbon to the canvas toolbar.
- Remove the Force layout action and implementation.
- Update dashboard, ribbon, canvas, and navigation tests.

## Toolbar

Provide Add, Search, Arrange, Fit, Reset, Clear pins, Unplaced count, and Navigator toggle. Disable or hide actions only when the existing document state requires it.

## Navigator

Show this hierarchy:

- segment;
- host;
- service;
- attached context;
- Unplaced.

Selecting an item focuses the same canvas entity. Search results also focus the canvas. Do not create a second semantic model.

## Unplaced tray

- Read its content from scene projection issues.
- Show the reason and related entities.
- Selection focuses the entity and opens its inspector.
- Do not let drag gestures invent ownership or anchoring relationships.

## Arrange

Arrange uses the new deterministic layout. Fit and Reset change viewport state only. None of these actions requests a new projection.

## Acceptance

- The application ribbon no longer owns topology Arrange or Force layout.
- `ForceLayout.svelte.ts` and its tests are removed if no caller remains.
- Toolbar, search, Navigator, and Unplaced actions share selection and focus state with the canvas.
- Tests cover action wiring and geometry-only behavior.

## Focused checks

Run dashboard, ribbon, navigator, unified-canvas, and layout tests. Run Svelte checks and formatting.
