# Chunk 06: Focus, Pins, and Inspector

## Objective

Add local disclosure without adding canvas modes.

## Dependency

Chunk 05 must pass.

## Scope

- Add the adjacency focus lens to the unified canvas.
- Add sticky pin state and Clear pins behavior hooks.
- Update graph and selection inspector components.
- Add keyboard and inspector tests.

## Required behavior

- Pointer selection and keyboard focus activate the same adjacency lens.
- The lens reveals the selected entity, direct structural neighbors, attached context, and relevant grouped relationships.
- Unrelated content dims but remains spatially stable.
- Pin keeps a lens visible after selection changes.
- Unpin returns that neighborhood to the semantic-zoom baseline.
- Delete removes stale pins and focus references.
- The inspector shows pin actions, placement status, typed issues, visible relationship summaries, and draft-reachability status.
- Focus and pin state stay in the browser. They do not enter graph contracts or projection requests.

## Accessibility

- Keyboard focus produces the same disclosure as pointer selection.
- Focus order and accessible names remain clear.
- Every focusable SVG entity has a visible stroke-based `:focus-visible` indicator.
- Connection creation has an exposed keyboard path. Do not nest an interactive connector inside a button role.
- Dimming does not remove focused content from assistive technology.

## Acceptance

- Tests cover selection lens, keyboard lens, pin persistence, unpin, deletion cleanup, and inspector status.
- The implementation does not introduce Overview or Detail modes.

## Focused checks

Run unified-canvas and inspector tests, Svelte checks, accessibility checks available in the repository, and formatting.
