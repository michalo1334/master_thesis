# Chunk 09: Cutover and Documentation

## Objective

Delete the old topology paths and document the final ownership boundary.

## Dependency

Chunk 08 must pass. Confirm that no old caller remains before deletion.

## Delete

Delete the old files and symbols listed in `planning/unified-topology-file-map.md`, including:

- saved-only projection payload, reply, and projection contract modules;
- `fetch_graph_projection` event and helper functions;
- `DashboardApi.fetchGraphProjection`;
- `NetworkCanvasProjection.ts` and its tests;
- `NetworkCanvas.svelte` and its tests;
- `NetworkCanvasLayout.ts` and its tests;
- `ownership.ts`;
- obsolete imports, aliases, mode toggles, and ribbon handlers.

Regenerate TypeScript contracts after old Elixir contracts are removed.

Do not retain a wrapper, alias, fallback, feature flag, or dead compatibility path.

## Documentation

Update only the necessary sections in:

- `docs/design/dashboard.md`;
- `docs/concepts/graph.md`;
- `docs/architecture.md` only if it describes the old flow.

Document why Elixir owns graph meaning and why the browser owns geometry. Do not copy contract fields or source values into documentation.

## Acceptance

Repository search finds no production reference to:

- `fetch_graph_projection`;
- `fetchGraphProjection`;
- `GraphProjectionOperationalFlow`;
- `GraphProjectionPolicyLink`;
- `projectNetwork`;
- `NetworkCanvas`;
- `resolveOwnership`;
- the old Topology/Network mode toggle.

The generated contract files match the remaining Elixir contracts.

## Focused checks

Run affected backend and frontend tests, contract generation checks, Svelte checks, formatting, and repository searches for deleted symbols.
