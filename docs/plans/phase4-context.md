# Phase 4 Shared Context

## Boundary

`SegmentReachability` is the authored and persisted `NetworkSegment -> NetworkSegment` policy. It owns protocol and port-range data.

`NetworkReachability` is an empty, deterministic `Host -> Service` marker created only in a materialized operational graph. It is never accepted by canonical contracts, authored by the UI, or persisted in a graph revision.

`GraphDiff` receives canonical revisions. A policy removal is one policy-edge removal; comparison must never expand it into host/service flows.

Operational flows may be rendered in the network view, but must be noninteractive. Policy links remain the only editable reachability relationship.

## Explored State

Phases 1 through 3 are present in the codebase. Canonical persistence rejects operational edges, the materializer creates them in memory, simulations and optimization materialize before traversal, and the dashboard projection returns derived flows read-only.

`graph_diff.ex` compares supplied graph states directly. Phase 4 regression coverage proves policy removal remains an edge-level canonical diff.

At phase start, the active concept documents and thesis chapters still contained direct-reachability claims; the phase audits and follow-up edits removed them. Historical drafts under `docs/initial` should be marked superseded rather than rewritten.

## Allowed Operational Uses

Production uses of `NetworkReachability` are limited to materialization, traversal of a materialized graph, and projection serialization. Its registry and semantic endpoint support remain necessary so the materialized graph can be valid in memory. Persistence and contract code must reject it.

## Worker Rules

Read `README.md`, applicable `AGENTS.md`, this file, and `phase4.md` before editing. Work only on the assigned chunk. Do not commit, add dependencies, migrate data, or broaden the model.

For dashboard work, preserve the repository's Svelte 5 and Vitest conventions. Do not introduce a control, event handler, keyboard path, or label that makes a derived flow editable, selectable, or deletable.

## Checks

Run the smallest relevant Mix or npm test command after each chunk. The final gate runs `mix precommit` from `src`, which includes contract generation, formatting, frontend checks, static analysis, and tests.

## Accepted Results

Chunk 1 adds canonical graph-diff and persisted dashboard comparison regressions. They prove one policy removal remains one removed edge and that neither diff result exposes an operational edge. No production code changed.

Chunk 2 adds dashboard regression coverage without changing components. It verifies policy diff states render read-only, policy links have accessible keyboard selection, and operational flows are labeled but cannot receive focus or change the canvas selection.

Chunk 3 audited every production reachability path. No forbidden authoring, persistence, or presentation path exists. Direct regressions now prove canonical draft creation and optimized-revision persistence reject operational edges.

Chunks 4 through 6 reconcile active concepts, thesis chapters, and historical drafts. Active documentation now describes canonical segment policy and derived operational flows; retired direct-flow and min-cut claims are either removed or explicitly superseded historical material.

The local Terraform stack is available. The host Elixir version does not satisfy this project, so Mix checks run in the stack's Elixir container with test-database connection variables.
