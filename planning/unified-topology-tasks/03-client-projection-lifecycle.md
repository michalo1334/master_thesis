# Chunk 03: Client Projection Lifecycle

## Objective

Add semantic freshness, request ordering, and projection state to editable graph documents.

## Dependency

Chunk 02 must pass and generated contracts must be current.

## Scope

- Add `src/assets/svelte/dashboard/graph/topology-projection-model.svelte.ts`.
- Add `projectTopologyDraft` to `dashboard-api.ts`.
- Compose the model into `EditableGraphDocument.svelte.ts`.
- Pass bundled projections through editable Open paths in `WorkspaceModel.svelte.ts`.
- Update API, document, and workspace tests.

Do not remove `fetchGraphProjection` yet. Chunk 08 migrates its last consumer. Chunk 09 deletes it.

## Required lifecycle

- The fingerprint includes node IDs, node types, node data, edge IDs, endpoints, edge types, and edge data.
- The fingerprint excludes title, revision metadata, and all `view_data`.
- Structural changes request immediately.
- Inspector field changes use a configurable 300 ms debounce.
- Geometry-only changes do not change the semantic version.
- Draft replies apply only when document ID and semantic version match.
- Save captures the semantic version at request start. A matching Save projection can replace current projection. A stale Save projection cannot overwrite newer draft meaning.
- Blank documents start with an empty ready projection.
- Editable Open requires graph and projection.
- Comparison-base Open can ignore projection because it does not create an editable document.
- Recovery uses the same freshness rules as normal Open.

## Acceptance

- Tests cover fingerprint exclusions, immediate and debounced requests, stale draft replies, save conflicts, Open validation, and recovery.
- The model prunes browser state for deleted entities.
- No scene or canvas logic enters the model.

## Focused checks

Run dashboard API tests, editable-document tests, workspace-model tests, Svelte checks for changed files, and formatting.
