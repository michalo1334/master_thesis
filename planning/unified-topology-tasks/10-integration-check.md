# Chunk 10: Integration Check

## Objective

Check the complete implementation and fix defects within the approved design.

## Dependency

Chunk 09 must pass.

## Review

Check the full diff against:

- `planning/unified-topology-design.md`;
- `planning/grilling-topology-projection-boundary.md`;
- `planning/unified-topology-file-map.md`;
- all prior chunk acceptance criteria.

Check these boundaries:

- Elixir is the only owner of graph-semantic projection.
- The browser is the only owner of geometry and interaction.
- Semantic versions ignore geometry-only edits.
- Open, Save, draft projection, recovery, mission-flow editing, and simulation reports use the new projection.
- No compatibility path remains.

## Focused checks

Run the repository's standard:

- formatter checks;
- Elixir tests;
- frontend unit tests;
- TypeScript and Svelte checks;
- lint or static analysis;
- contract generation consistency checks.

Use focused reruns to diagnose failures. Fix failures caused by this implementation. Report unrelated pre-existing failures without changing unrelated code.

## Playwright CLI post-check

After automated checks pass, use the `playwright-cli` skill with DeepSeek 4.1 Flash. Start the local application through the repository's documented local workflow. Use snapshots, interactions, request inspection, console inspection, and screenshots where useful.

Check these flows:

1. Open a graph and confirm that the topology appears immediately.
2. Move an entity and confirm that no semantic projection request occurs.
3. Change a semantic field and confirm that projection feedback appears.
4. Select, focus, pin, unpin, search, and use the Navigator.
5. Arrange, Fit, Reset, and open the Unplaced tray.
6. Open a simulation report and confirm heat appearance on the unified canvas.
7. Check the browser console and failed requests after each main flow.

Record the tested URL, viewport, commands, screenshots, console findings, request findings, and defects. Close the browser session and local process after the check.

## Acceptance

- All relevant automated checks pass.
- The repository contains no old projection or Network-renderer path.
- The implementation matches the UX and architecture documents.
- The final report lists checks, results, and any unresolved external blocker.
