# Chunk 02: Server Projection Transport

## Objective

Expose the Elixir projection through generated contracts, Open, Save, and draft projection.

## Dependency

Chunk 01 must pass.

## Scope

- Add all `topology_projection*.ex` contract modules listed in the file map.
- Add `project_topology_draft_payload.ex` and `project_topology_draft_reply.ex`.
- Add `topology_projection` to `open_graph_reply.ex` and `save_graph_reply.ex`.
- Add `handle_event("project_topology_draft", ...)` to `dashboard_live.ex`.
- Bundle a projection into successful Open and Save replies.
- Generate TypeScript contracts with `mix gen.contracts`.
- Update web contract and LiveView tests.

Keep the old saved-only event and old contracts until Chunk 09. The temporary coexistence must not add an adapter, fallback, or feature flag.

## Wire rules

- The draft payload contains `document_id`, `semantic_version`, and the full `GraphContract`.
- The draft reply echoes `document_id` and `semantic_version`.
- The draft handler calls `GraphContract.to_domain(graph, validate_membership: false)`.
- Incomplete membership returns `ok` with issues.
- Structural invalidity returns `invalid_graph` with validation errors.
- Unexpected failures return the existing unmapped-error shape.
- Error replies do not fabricate a projection.

## Acceptance

- Successful Open and Save replies contain graph and projection from the same domain graph.
- Draft projection does not persist data.
- Generated TypeScript exports all new types.
- Old frontend callers still compile until migration.

## Focused checks

Run dashboard contract tests, the draft/Open/Save LiveView tests, contract generation checks, and the Elixir formatter.
